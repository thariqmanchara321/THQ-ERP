import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/mobile_session.dart';
import '../../../services/mobile_client_service.dart';
import 'material_yard_billing_sheet.dart';
import 'material_yard_load_sheet.dart';
import 'material_yard_types.dart';

class MobileMaterialLoadDetailSheet extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String loadId;
  final VoidCallback onChanged;

  const MobileMaterialLoadDetailSheet({
    super.key,
    required this.session,
    required this.service,
    required this.loadId,
    required this.onChanged,
  });

  @override
  State<MobileMaterialLoadDetailSheet> createState() =>
      _MobileMaterialLoadDetailSheetState();
}

class _MobileMaterialLoadDetailSheetState
    extends State<MobileMaterialLoadDetailSheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _load = const {};
  bool _operating = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.service.materialLoadDetail(
        widget.session,
        loadId: widget.loadId,
      );
      if (!mounted) return;
      setState(() {
        _load = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get isInward =>
      _load['direction']?.toString().toLowerCase() == 'inbound';
  String get status =>
      (_load['status'] ?? 'draft').toString().toLowerCase();
  bool get isDraft => status == 'draft';
  bool get isConfirmed => status == 'confirmed';
  bool get isInvoiced =>
      status == 'invoiced' ||
      _load['invoice_number'] != null ||
      _load['purchase_id'] != null ||
      _load['sale_id'] != null;

  Future<void> _confirmLoad() async {
    setState(() => _operating = true);
    try {
      await widget.service.confirmMaterialLoad(
        widget.session,
        loadId: widget.loadId,
      );
      if (!mounted) return;
      setState(() => _operating = false);
      ThqNotify.success(context, 'Load Confirmed', message: 'Load has been verified and confirmed.');
      widget.onChanged();
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _operating = false);
      ThqNotify.error(context, 'Confirm Failed', message: '$e');
    }
  }

  Future<void> _deleteLoad() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft Load'),
        content: const Text('Are you sure you want to permanently delete this draft load?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _operating = true);
    try {
      await widget.service.deleteMaterialLoad(
        widget.session,
        loadId: widget.loadId,
      );
      if (!mounted) return;
      setState(() => _operating = false);
      ThqNotify.success(context, 'Deleted', message: 'Draft load has been removed.');
      widget.onChanged();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _operating = false);
      ThqNotify.error(context, 'Delete Failed', message: '$e');
    }
  }

  void _editDraft() async {
    final edited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MobileMaterialLoadSheet(
        session: widget.session,
        service: widget.service,
        editingLoad: _load,
        onSaved: () {
          widget.onChanged();
          _reload();
        },
      ),
    );
    if (edited == true && mounted) {
      _reload();
    }
  }

  void _openBilling() async {
    final invoiced = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MobileMaterialBillingSheet(
        session: widget.session,
        service: widget.service,
        load: _load,
        onInvoiced: () {
          widget.onChanged();
          _reload();
        },
      ),
    );
    if (invoiced == true && mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = widget.session.currency;

    if (_loading) {
      return Container(
        height: 350,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('Error loading details: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      );
    }

    final loadNum = _load['load_number'] ?? 'LD-${_load['id']}';
    final truck = _load['vehicle_registration'] ?? _load['vehicle_registration_snapshot'] ?? 'No Truck';
    final driver = _load['driver_name'] ?? _load['driver_name_snapshot'] ?? 'No Driver';
    final driverPhone = _load['driver_phone'] ?? '';
    final material = _load['product_name'] ?? 'Material';
    final variant = _load['variant_name'] ?? '';
    final qty = _load['quantity'] ?? 0;
    final unit = _load['unit_code'] ?? 'CFT';
    final calcCft = _load['calculated_cft'];
    final heapAdj = _load['heap_adjustment_cft'];
    final billableQty = _load['approved_billable_qty'];
    final rawRate = _load['rate'] ?? _load['unit_price'];
    final rate = double.tryParse(rawRate?.toString() ?? '') ?? 0.0;
    final statusColor = MaterialYardFormat.statusColor(status);
    final partyName = isInward
        ? (_load['supplier_name'] ?? 'Quarry Supplier')
        : (_load['customer_name'] ?? 'Direct Yard Customer');
    final invoiceNum = _load['invoice_number'] ?? _load['sale_number'] ?? _load['purchase_number'];
    final costs = (_load['costs'] as List? ?? const []).whereType<Map>().toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(loadNum),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              MaterialYardFormat.statusLabel(status),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            // Header Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isInward ? Icons.south_west_rounded : Icons.north_east_rounded,
                          size: 20,
                          color: isInward ? Colors.teal : Colors.indigo,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isInward ? 'Inward Quarry Load' : 'Outward Sales Load',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isInward ? Colors.teal : Colors.indigo,
                          ),
                        ),
                        const Spacer(),
                        if (_load['load_date'] != null)
                          Text(
                            _load['load_date'].toString().split('T').first,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const Divider(height: 16),
                    Text(
                      '$material${variant.toString().isNotEmpty ? " ($variant)" : ""}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isInward ? "Supplier" : "Customer"}: $partyName',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Invoiced banner if present
            if (invoiceNum != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.receipt_rounded, color: Colors.green.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Linked to ${isInward ? "Purchase Bill" : "Sales Invoice"}',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900, fontSize: 13),
                          ),
                          Text(
                            'Invoice #: $invoiceNum',
                            style: TextStyle(color: Colors.green.shade800, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Physical & Billable Measurements
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Measurement Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMetricTile('Physical Qty', MaterialYardFormat.quantity(qty, unit)),
                        if (calcCft != null && (double.tryParse(calcCft.toString()) ?? 0) > 0)
                          _buildMetricTile('Calculated CFT', MaterialYardFormat.cft(calcCft)),
                        if (billableQty != null && billableQty != qty)
                          _buildMetricTile('Billable Qty', MaterialYardFormat.quantity(billableQty, unit), highlight: true),
                      ],
                    ),
                    if (heapAdj != null && (double.tryParse(heapAdj.toString()) ?? 0) != 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Heap Adjustment: ${MaterialYardFormat.cft(heapAdj)}'
                        '${_load['heap_adjustment_reason'] != null ? " (${_load['heap_adjustment_reason']})" : ""}',
                        style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                    if (_load['raw_dimensions'] is Map) ...[
                      const Divider(height: 16),
                      Text(
                        'Dimensions: ${_load['raw_dimensions']['length'] ?? "-"} × ${_load['raw_dimensions']['width'] ?? "-"} × ${_load['raw_dimensions']['height'] ?? "-"} ${_load['raw_dimensions']['unit'] ?? "in"}',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Vehicle & Driver Details
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Transport & Fleet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text(truck, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('Driver: $driver${driverPhone.isNotEmpty ? " • $driverPhone" : ""}'),
                    ),
                    if (_load['source_name'] != null || _load['destination_name'] != null)
                      Text(
                        '${_load['source_name'] ?? "Yard"} → ${_load['destination_name'] ?? "Site"}',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    if (_load['source_reference'] != null && _load['source_reference'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Quarry Slip: ${_load['source_reference']}',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Rates and Valuation
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Commercial Valuation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rate per $unit', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                        Text(
                          rate > 0 ? MaterialYardFormat.money(rate, currency: currency) : 'Pending',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Estimated Total', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                        Text(
                          rate > 0 ? MaterialYardFormat.money(rate * (billableQty ?? qty), currency: currency) : 'Pending',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: scheme.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (costs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Load Expenses', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      ...costs.map((c) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${c['description']} (${c['payee'] ?? "Self"})', style: const TextStyle(fontSize: 12)),
                              Text(MaterialYardFormat.money(c['amount'], currency: currency), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -3)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDraft) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _operating ? null : _editDraft,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Draft'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Delete Draft',
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      onPressed: _operating ? null : _deleteLoad,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _operating ? null : _confirmLoad,
                        icon: _operating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Confirm Load'),
                      ),
                    ),
                  ],
                ),
              ] else if (isConfirmed && !isInvoiced) ...[
                FilledButton.icon(
                  onPressed: _operating ? null : _openBilling,
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: Text(isInward ? 'Create Purchase Bill' : 'Create Sales Invoice'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: isInward ? Colors.teal.shade700 : scheme.primary,
                  ),
                ),
              ] else if (isInvoiced) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.done_all_rounded, color: Colors.green),
                  label: const Text('Load Invoiced & Posted'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, {bool highlight = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: highlight ? scheme.primary : null,
          ),
        ),
      ],
    );
  }
}
