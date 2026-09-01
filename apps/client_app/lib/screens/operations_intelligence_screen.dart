import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/operations_intelligence_service.dart';

class OperationsIntelligenceScreen extends StatefulWidget {
  final ClientSession session;
  const OperationsIntelligenceScreen({super.key, required this.session});

  @override
  State<OperationsIntelligenceScreen> createState() =>
      _OperationsIntelligenceScreenState();
}

class _OperationsIntelligenceScreenState
    extends State<OperationsIntelligenceScreen>
    with SingleTickerProviderStateMixin {
  final OperationsIntelligenceService _service = OperationsIntelligenceService();
  final TextEditingController _search = TextEditingController();
  late TabController _tabs;
  bool _loading = true;
  String? _error;
  int _days = 30;
  Map<String, dynamic> _attention = const {};
  List<Map<String, dynamic>> _inventory = const [];
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _suppliers = const [];
  List<Map<String, dynamic>> _reorder = const [];
  List<Map<String, dynamic>> _orders = const [];
  final Set<String> _selectedReorder = <String>{};

  String get _tenantId => widget.session.business.id;
  String? get _locationId => LocationScopeService.selectedLocationId.value;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _search.text.trim();
      final values = await Future.wait<dynamic>([
        _service.attention(tenantId: _tenantId, locationId: _locationId, days: _days),
        _service.inventory(tenantId: _tenantId, locationId: _locationId, days: _days, query: query),
        _service.customerCredit(tenantId: _tenantId, locationId: _locationId, query: query),
        _service.supplierPayables(tenantId: _tenantId, locationId: _locationId, query: query),
        _service.reorder(tenantId: _tenantId, locationId: _locationId, days: _days, query: query),
        _service.purchaseOrders(tenantId: _tenantId, locationId: _locationId, query: query),
      ]);
      if (!mounted) return;
      setState(() {
        _attention = Map<String, dynamic>.from(values[0] as Map);
        _inventory = List<Map<String, dynamic>>.from(values[1] as List);
        _customers = List<Map<String, dynamic>>.from(values[2] as List);
        _suppliers = List<Map<String, dynamic>>.from(values[3] as List);
        _reorder = List<Map<String, dynamic>>.from(values[4] as List);
        _orders = List<Map<String, dynamic>>.from(values[5] as List);
        _selectedReorder.removeWhere((key) => !_reorder.any((row) => _reorderKey(row) == key));
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _n(dynamic value) => (value as num?)?.toDouble() ?? 0;
  String _money(dynamic value) => '${widget.session.currencyCode} ${_n(value).toStringAsFixed(2)}';
  String _qty(dynamic value) => _n(value).toStringAsFixed(_n(value) % 1 == 0 ? 0 : 2);
  String _reorderKey(Map<String, dynamic> row) => '${row['location_id']}|${row['variant_id']}';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Stock Intelligence'),
            Tab(text: 'Customer Credit'),
            Tab(text: 'Supplier Payables'),
            Tab(text: 'Purchase Planning'),
            Tab(text: 'Purchase Orders'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorView()
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _overview(),
                        _stock(),
                        _customerCredit(),
                        _supplierPayables(),
                        _planning(),
                        _purchaseOrders(),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Operations Intelligence', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Live cross-module ERP intelligence: stock, credit, purchasing, transfers, offline POS, tracking and restaurant operations.'),
              ],
            ),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search product / customer / supplier',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _days,
            items: const [14, 30, 60, 90].map((d) => DropdownMenuItem(value: d, child: Text('$d days'))).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _days = value);
              _load();
            },
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh intelligence'),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 12),
                const Text('Operations Intelligence could not load.', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(_error ?? '', textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ]),
            ),
          ),
        ),
      );

  Widget _overview() {
    final cards = <(String, String, IconData)>[
      ('Low stock', '${_attention['low_stock'] ?? 0}', Icons.warning_amber_outlined),
      ('Out of stock', '${_attention['out_of_stock'] ?? 0}', Icons.remove_shopping_cart_outlined),
      ('Dead stock', '${_attention['dead_stock'] ?? 0}', Icons.inventory_2_outlined),
      ('Inventory value', _money(_attention['inventory_value']), Icons.warehouse_outlined),
      ('Receivables', _money(_attention['receivables']), Icons.account_balance_wallet_outlined),
      ('Overdue receivables', _money(_attention['overdue_receivables']), Icons.schedule_outlined),
      ('Supplier payables', _money(_attention['payables']), Icons.payments_outlined),
      ('PR approvals', '${_attention['purchase_requests_awaiting_approval'] ?? 0}', Icons.approval_outlined),
      ('PO approvals', '${_attention['purchase_orders_awaiting_approval'] ?? 0}', Icons.fact_check_outlined),
      ('Draft GRNs', '${_attention['draft_grns'] ?? 0}', Icons.inventory_outlined),
      ('Draft purchase invoices', '${_attention['draft_purchase_invoices'] ?? 0}', Icons.receipt_long_outlined),
      ('Transfers in transit', '${_attention['transfers_in_transit'] ?? 0}', Icons.local_shipping_outlined),
      ('Offline POS conflicts', '${_attention['offline_pos_conflicts'] ?? 0}', Icons.sync_problem_outlined),
      ('Batches expiring ≤30d', '${_attention['batches_expiring_30d'] ?? 0}', Icons.event_busy_outlined),
      ('Warranties expiring ≤30d', '${_attention['warranties_expiring_30d'] ?? 0}', Icons.verified_user_outlined),
      ('Restaurant open orders', '${_attention['restaurant_open_orders'] ?? 0}', Icons.restaurant_outlined),
    ];
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((item) => SizedBox(
            width: 220,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  CircleAvatar(child: Icon(item.$3)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.$1, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Text(item.$2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ])),
                ]),
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('What needs attention', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Demand window: $_days days. These cards now include Purchasing V2 approvals/drafts, warehouse transfers, offline POS conflicts, expiring trace stock/warranties and live restaurant orders. Use the tabs for detailed stock, credit, payables and purchasing analysis.'),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _stock() => _table(
        columns: const ['Store', 'Product', 'SKU', 'Available', 'Reorder', 'Max', 'Avg/day', 'Cover', 'Suggested', 'Value', 'Status'],
        rows: _inventory.map((r) => [
          r['location_name'], r['product_name'], r['sku'], _qty(r['available']), _qty(r['reorder_level']), _qty(r['max_stock']),
          _qty(r['avg_daily_sales']), r['days_cover'] == null ? '—' : '${_n(r['days_cover']).toStringAsFixed(1)} d', _qty(r['suggested_reorder']), _money(r['stock_value']), _status(r['status']),
        ]).toList(),
      );

  Widget _customerCredit() => _table(
        columns: const ['Customer', 'Phone', 'Outstanding', 'Limit', 'Available', 'Usage', 'Current', '1–30', '31–60', '61–90', '90+', 'Status'],
        rows: _customers.map((r) => [
          r['customer_name'], r['phone'], _money(r['total_outstanding']), _money(r['credit_limit']), _money(r['available_credit']),
          r['utilization_pct'] == null ? '—' : '${_n(r['utilization_pct']).toStringAsFixed(1)}%', _money(r['current_amount']), _money(r['days_1_30']),
          _money(r['days_31_60']), _money(r['days_61_90']), _money(r['days_90_plus']), _status(r['status']),
        ]).toList(),
      );

  Widget _supplierPayables() => _table(
        columns: const ['Supplier', 'Phone', 'Outstanding', 'Current', '1–30', '31–60', '61–90', '90+', 'Open invoices', 'Oldest due', 'Status'],
        rows: _suppliers.map((r) => [
          r['supplier_name'], r['phone'], _money(r['total_outstanding']), _money(r['current_amount']), _money(r['days_1_30']),
          _money(r['days_31_60']), _money(r['days_61_90']), _money(r['days_90_plus']), '${r['open_invoice_count'] ?? 0}', r['oldest_due_date'] ?? '—', _status(r['status']),
        ]).toList(),
      );

  Widget _planning() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
        child: Row(children: [
          Expanded(child: Text('${_reorder.length} reorder suggestions • ${_selectedReorder.length} selected')),
          FilledButton.icon(
            onPressed: _selectedReorder.isEmpty ? null : _createSelectedPurchaseOrders,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Create PO from selected'),
          ),
        ]),
      ),
      Expanded(
        child: _table(
          leading: true,
          columns: const ['Store', 'Product', 'SKU', 'Stock', 'Reorder', 'Avg/day', 'Cover', 'Suggested', 'Last supplier', 'Last cost'],
          sourceRows: _reorder,
          rowBuilder: (r) => [
            r['location_name'], r['product_name'], r['sku'], _qty(r['current_stock']), _qty(r['reorder_level']), _qty(r['avg_daily_sales']),
            r['days_cover'] == null ? '—' : '${_n(r['days_cover']).toStringAsFixed(1)} d', _qty(r['suggested_quantity']), r['last_supplier_name'] ?? 'No supplier history', _money(r['last_unit_cost']),
          ],
        ),
      ),
    ]);
  }

  Widget _purchaseOrders() {
    if (_orders.isEmpty) return const Center(child: Text('No purchase orders yet.'));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = _orders[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
            title: Text('${row['order_number']} • ${row['supplier_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${row['location_name']} • ${row['order_date']} • ${row['item_count']} items • ${_money(row['grand_total'])}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _status(row['status']),
              PopupMenuButton<String>(
                tooltip: 'Change status',
                onSelected: (value) => _changeOrderStatus(row, value),
                itemBuilder: (_) => _nextStatuses(row['status']?.toString() ?? '').map((s) => PopupMenuItem(value: s, child: Text(s.toUpperCase()))).toList(),
              ),
            ]),
            onTap: () => _showOrder(row['id'].toString()),
          ),
        );
      },
    );
  }

  List<String> _nextStatuses(String status) => switch (status) {
        'draft' => const ['submitted', 'cancelled'],
        'submitted' => const ['approve', 'reject'],
        'approved' => const ['ordered', 'cancelled'],
        'ordered' => const ['cancelled'],
        'rejected' => const ['submitted', 'cancelled'],
        _ => const <String>[],
      };

  Future<void> _changeOrderStatus(Map<String, dynamic> row, String action) async {
    final purchaseOrderId = row['id'].toString();
    try {
      if (action == 'approve' || action == 'reject') {
        var draftNote = '';
        final approving = action == 'approve';
        final note = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(approving ? 'Approve purchase order' : 'Reject purchase order'),
            content: TextField(
              onChanged: (value) => draftNote = value,
              decoration: InputDecoration(
                labelText: approving ? 'Approval note (optional)' : 'Rejection reason',
              ),
              autofocus: !approving,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Back')),
              FilledButton(
                onPressed: () {
                  final value = draftNote.trim();
                  if (!approving && value.isEmpty) return;
                  Navigator.pop(dialogContext, value);
                },
                child: Text(approving ? 'Approve' : 'Reject'),
              ),
            ],
          ),
        );
        if (note == null) return;
        await _service.decidePurchaseOrder(
          tenantId: _tenantId,
          purchaseOrderId: purchaseOrderId,
          approve: approving,
          note: note,
        );
      } else {
        String reason = '';
        if (action == 'cancelled') {
          var draftReason = '';
          final result = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Cancel purchase order'),
              content: TextField(
                onChanged: (value) => draftReason = value,
                decoration: const InputDecoration(labelText: 'Reason'),
                autofocus: true,
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Back')),
                FilledButton(onPressed: () => Navigator.pop(dialogContext, draftReason.trim()), child: const Text('Cancel PO')),
              ],
            ),
          );
          if (result == null || result.trim().isEmpty) return;
          reason = result;
        }
        await _service.setPurchaseOrderStatus(
          tenantId: _tenantId,
          purchaseOrderId: purchaseOrderId,
          status: action,
          reason: reason,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PO update failed: $error')),
        );
      }
    }
  }

  Future<void> _showOrder(String id) async {
    try {
      final detail = await _service.purchaseOrderDetail(tenantId: _tenantId, purchaseOrderId: id);
      if (!mounted) return;
      final order = Map<String, dynamic>.from(detail['order'] as Map? ?? const {});
      final items = (detail['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final history = (detail['history'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${order['order_number'] ?? 'Purchase Order'} • ${order['status'] ?? ''}'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${order['supplier_name'] ?? ''} • ${order['location_name'] ?? ''}'),
                const SizedBox(height: 12),
                ...items.map((i) => ListTile(
                  dense: true,
                  title: Text('${i['product_name']} • ${i['sku'] ?? ''}'),
                  subtitle: Text('${_qty(i['quantity'])} × ${_money(i['unit_cost'])}'),
                  trailing: Text(_money(i['line_total'])),
                )),
                const Divider(),
                const Text('Status history', style: TextStyle(fontWeight: FontWeight.w800)),
                ...history.map((h) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 18),
                  title: Text('${h['from_status'] ?? 'created'} → ${h['to_status']}'),
                  subtitle: Text('${h['changed_at'] ?? ''}${(h['reason'] ?? '').toString().isEmpty ? '' : ' • ${h['reason']}'}'),
                )),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
        ),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open PO: $error')));
    }
  }

  Future<void> _createSelectedPurchaseOrders() async {
    final rows = _reorder.where((r) => _selectedReorder.contains(_reorderKey(r))).toList();
    if (rows.any((r) => (r['last_supplier_id']?.toString() ?? '').isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Some selected products have no purchase supplier history. Select products with a supplier.')));
      return;
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final key = '${row['location_id']}|${row['last_supplier_id']}';
      groups.putIfAbsent(key, () => []).add(row);
    }
    try {
      for (final entry in groups.entries) {
        final first = entry.value.first;
        await _service.createPurchaseOrder(
          tenantId: _tenantId,
          locationId: first['location_id'].toString(),
          supplierId: first['last_supplier_id'].toString(),
          notes: 'Created from THQ reorder suggestions ($_days-day demand window).',
          items: entry.value.map((r) => <String, dynamic>{
            'variant_id': r['variant_id'],
            'quantity': _n(r['suggested_quantity']),
            'unit_cost': _n(r['last_unit_cost']),
            'tax_rate': _n(r['tax_rate']),
          }).toList(),
        );
      }
      _selectedReorder.clear();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${groups.length} purchase order(s) created as Draft.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PO creation failed: $error')));
    }
  }

  Widget _table({
    required List<String> columns,
    List<List<dynamic>>? rows,
    bool leading = false,
    List<Map<String, dynamic>>? sourceRows,
    List<dynamic> Function(Map<String, dynamic>)? rowBuilder,
  }) {
    final dataRows = sourceRows == null
        ? (rows ?? const <List<dynamic>>[])
        : sourceRows.map((r) => rowBuilder!(r)).toList();
    if (dataRows.isEmpty) return const Center(child: Text('No matching records.'));
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              if (leading) const DataColumn(label: Text('')),
              ...columns.map((c) => DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.w800)))),
            ],
            rows: List<DataRow>.generate(dataRows.length, (index) {
              final source = sourceRows == null ? null : sourceRows[index];
              final selected = source == null ? false : _selectedReorder.contains(_reorderKey(source));
              return DataRow(
                selected: selected,
                cells: [
                  if (leading)
                    DataCell(Checkbox(
                      value: selected,
                      onChanged: (value) => setState(() {
                        final key = _reorderKey(source!);
                        if (value == true) {
                          _selectedReorder.add(key);
                        } else {
                          _selectedReorder.remove(key);
                        }
                      }),
                    )),
                  ...dataRows[index].map((value) => DataCell(value is Widget ? value : Text(value?.toString() ?? ''))),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _status(dynamic value) {
    final text = value?.toString().replaceAll('_', ' ') ?? '';
    final severe = text.contains('critical') || text.contains('out of stock') || text.contains('over limit');
    final warn = text.contains('low stock') || text == 'overdue' || text == 'submitted';
    final color = severe
        ? Theme.of(context).colorScheme.errorContainer
        : warn
            ? Theme.of(context).colorScheme.tertiaryContainer
            : Theme.of(context).colorScheme.secondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(text.isEmpty ? '—' : text.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}
