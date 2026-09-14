import 'package:flutter/material.dart';

class LogisticsReceiptDialog extends StatefulWidget {
  final Map<String, dynamic> receiptContext;

  const LogisticsReceiptDialog({super.key, required this.receiptContext});

  @override
  State<LogisticsReceiptDialog> createState() => _LogisticsReceiptDialogState();
}

class _LogisticsReceiptDialogState extends State<LogisticsReceiptDialog> {
  final TextEditingController _note = TextEditingController();
  final Map<String, Map<String, TextEditingController>> _lineControllers = {};
  final Map<String, Map<String, Map<String, TextEditingController>>>
  _batchControllers = {};
  final Map<String, String> _serialOutcomes = {};

  String? _error;

  List<Map<String, dynamic>> get _items =>
      ((widget.receiptContext['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _note.dispose();
    for (final controllers in _lineControllers.values) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
    for (final allocations in _batchControllers.values) {
      for (final controllers in allocations.values) {
        for (final controller in controllers.values) {
          controller.dispose();
        }
      }
    }
    super.dispose();
  }

  void _prepare() {
    for (final item in _items) {
      final itemId = item['id'].toString();
      final mode = item['tracking_mode']?.toString() ?? 'none';
      final dispatched = _number(item['dispatched_quantity']);

      if (mode == 'none') {
        _lineControllers[itemId] = _quantityControllers(dispatched);
        continue;
      }

      final allocations = ((item['allocations'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (mode == 'serial') {
        for (final allocation in allocations) {
          _serialOutcomes[allocation['id'].toString()] = 'good';
        }
      } else if (mode == 'batch') {
        final rows = <String, Map<String, TextEditingController>>{};
        for (final allocation in allocations) {
          rows[allocation['id'].toString()] = _quantityControllers(
            _number(allocation['quantity']),
          );
        }
        _batchControllers[itemId] = rows;
      }
    }
  }

  Map<String, TextEditingController> _quantityControllers(double good) => {
    'good': TextEditingController(text: _formatNumber(good)),
    'damaged': TextEditingController(text: '0'),
    'missing': TextEditingController(text: '0'),
    'returned': TextEditingController(text: '0'),
  };

  double _number(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  String _formatNumber(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  double? _parse(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  bool _same(double left, double right) => (left - right).abs() <= 0.000001;

  Map<String, dynamic>? _buildSubmission() {
    final lines = <Map<String, dynamic>>[];

    for (final item in _items) {
      final itemId = item['id'].toString();
      final mode = item['tracking_mode']?.toString() ?? 'none';
      final dispatched = _number(item['dispatched_quantity']);
      final label =
          item['product_name']?.toString() ?? item['sku']?.toString() ?? 'Item';

      if (mode == 'none') {
        final values = _readQuantities(_lineControllers[itemId]!, label);
        if (values == null) {
          return null;
        }
        final total = values.values.fold<double>(
          0,
          (sum, value) => sum + value,
        );
        if (!_same(total, dispatched)) {
          _error =
              '$label must total ${_formatNumber(dispatched)}. Current total: ${_formatNumber(total)}.';
          return null;
        }

        lines.add({
          'transfer_item_id': itemId,
          'good_quantity': values['good'],
          'damaged_quantity': values['damaged'],
          'missing_quantity': values['missing'],
          'returned_quantity': values['returned'],
        });
        continue;
      }

      final allocations = ((item['allocations'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (mode == 'serial') {
        if (allocations.isEmpty && dispatched > 0) {
          _error = '$label has no in-transit serial allocations.';
          return null;
        }

        lines.add({
          'transfer_item_id': itemId,
          'allocations': allocations
              .map(
                (allocation) => {
                  'allocation_id': allocation['id'].toString(),
                  'outcome':
                      _serialOutcomes[allocation['id'].toString()] ?? 'good',
                },
              )
              .toList(),
        });
        continue;
      }

      if (mode == 'batch') {
        if (allocations.isEmpty && dispatched > 0) {
          _error = '$label has no in-transit batch allocations.';
          return null;
        }

        final payload = <Map<String, dynamic>>[];
        for (final allocation in allocations) {
          final allocationId = allocation['id'].toString();
          final controllers = _batchControllers[itemId]?[allocationId];
          if (controllers == null) {
            _error = 'Batch receipt controls are incomplete.';
            return null;
          }

          final batchLabel =
              'Batch ${allocation['batch_number'] ?? allocationId}';
          final values = _readQuantities(controllers, batchLabel);
          if (values == null) {
            return null;
          }

          final expected = _number(allocation['quantity']);
          final total = values.values.fold<double>(
            0,
            (sum, value) => sum + value,
          );
          if (!_same(total, expected)) {
            _error =
                '$batchLabel must total ${_formatNumber(expected)}. Current total: ${_formatNumber(total)}.';
            return null;
          }

          payload.add({
            'allocation_id': allocationId,
            'good_quantity': values['good'],
            'damaged_quantity': values['damaged'],
            'missing_quantity': values['missing'],
            'returned_quantity': values['returned'],
          });
        }

        lines.add({'transfer_item_id': itemId, 'allocations': payload});
        continue;
      }

      _error = 'Unsupported tracking mode: $mode';
      return null;
    }

    return {'lines': lines, 'note': _note.text.trim()};
  }

  Map<String, double>? _readQuantities(
    Map<String, TextEditingController> controllers,
    String label,
  ) {
    final values = <String, double>{};

    for (final entry in controllers.entries) {
      final parsed = _parse(entry.value);
      if (parsed == null || parsed < 0) {
        _error = '$label has an invalid ${entry.key} quantity.';
        return null;
      }
      values[entry.key] = parsed;
    }

    return values;
  }

  void _submit() {
    setState(() {
      _error = null;
    });

    final result = _buildSubmission();
    if (result == null) {
      setState(() {});
      return;
    }

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final transfer =
        widget.receiptContext['transfer_number']?.toString() ?? 'Transfer';

    return AlertDialog(
      title: Text('Receive / Verify $transfer'),
      content: SizedBox(
        width: 920,
        height: 650,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Everything starts as GOOD. Change only the differences. '
                  'Damaged stock is received but kept unavailable. Missing stock '
                  'is recorded as missing. Returned means the stock has physically '
                  'returned to the origin store/warehouse.',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(child: ListView(children: _items.map(_itemCard).toList())),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Receipt note (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.inventory_outlined),
          label: const Text('Finalize Receipt'),
        ),
      ],
    );
  }

  Widget _itemCard(Map<String, dynamic> item) {
    final mode = item['tracking_mode']?.toString() ?? 'none';
    final itemId = item['id'].toString();
    final title = '${item['product_name'] ?? '-'} • ${item['sku'] ?? '-'}';
    final dispatched = _number(item['dispatched_quantity']);

    if (mode == 'none') {
      return Card(
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(title),
          subtitle: Text(
            'Normal stock • Dispatched ${_formatNumber(dispatched)}',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _quantityRow(_lineControllers[itemId]!),
            ),
          ],
        ),
      );
    }

    final allocations = ((item['allocations'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (mode == 'serial') {
      return Card(
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(title),
          subtitle: Text('Serial tracked • ${allocations.length} serial(s)'),
          children: allocations.map((allocation) {
            final allocationId = allocation['id'].toString();
            return ListTile(
              dense: true,
              title: Text(
                allocation['serial_number']?.toString() ?? allocationId,
              ),
              subtitle: const Text('Physical receiving result'),
              trailing: SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  initialValue: _serialOutcomes[allocationId] ?? 'good',
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'good', child: Text('Good')),
                    DropdownMenuItem(value: 'damaged', child: Text('Damaged')),
                    DropdownMenuItem(value: 'missing', child: Text('Missing')),
                    DropdownMenuItem(
                      value: 'returned',
                      child: Text('Returned'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _serialOutcomes[allocationId] = value;
                    });
                  },
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    if (mode == 'batch') {
      return Card(
        child: ExpansionTile(
          initiallyExpanded: true,
          title: Text(title),
          subtitle: Text(
            'Batch tracked • Dispatched ${_formatNumber(dispatched)}',
          ),
          children: allocations.map((allocation) {
            final allocationId = allocation['id'].toString();
            final quantity = _number(allocation['quantity']);
            final controllers = _batchControllers[itemId]![allocationId]!;
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Batch ${allocation['batch_number'] ?? allocationId} • ${_formatNumber(quantity)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  _quantityRow(controllers),
                ],
              ),
            );
          }).toList(),
        ),
      );
    }

    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text('Unsupported tracking mode: $mode'),
      ),
    );
  }

  Widget _quantityRow(Map<String, TextEditingController> controllers) => Row(
    children: [
      Expanded(child: _quantityField(controllers['good']!, 'Good')),
      const SizedBox(width: 8),
      Expanded(child: _quantityField(controllers['damaged']!, 'Damaged')),
      const SizedBox(width: 8),
      Expanded(child: _quantityField(controllers['missing']!, 'Missing')),
      const SizedBox(width: 8),
      Expanded(child: _quantityField(controllers['returned']!, 'Returned')),
    ],
  );

  Widget _quantityField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
}
