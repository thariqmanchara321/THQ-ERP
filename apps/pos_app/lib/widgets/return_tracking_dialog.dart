import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<Map<String, dynamic>?> collectReturnTracking(BuildContext context, {
  required String tenantId, required String kind, required String itemId,
  required double quantity,
}) async {
  final result = await Supabase.instance.client.rpc('inventory_return_tracking_context_v633',
    params: {'p_tenant_id': tenantId, 'p_kind': kind, 'p_item_id': itemId});
  if (result is! Map) throw const FormatException('Return tracking details could not be loaded.');
  final data = Map<String, dynamic>.from(result);
  if (data['mode'] == 'none' && data['current_mode'] == 'none') return <String, dynamic>{};
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ReturnTrackingDialog(data: data, kind: kind, quantity: quantity));
}

class _ReturnTrackingDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final String kind;
  final double quantity;
  const _ReturnTrackingDialog({required this.data, required this.kind, required this.quantity});
  @override
  State<_ReturnTrackingDialog> createState() => _ReturnTrackingDialogState();
}

class _ReturnTrackingDialogState extends State<_ReturnTrackingDialog> {
  final _original = TextEditingController();
  final _current = TextEditingController();
  String? _error;
  String get _mode => widget.data['mode']?.toString() ?? 'none';
  String get _currentMode => widget.data['current_mode']?.toString() ?? 'none';
  bool get _changed => widget.data['revision'] != widget.data['current_revision'];
  bool get _needCurrent => _changed && _currentMode != 'none' &&
      (widget.kind == 'purchase' || _mode != _currentMode);

  @override
  void initState() {
    super.initState();
    final originals = (widget.data[_mode == 'serial' ? 'serials' : 'batches'] as List? ?? const []).whereType<Map>().toList();
    if (_mode == 'serial' && originals.length == widget.quantity) {
      _original.text = originals.map((r) => r['serial_number']).join('\n');
    } else if (_mode == 'batch' && originals.length == 1) {
      _original.text = '${originals.first['batch_number']}=${widget.quantity}';
    }
    if (_needCurrent && _currentMode == 'batch' && widget.kind == 'sale') {
      _current.text = 'RET-${DateTime.now().microsecondsSinceEpoch}=${widget.quantity}';
    }
  }

  @override
  void dispose() { _original.dispose(); _current.dispose(); super.dispose(); }

  void _confirm() {
    try {
      final payload = <String, dynamic>{};
      if (_mode == 'serial') payload['serial_numbers'] = parseTrackingSerials(_original.text, widget.quantity);
      if (_mode == 'batch') payload['batches'] = parseTrackingBatches(_original.text, widget.quantity);
      if (_needCurrent && _currentMode == 'serial') payload['current_serial_numbers'] = parseTrackingSerials(_current.text, widget.quantity);
      if (_needCurrent && _currentMode == 'batch') payload['current_batches'] = parseTrackingBatches(_current.text, widget.quantity);
      Navigator.pop(context, payload);
    } on FormatException catch (e) { setState(() => _error = e.message); }
  }

  Widget _field(TextEditingController controller, String mode, String label) => TextField(
    controller: controller, minLines: 2, maxLines: 6, decoration: InputDecoration(labelText: label,
      helperText: mode == 'serial' ? 'One serial number per line.' : 'One per line: BATCH=QUANTITY|YYYY-MM-DD (expiry optional unless required).',
      border: const OutlineInputBorder()));

  @override
  Widget build(BuildContext context) {
    final originals = (widget.data[_mode == 'serial' ? 'serials' : 'batches'] as List? ?? const []);
    final options = widget.data['current_options'] is Map ? widget.data['current_options'] as Map : const {};
    final current = (options[_currentMode == 'serial' ? 'serials' : 'batches'] as List? ?? const []);
    return AlertDialog(title: const Text('Return stock tracking'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min,
        children: [
          Text('Return quantity: ${widget.quantity} base units'),
          Text('Original invoice: $_mode. Current stock: $_currentMode.'),
          const SizedBox(height: 12),
          const Text('Select the goods physically being returned. The system validates the original invoice and the current stock allocation.'),
          if (_mode != 'none') ...[
            const SizedBox(height: 12),
            const Text('Original invoice allocations', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final r in originals) if (r is Map) Text(_mode == 'serial' ? '${r['serial_number']}' : '${r['batch_number']} · ${r['remaining_quantity']} remaining'),
            const SizedBox(height: 8),
            _field(_original, _mode, _mode == 'serial' ? 'Original serial numbers' : 'Original batch quantities'),
          ],
          if (_needCurrent) ...[
            const SizedBox(height: 16),
            Text(widget.kind == 'purchase' ? 'Select the current stock being sent to the supplier' : 'Assign the received stock to the current tracking method'),
            if (widget.kind == 'purchase') for (final r in current) if (r is Map)
              Text(_currentMode == 'serial' ? '${r['serial_number']}' : '${r['batch_number']} · ${r['available_quantity']} available'),
            const SizedBox(height: 8),
            _field(_current, _currentMode, _currentMode == 'serial' ? 'Current serial numbers' : 'Current batch quantities'),
          ],
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _confirm, child: const Text('Use These Allocations'))]);
  }
}
