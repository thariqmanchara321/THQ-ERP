import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import '../services/tracking_service.dart';

class AggregateYardStockScreen extends StatefulWidget {
  final ClientSession session;
  const AggregateYardStockScreen({super.key, required this.session});
  @override
  State<AggregateYardStockScreen> createState() =>
      _AggregateYardStockScreenState();
}

class _AggregateYardStockScreenState extends State<AggregateYardStockScreen> {
  final _service = AggregateYardService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  int _request = 0;
  bool get _manage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('aggregate_yard.manage');
  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String _qty(dynamic v) =>
      _n(v).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  String _money(dynamic v) => v == null
      ? '—'
      : '${widget.session.currencyCode} ${_n(v).toStringAsFixed(2)}';
  List<Map<String, dynamic>> _list(dynamic v) => (v as List? ?? [])
      .whereType<Map>()
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_scopeChanged);
    _load();
  }

  void _scopeChanged() {
    _load();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_scopeChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.stock(
        tenantId: widget.session.business.id,
        locationId: LocationScopeService.selectedLocationId.value,
        query: _search.text,
      );
      if (!mounted || request != _request) {
        return;
      }
      setState(() => _rows = rows);
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editBatch(Map<String, dynamic> batch, String unit) async {
    final quality = TextEditingController(
      text: batch['quality_label']?.toString() ?? '',
    );
    final rate = TextEditingController(
      text: batch['selling_price_base']?.toString() ?? '',
    );
    bool saving = false;
    String? error;
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('Batch ${batch['batch_number']}'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: quality,
                    decoration: const InputDecoration(
                      labelText: 'Quality / grade',
                    ),
                  ),
                  TextField(
                    controller: rate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Selling rate per $unit',
                      helperText: 'Leave blank to use standard pricing.',
                    ),
                  ),
                  const Text('Changes apply to future invoices.'),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final value = rate.text.trim().isEmpty
                            ? null
                            : double.tryParse(rate.text.trim());
                        if (rate.text.trim().isNotEmpty &&
                            (value == null || !value.isFinite || value < 0)) {
                          update(
                            () => error = 'Enter a valid nonnegative rate.',
                          );
                          return;
                        }
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await _service.saveBatchProfile(
                            tenantId: widget.session.business.id,
                            batchId: batch['batch_id'].toString(),
                            qualityLabel: quality.text,
                            sellingPriceBase: value,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            update(() {
                              saving = false;
                              error = e.toString();
                            });
                          }
                        }
                      },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (saved == true && mounted) {
        await _load();
      }
    } finally {
      quality.dispose();
      rate.dispose();
    }
  }

  Future<void> _history(Map<String, dynamic> batch) async {
    try {
      final detail = await TrackingService().batchHistory(
        tenantId: widget.session.business.id,
        batchId: batch['batch_id'].toString(),
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Batch ${batch['batch_number']} history'),
          content: SizedBox(
            width: 640,
            height: 420,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (_list(detail['events']).isEmpty)
                    const Text('No movements recorded.'),
                  ..._list(detail['events']).map(
                    (event) => ListTile(
                      title: Text(
                        '${event['event_type']} • ${event['quantity']}',
                      ),
                      subtitle: Text(
                        '${event['created_at']} • ${event['location_name'] ?? ''}'
                        '\n${event['reference_number'] ?? ''} • ${event['customer_name'] ?? event['supplier_name'] ?? ''}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Yard Stock'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: 'Search material / SKU',
              suffixIcon: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                const Text(
                  'Physical yard stock from the inventory ledger. Quantities keep each material’s base unit. '
                  'Load tickets are operational records; posted purchases and sales affect stock.',
                ),
                if (!_loading && _rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No materials found.'),
                  ),
                if (_rows.length >= 1000)
                  const Text(
                    'Showing the first 1,000 materials. Search to narrow the results.',
                  ),
                ..._rows.map((row) {
                  final unit = row['base_unit_code']?.toString() ?? '';
                  final batches = _list(row['batches']);
                  return Card(
                    child: ExpansionTile(
                      title: Text('${row['product_name']} • ${row['sku']}'),
                      subtitle: Text(
                        'Available ${_qty(row['available'])} $unit • On hand ${_qty(row['on_hand'])} $unit'
                        '\nCost ${_money(row['average_cost'])} • Selling ${_money(row['selling_price'])}'
                        ' • ${_n(row['available']) <= 0 ? 'Out of stock' : 'In stock'}',
                      ),
                      childrenPadding: const EdgeInsets.all(12),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Reserved ${_qty(row['reserved'])} • Damaged ${_qty(row['damaged'])} • Quarantine ${_qty(row['quarantine'])}'
                            '\nReceived ${_qty(row['received'])} $unit • Dispatched ${_qty(row['dispatched'])} $unit (posted movements)'
                            '\nCurrent master cost ${_money(row['master_cost_price'])}',
                          ),
                        ),
                        ..._list(row['locations']).map(
                          (location) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.warehouse_outlined),
                            title: Text('${location['location_name']}'),
                            subtitle: Text(
                              'Available ${_qty(location['available'])} $unit • On hand ${_qty(location['on_hand'])} $unit',
                            ),
                          ),
                        ),
                        if (row['tracking_mode'] == 'batch' && batches.isEmpty)
                          const Text(
                            'No batch balances. Check the product’s opening tracking allocation.',
                          ),
                        ...batches.map(
                          (batch) => ListTile(
                            dense: true,
                            title: Text(
                              '${batch['batch_number']} • ${batch['quality_label'] ?? 'Unlabelled quality'}',
                            ),
                            subtitle: Text(
                              'Available ${_qty(batch['available'])} $unit • Reserved ${_qty(batch['reserved'])}'
                              ' • Damaged ${_qty(batch['damaged'])}'
                              '\nCost ${_money(batch['purchase_cost_base'])} • Sell ${_money(batch['selling_price_base'])}'
                              ' • ${batch['status']}',
                            ),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: 'History',
                                  onPressed: () => _history(batch),
                                  icon: const Icon(Icons.history),
                                ),
                                if (_manage)
                                  IconButton(
                                    tooltip: 'Edit quality / rate',
                                    onPressed: () => _editBatch(batch, unit),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
