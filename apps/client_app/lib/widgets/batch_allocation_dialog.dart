import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Quantities and rates in this dialog are always expressed in the base unit.
class BatchAllocationDialog extends StatefulWidget {
  final String tenantId;
  final String variantId;
  final String locationId;
  final String baseUnit;
  final DateTime saleDate;
  final double requiredQuantity;
  final List<Map<String, dynamic>> initial;
  const BatchAllocationDialog({
    super.key,
    required this.tenantId,
    required this.variantId,
    required this.locationId,
    required this.baseUnit,
    required this.saleDate,
    required this.requiredQuantity,
    this.initial = const [],
  });
  @override
  State<BatchAllocationDialog> createState() => _BatchAllocationDialogState();
}

class _BatchAllocationDialogState extends State<BatchAllocationDialog> {
  List<Map<String, dynamic>> _rows = [];
  final Map<String, TextEditingController> _quantities = {};
  bool _loading = true;
  String? _error;
  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final date = widget.saleDate;
      final result = await Supabase.instance.client.rpc(
        'inventory_sale_batches_v628',
        params: {
          'p_tenant_id': widget.tenantId,
          'p_variant_id': widget.variantId,
          'p_location_id': widget.locationId,
          'p_sale_date':
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        },
      );
      if (!mounted) {
        return;
      }
      _rows = (result as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      for (final row in _rows) {
        final id = row['batch_id'].toString();
        final initial = widget.initial.where((b) => b['batch_id'] == id);
        _quantities[id] = TextEditingController(
          text: initial.isEmpty ? '' : initial.first['quantity'].toString(),
        );
      }
    } catch (error) {
      if (mounted) {
        _error = error.toString();
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _save() {
    final selected = <Map<String, dynamic>>[];
    double total = 0;
    for (final row in _rows) {
      final text = _quantities[row['batch_id']]!.text.trim();
      final qty = text.isEmpty ? 0.0 : double.tryParse(text);
      if (qty == null ||
          !qty.isFinite ||
          qty < 0 ||
          qty > _number(row['available_quantity']) + 0.000001) {
        setState(
          () => _error =
              'Enter a valid available quantity for ${row['batch_number']}.',
        );
        return;
      }
      if (qty == 0) {
        continue;
      }
      total += qty;
      selected.add({
        'batch_id': row['batch_id'],
        'batch_number': row['batch_number'],
        'quality_label': row['quality_label'],
        'quantity': qty,
        'selling_price_base': row['selling_price_base'],
      });
    }
    if ((total - widget.requiredQuantity).abs() > 0.000001) {
      setState(
        () => _error =
            'Allocate exactly ${widget.requiredQuantity} ${widget.baseUnit}; selected $total.',
      );
      return;
    }
    Navigator.pop(context, selected);
  }

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose batch / quality'),
    content: SizedBox(
      width: 680,
      height: 420,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Required: ${widget.requiredQuantity} ${widget.baseUnit}. Enter quantity against each quality.',
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _rows.isEmpty
                      ? const Center(
                          child: Text('No eligible batch stock in this yard.'),
                        )
                      : ListView(
                          children: _rows
                              .map(
                                (row) => ListTile(
                                  title: Text(
                                    '${row['batch_number']} • ${row['quality_label'] ?? 'Unlabelled quality'}',
                                  ),
                                  subtitle: Text(
                                    'Available ${row['available_quantity']} ${widget.baseUnit}'
                                    ' • Rate ${row['selling_price_base'] ?? 'standard price'}'
                                    '${row['expiry_on'] == null ? '' : ' • Expiry ${row['expiry_on']}'}',
                                  ),
                                  trailing: SizedBox(
                                    width: 140,
                                    child: TextField(
                                      controller: _quantities[row['batch_id']],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: widget.baseUnit,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _loading || _rows.isEmpty ? null : _save,
        child: const Text('Apply batches'),
      ),
    ],
  );
}
