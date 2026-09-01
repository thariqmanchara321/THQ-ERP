import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/tracking_service.dart';

class ProductTrackingPolicyScreen extends StatefulWidget {
  final ClientSession session;
  final String variantId;
  final String productName;
  const ProductTrackingPolicyScreen({super.key, required this.session, required this.variantId, required this.productName});

  @override
  State<ProductTrackingPolicyScreen> createState() => _ProductTrackingPolicyScreenState();
}

class _ProductTrackingPolicyScreenState extends State<ProductTrackingPolicyScreen> {
  final TrackingService _service = TrackingService();
  final _months = TextEditingController(text: '0');
  final _days = TextEditingController(text: '0');
  final _serials = TextEditingController();
  final _note = TextEditingController();
  String _mode = 'none';
  bool _warranty = false;
  bool _requireExpiry = false;
  bool _allowExpired = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _reconciliation;
  final List<Map<String, dynamic>> _batches = [];

  String get _tenantId => widget.session.business.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final policy = await _service.getPolicy(tenantId: _tenantId, variantId: widget.variantId);
      Map<String, dynamic>? reconciliation;
      try {
        reconciliation = await _service.reconciliation(tenantId: _tenantId, variantId: widget.variantId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _mode = policy['tracking_mode']?.toString() ?? 'none';
        _warranty = policy['warranty_enabled'] == true;
        _months.text = (policy['warranty_months'] ?? 0).toString();
        _days.text = (policy['warranty_days'] ?? 0).toString();
        _requireExpiry = policy['require_batch_expiry'] == true;
        _allowExpired = policy['allow_expired_sale'] == true;
        _reconciliation = reconciliation;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _save() async {
    final months = int.tryParse(_months.text.trim()) ?? 0;
    final days = int.tryParse(_days.text.trim()) ?? 0;
    setState(() { _saving = true; _error = null; });
    try {
      await _service.savePolicy(
        tenantId: _tenantId,
        variantId: widget.variantId,
        trackingMode: _mode,
        warrantyEnabled: _warranty,
        warrantyMonths: months,
        warrantyDays: days,
        requireBatchExpiry: _requireExpiry,
        allowExpiredSale: _allowExpired,
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tracking policy saved.')));
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _serialValues() => _serials.text.split(RegExp(r'[\n,;]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();

  Future<void> _register() async {
    setState(() { _saving = true; _error = null; });
    try {
      await _service.registerOpening(
        tenantId: _tenantId,
        variantId: widget.variantId,
        serialNumbers: _mode == 'serial' ? _serialValues() : const [],
        batches: _mode == 'batch' ? _batches : const [],
        note: _note.text,
      );
      _serials.clear();
      _batches.clear();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Existing stock registered for traceability.')));
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addBatch() async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _OpeningBatchDialog());
    if (result != null) setState(() => _batches.add(result));
  }

  @override
  void dispose() {
    _months.dispose(); _days.dispose(); _serials.dispose(); _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(title: const Text('Tracking Policy')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.productName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Choose how physical stock is traced. The normal stock ledger remains the quantity/accounting source of truth.'),
              const SizedBox(height: 20),
              Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Tracking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(initialValue: _mode, decoration: const InputDecoration(labelText: 'Tracking mode', border: OutlineInputBorder()), items: const [
                  DropdownMenuItem(value: 'none', child: Text('No serial / batch tracking')),
                  DropdownMenuItem(value: 'serial', child: Text('Serial number tracking')),
                  DropdownMenuItem(value: 'batch', child: Text('Batch / lot tracking')),
                ], onChanged: _saving ? null : (v) => setState(() => _mode = v ?? 'none')),
                if (_mode == 'batch') ...[
                  const SizedBox(height: 8),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _requireExpiry, onChanged: (v) => setState(() => _requireExpiry = v), title: const Text('Require expiry date on every received batch')),
                  SwitchListTile(contentPadding: EdgeInsets.zero, value: _allowExpired, onChanged: (v) => setState(() => _allowExpired = v), title: const Text('Allow sale from expired batches'), subtitle: const Text('Normally keep this off. FEFO skips expired stock.')),
                ],
              ]))),
              const SizedBox(height: 14),
              Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
                SwitchListTile(contentPadding: EdgeInsets.zero, value: _warranty, onChanged: (v) => setState(() => _warranty = v), title: const Text('Warranty tracking'), subtitle: const Text('Creates warranty records automatically when tracked stock is sold.')),
                if (_warranty) Row(children: [
                  Expanded(child: TextField(controller: _months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Warranty months', border: OutlineInputBorder()))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Extra days', border: OutlineInputBorder()))),
                ]),
              ]))),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving...' : 'Save Policy')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              if (_mode != 'none' && _reconciliation != null) ...[
                const SizedBox(height: 24),
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Existing stock registration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Ledger stock: ${_reconciliation!['stock_quantity'] ?? 0} • Tracked: ${_reconciliation!['tracked_quantity'] ?? 0} • ${_reconciliation!['reconciled'] == true ? 'Reconciled' : 'Registration required'}'),
                  if (_reconciliation!['reconciled'] != true) ...[
                    const SizedBox(height: 14),
                    if (_mode == 'serial') TextField(controller: _serials, minLines: 5, maxLines: 10, decoration: const InputDecoration(labelText: 'Serial numbers', hintText: 'One serial per line (comma also accepted)', border: OutlineInputBorder())),
                    if (_mode == 'batch') ...[
                      ..._batches.asMap().entries.map((e) => ListTile(contentPadding: EdgeInsets.zero, title: Text('${e.value['batch_number']} • Qty ${e.value['quantity']}'), subtitle: Text('MFG ${e.value['manufactured_on'] ?? '-'} • EXP ${e.value['expiry_on'] ?? '-'}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _batches.removeAt(e.key))))),
                      OutlinedButton.icon(onPressed: _addBatch, icon: const Icon(Icons.add), label: const Text('Add Batch')),
                    ],
                    const SizedBox(height: 12),
                    TextField(controller: _note, decoration: const InputDecoration(labelText: 'Registration note (optional)', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _saving ? null : _register, icon: const Icon(Icons.inventory_outlined), label: const Text('Register Existing Stock')),
                  ],
                ]))),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _OpeningBatchDialog extends StatefulWidget {
  const _OpeningBatchDialog();
  @override
  State<_OpeningBatchDialog> createState() => _OpeningBatchDialogState();
}

