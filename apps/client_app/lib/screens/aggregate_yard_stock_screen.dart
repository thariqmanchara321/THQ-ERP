import 'package:thq_ui/thq_ui.dart';
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
  bool _isTableView = true;

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
      final saved = await showThqDialog<bool>(
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
      await showThqDialog<void>(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _showProductDetail(Map<String, dynamic> row) {
    final unit = row['base_unit_code']?.toString() ?? '';
    final batches = _list(row['batches']);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${row['product_name']} • SKU ${row['sku']}'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Available ${_qty(row['available'])} $unit • On hand ${_qty(row['on_hand'])} $unit',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Reserved ${_qty(row['reserved'])} • Damaged ${_qty(row['damaged'])} • Quarantine ${_qty(row['quarantine'])}'
                  '\nReceived ${_qty(row['received'])} $unit • Dispatched ${_qty(row['dispatched'])} $unit'
                  '\nAverage Cost ${_money(row['average_cost'])} • Selling ${_money(row['selling_price'])}',
                ),
                const SizedBox(height: 12),
                const Text('Location stock:', style: TextStyle(fontWeight: FontWeight.bold)),
                ..._list(row['locations']).map(
                  (loc) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warehouse_outlined, size: 18),
                    title: Text('${loc['location_name']}'),
                    subtitle: Text('Available ${_qty(loc['available'])} $unit • On hand ${_qty(loc['on_hand'])} $unit'),
                  ),
                ),
                if (batches.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Batches / Quality lots:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...batches.map(
                    (b) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${b['batch_number']} • ${b['quality_label'] ?? 'Standard'}'),
                      subtitle: Text('Available ${_qty(b['available'])} $unit • Cost ${_money(b['purchase_cost_base'])} • Sell ${_money(b['selling_price_base'])}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.history, size: 18),
                            tooltip: 'History',
                            onPressed: () => _history(b),
                          ),
                          if (_manage)
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Edit quality/price',
                              onPressed: () => _editBatch(b, unit),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46,
        title: const Text('Yard Stock & Inventory', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: _isTableView ? 'Switch to Cards view' : 'Switch to Table view',
            icon: Icon(_isTableView ? Icons.grid_view_rounded : Icons.table_rows_rounded),
            onPressed: () => setState(() => _isTableView = !_isTableView),
          ),
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
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _search,
                style: const TextStyle(fontSize: 12),
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  hintText: 'Search material, quality or SKU…',
                  hintStyle: const TextStyle(fontSize: 11.5),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: _load,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 11),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _rows.isEmpty && !_loading
                  ? const Center(child: Text('No materials found.'))
                  : _isTableView
                      ? _buildStockTable(scheme)
                      : _buildStockCards(scheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockTable(ColorScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(2.2), // Material / SKU
            1: FlexColumnWidth(1.2), // Available
            2: FlexColumnWidth(1.2), // On Hand
            3: FlexColumnWidth(1.1), // Received
            4: FlexColumnWidth(1.1), // Dispatched
            5: FlexColumnWidth(1.2), // Avg Cost
            6: FlexColumnWidth(1.2), // Selling
            7: FlexColumnWidth(0.8), // Actions
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text('Material / SKU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text('Available', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text('On Hand', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text('Received', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text('Dispatched', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text('Avg Cost', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Text('Sell Rate', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Detail', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            ..._rows.map((row) {
              final unit = row['base_unit_code']?.toString() ?? '';
              final available = _n(row['available']);
              final inStock = available > 0;

              return TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                ),
                children: [
                  // Material
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: InkWell(
                      onTap: () => _showProductDetail(row),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['product_name'] ?? ''}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                          Text('SKU: ${row['sku'] ?? '—'}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  // Available
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      '${_qty(row['available'])} $unit',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: inStock ? const Color(0xFF00875A) : scheme.error,
                      ),
                    ),
                  ),
                  // On Hand
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      '${_qty(row['on_hand'])} $unit',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  // Received
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      _qty(row['received']),
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  // Dispatched
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      _qty(row['dispatched']),
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  // Cost
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      _money(row['average_cost']),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  // Selling
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      _money(row['selling_price']),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  // Action
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        icon: const Icon(Icons.open_in_new_rounded, size: 15),
                        tooltip: 'View details & batches',
                        onPressed: () => _showProductDetail(row),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStockCards(ColorScheme scheme) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final row = _rows[index];
        final unit = row['base_unit_code']?.toString() ?? '';
        final batches = _list(row['batches']);

        return Card(
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            dense: true,
            title: Text('${row['product_name']} • ${row['sku']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            subtitle: Text(
              'Available ${_qty(row['available'])} $unit • On hand ${_qty(row['on_hand'])} $unit'
              ' • Cost ${_money(row['average_cost'])} • Sell ${_money(row['selling_price'])}',
              style: const TextStyle(fontSize: 11),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Reserved ${_qty(row['reserved'])} • Damaged ${_qty(row['damaged'])} • Quarantine ${_qty(row['quarantine'])}'
                  '\nReceived ${_qty(row['received'])} $unit • Dispatched ${_qty(row['dispatched'])} $unit',
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ),
              ...batches.map(
                (batch) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${batch['batch_number']} • ${batch['quality_label'] ?? 'Standard'}'),
                  subtitle: Text('Available ${_qty(batch['available'])} $unit • Cost ${_money(batch['purchase_cost_base'])} • Sell ${_money(batch['selling_price_base'])}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.history, size: 16),
                        tooltip: 'History',
                        onPressed: () => _history(batch),
                      ),
                      if (_manage)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          tooltip: 'Edit quality/price',
                          onPressed: () => _editBatch(batch, unit),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