class _OpeningBatchDialogState extends State<_OpeningBatchDialog> {
  final _number = TextEditingController();
  final _quantity = TextEditingController();
  final _mfg = TextEditingController();
  final _expiry = TextEditingController();
  String? _error;

  @override
  void dispose() { _number.dispose(); _quantity.dispose(); _mfg.dispose(); _expiry.dispose(); super.dispose(); }

  void _save() {
    final qty = double.tryParse(_quantity.text.trim());
    if (_number.text.trim().isEmpty || qty == null || qty <= 0) { setState(() => _error = 'Enter a batch number and positive base quantity.'); return; }
    Navigator.pop(context, <String, dynamic>{
      'batch_number': _number.text.trim(),
      'quantity': qty,
      'manufactured_on': _mfg.text.trim().isEmpty ? null : _mfg.text.trim(),
      'expiry_on': _expiry.text.trim().isEmpty ? null : _expiry.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Batch'),
    content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _number, decoration: const InputDecoration(labelText: 'Batch / lot number', border: OutlineInputBorder())), const SizedBox(height: 10),
      TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantity in base unit', border: OutlineInputBorder())), const SizedBox(height: 10),
      TextField(controller: _mfg, decoration: const InputDecoration(labelText: 'Manufacture date (YYYY-MM-DD)', border: OutlineInputBorder())), const SizedBox(height: 10),
      TextField(controller: _expiry, decoration: const InputDecoration(labelText: 'Expiry date (YYYY-MM-DD)', border: OutlineInputBorder())),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _save, child: const Text('Add'))],
  );
}
