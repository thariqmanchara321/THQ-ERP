import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/inventory_product.dart';
import '../models/supplier.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/purchasing_v2_service.dart';
import '../services/supplier_service.dart';
import 'purchases_screen.dart';

class PurchasingV2Screen extends StatefulWidget {
  final ClientSession session;

  const PurchasingV2Screen({super.key, required this.session});

  @override
  State<PurchasingV2Screen> createState() => _PurchasingV2ScreenState();
}

class _PurchasingV2ScreenState extends State<PurchasingV2Screen>
    with SingleTickerProviderStateMixin {
  final PurchasingV2Service _service = PurchasingV2Service();
  final InventoryService _inventory = InventoryService();
  final SupplierService _suppliersService = SupplierService();
  final TextEditingController _search = TextEditingController();

  late TabController _tabs;
  bool _loading = true;
  String? _error;
  String? _warning;
  Map<String, dynamic> _dashboard = const {};
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _grns = const [];
  List<Map<String, dynamic>> _invoices = const [];
  List<Map<String, dynamic>> _prices = const [];
  List<InventoryProduct> _products = const [];
  List<Supplier> _suppliers = const [];
  String? _ledgerSupplierId;
  Map<String, dynamic>? _ledger;
  List<Map<String, dynamic>> _supplierPayments = const [];

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('purchases.manage');
  bool get _canApprove =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('approvals.approve');

  String get _currency => widget.session.currencyCode;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    LocationScopeService.selectedLocationId.addListener(_locationChanged);
    _load();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_locationChanged);
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _locationChanged() {
    if (mounted) _load();
  }

  double _n(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _money(dynamic value) => '$_currency ${_n(value).toStringAsFixed(2)}';

  String _qty(dynamic value) {
    final n = _n(value);
    return n == n.roundToDouble()
        ? n.toStringAsFixed(0)
        : n
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  Future<T> _safeLoad<T>(
    Future<T> future,
    T fallback,
    List<String> warnings,
    String label,
  ) async {
    try {
      return await future;
    } catch (error) {
      warnings.add('$label temporarily unavailable');
      return fallback;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _warning = null;
    });

    final warnings = <String>[];
    final query = _search.text.trim();
    try {
      final results = await Future.wait<dynamic>([
        _safeLoad<Map<String, dynamic>>(
          _service.dashboard(widget.session),
          <String, dynamic>{},
          warnings,
          'Dashboard',
        ),
        _safeLoad<List<Map<String, dynamic>>>(
          _service.requests(widget.session, query: query),
          <Map<String, dynamic>>[],
          warnings,
          'Purchase Requests',
        ),
        _safeLoad<List<Map<String, dynamic>>>(
          _service.orders(widget.session, query: query),
          <Map<String, dynamic>>[],
          warnings,
          'Purchase Orders',
        ),
        _safeLoad<List<Map<String, dynamic>>>(
          _service.grns(widget.session, query: query),
          <Map<String, dynamic>>[],
          warnings,
          'GRN',
        ),
        _safeLoad<List<Map<String, dynamic>>>(
          _service.invoices(widget.session, query: query),
          <Map<String, dynamic>>[],
          warnings,
          'Purchase Invoices',
        ),
        _safeLoad<List<Map<String, dynamic>>>(
          _service.priceHistory(widget.session, query: query),
          <Map<String, dynamic>>[],
          warnings,
          'Price History',
        ),
        _safeLoad<List<InventoryProduct>>(
          _inventory.getProducts(
            tenantId: widget.session.business.id,
            locationId: LocationScopeService.currentForRead(widget.session),
          ),
          <InventoryProduct>[],
          warnings,
          'Products',
        ),
        _safeLoad<List<Supplier>>(
          _suppliersService.getSuppliers(tenantId: widget.session.business.id),
          <Supplier>[],
          warnings,
          'Suppliers',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = Map<String, dynamic>.from(results[0] as Map);
        _requests = List<Map<String, dynamic>>.from(results[1] as List);
        _orders = List<Map<String, dynamic>>.from(results[2] as List);
        _grns = List<Map<String, dynamic>>.from(results[3] as List);
        _invoices = List<Map<String, dynamic>>.from(results[4] as List);
        _prices = List<Map<String, dynamic>>.from(results[5] as List);
        _products = List<InventoryProduct>.from(results[6] as List);
        _suppliers = List<Supplier>.from(results[7] as List);
        _warning = warnings.isEmpty
            ? null
            : 'Some Purchase Details sections are temporarily unavailable. Purchase History remains available. ${warnings.join(' • ')}. Refresh after the backend update.';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _message(String message) {
    if (!mounted) return;

    ThqNotify.showSnackBar(context, SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      ThqNotify.showSnackBar(context, SnackBar(content: Text(success)));
      await _load();
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        children: [
          _header(),
          const SizedBox(height: 12),
          _summary(),
          if (_warning != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _warning!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Purchase Requests'),
              Tab(text: 'Purchase Orders'),
              Tab(text: 'GRN'),
              Tab(text: 'Purchase Invoices'),
              Tab(text: 'Supplier Ledger'),
              Tab(text: 'Price History'),
              Tab(text: 'Purchase History'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _requestsTab(),
                      _ordersTab(),
                      _grnTab(),
                      _invoiceTab(),
                      _ledgerTab(),
                      _priceTab(),
                      PurchasesScreen(
                        session: widget.session,
                        historyOnly: true,
                      ),
                    ],
                  ),
                ),
                if (_loading && _tabs.index != 6)
                  const Positioned.fill(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_error != null && _tabs.index != 6)
                  Positioned.fill(child: _errorView()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Purchase Details',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 3),
              Text(
                'PR → PO approval → GRN → Purchase Invoice → Supplier Payment',
              ),
            ],
          ),
        ),
        SizedBox(
          width: 270,
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search purchase details...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
      ],
    );
  }

  Widget _summary() {
    final cards = <(String, dynamic, IconData)>[
      ('Open PR', _dashboard['open_requests'], Icons.assignment_outlined),
      (
        'PO Approval',
        _dashboard['po_awaiting_approval'],
        Icons.approval_outlined,
      ),
      (
        'Open PO',
        _dashboard['open_purchase_orders'],
        Icons.shopping_cart_outlined,
      ),
      (
        'Partial',
        _dashboard['partial_purchase_orders'],
        Icons.call_split_outlined,
      ),
      ('Draft GRN', _dashboard['draft_grns'], Icons.inventory_outlined),
      (
        'Open Invoices',
        _dashboard['open_supplier_invoices'],
        Icons.receipt_long_outlined,
      ),
      (
        'Payable',
        _money(_dashboard['v2_payable_balance']),
        Icons.account_balance_wallet_outlined,
      ),
    ];
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final item = cards[index];
          return Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(item.$3, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${item.$2 ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        item.$1,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _errorView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 10),
        Text(_error ?? 'Unknown error'),
        const SizedBox(height: 10),
        FilledButton(onPressed: _load, child: const Text('Retry')),
      ],
    ),
  );

  Widget _requestsTab() {
    return Column(
      children: [
        _toolbar(
          '${_requests.length} purchase requests',
          _canManage ? () => _newRequest() : null,
          'New Purchase Request',
        ),
        Expanded(
          child: _list(
            _requests,
            empty: 'No purchase requests.',
            tile: (row) => ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.assignment_outlined),
              ),
              title: Text(
                '${row['request_number']} • ${row['purpose'] ?? 'Purchase request'}',
              ),
              subtitle: Text(
                '${row['location_name']} • ${row['request_date']} • ${row['item_count']} items • Qty ${_qty(row['total_quantity'])}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _status(row['status']),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    onSelected: (value) => _requestAction(row, value),
                    itemBuilder: (_) => _requestActions(row)
                        .map(
                          (x) => PopupMenuItem(value: x.$1, child: Text(x.$2)),
                        )
                        .toList(),
                  ),
                ],
              ),
              onTap: () => _showRequest(row['id'].toString()),
            ),
          ),
        ),
      ],
    );
  }

  List<(String, String)> _requestActions(Map<String, dynamic> row) {
    final status = '${row['status']}';
    final out = <(String, String)>[];
    if (status == 'draft' && _canManage) out.add(('submit', 'Submit'));
    if (status == 'submitted' && _canApprove) {
      out.add(('approve', 'Approve'));
      out.add(('reject', 'Reject'));
    }
    if (status == 'approved' && _canManage) {
      out.add(('po', 'Create Purchase Order'));
    }
    if (_canManage &&
        const ['draft', 'submitted', 'approved'].contains(status)) {
      out.add(('cancel', 'Cancel Request'));
    }
    return out;
  }

  Future<void> _requestAction(Map<String, dynamic> row, String action) async {
    if (action == 'submit') {
      await _run(
        () => _service.setRequestStatus(
          widget.session,
          requestId: '${row['id']}',
          status: 'submitted',
        ),
        'Purchase Request submitted.',
      );
    } else if (action == 'approve') {
      await _run(
        () => _service.setRequestStatus(
          widget.session,
          requestId: '${row['id']}',
          status: 'approved',
        ),
        'Purchase Request approved.',
      );
    } else if (action == 'reject') {
      final note = await _textPrompt('Reject Purchase Request', 'Reason');
      if (note == null || note.trim().isEmpty) return;
      await _run(
        () => _service.setRequestStatus(
          widget.session,
          requestId: '${row['id']}',
          status: 'rejected',
          note: note,
        ),
        'Purchase Request rejected.',
      );
    } else if (action == 'po') {
      await _createPoFromRequest('${row['id']}');
    } else if (action == 'cancel') {
      final note = await _textPrompt('Cancel Purchase Request', 'Reason');
      if (note == null || note.trim().isEmpty) return;
      await _run(
        () => _service.setRequestStatus(
          widget.session,
          requestId: '${row['id']}',
          status: 'cancelled',
          note: note,
        ),
        'Purchase Request cancelled.',
      );
    }
  }

  Widget _ordersTab() {
    return Column(
      children: [
        _toolbar(
          '${_orders.length} purchase orders',
          _canManage ? _newOrder : null,
          'New Purchase Order',
        ),
        Expanded(
          child: _list(
            _orders,
            empty: 'No purchase orders.',
            tile: (row) => ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.shopping_cart_outlined),
              ),
              title: Text('${row['order_number']} • ${row['supplier_name']}'),
              subtitle: Text(
                '${row['location_name']} • ${row['order_date']} • Received ${_qty(row['received_quantity'])}/${_qty(row['ordered_quantity'])} • ${_money(row['grand_total'])}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _status(row['status']),
                  PopupMenuButton<String>(
                    onSelected: (value) => _orderAction(row, value),
                    itemBuilder: (_) => _orderActions(row)
                        .map(
                          (x) => PopupMenuItem(value: x.$1, child: Text(x.$2)),
                        )
                        .toList(),
                  ),
                ],
              ),
              onTap: () => _showOrder('${row['id']}'),
            ),
          ),
        ),
      ],
    );
  }

  List<(String, String)> _orderActions(Map<String, dynamic> row) {
    final s = '${row['status']}';
    final out = <(String, String)>[];
    if (_canManage && (s == 'draft' || s == 'rejected')) {
      out.add(('submit', 'Submit for Approval'));
    }
    if (_canApprove && s == 'submitted') {
      out.add(('approve', 'Approve'));
      out.add(('reject', 'Reject'));
    }
    if (_canManage && s == 'approved') out.add(('ordered', 'Mark Ordered'));
    if (_canManage &&
        const ['approved', 'ordered', 'partially_received'].contains(s) &&
        _n(row['remaining_receive_quantity']) > 0) {
      out.add(('receive', 'Create GRN'));
    }
    if (_canManage &&
        const ['partially_received', 'received', 'closed'].contains(s) &&
        _n(row['remaining_invoice_quantity']) > 0) {
      out.add(('invoice', 'Create Purchase Invoice'));
    }
    if (_canManage &&
        const [
          'draft',
          'submitted',
          'approved',
          'ordered',
          'rejected',
        ].contains(s) &&
        _n(row['received_quantity']) <= 0.000001) {
      out.add(('cancel', 'Cancel Purchase Order'));
    }
    return out;
  }

  Future<void> _orderAction(Map<String, dynamic> row, String action) async {
    final id = '${row['id']}';
    if (action == 'submit' || action == 'ordered') {
      await _run(
        () => _service.setOrderStatus(
          widget.session,
          orderId: id,
          status: action == 'ordered' ? 'ordered' : 'submitted',
        ),
        action == 'ordered'
            ? 'Purchase Order marked Ordered.'
            : 'Purchase Order submitted.',
      );
    } else if (action == 'approve') {
      await _run(
        () => _service.decideOrder(widget.session, orderId: id, approve: true),
        'Purchase Order approved.',
      );
    } else if (action == 'reject') {
      final note = await _textPrompt('Reject Purchase Order', 'Reason');
      if (note == null || note.trim().isEmpty) return;
      await _run(
        () => _service.decideOrder(
          widget.session,
          orderId: id,
          approve: false,
          note: note,
        ),
        'Purchase Order rejected.',
      );
    } else if (action == 'receive') {
      await _receiveOrder(id);
    } else if (action == 'invoice') {
      await _createInvoiceFromOrder(id);
    } else if (action == 'cancel') {
      final note = await _textPrompt('Cancel Purchase Order', 'Reason');
      if (note == null || note.trim().isEmpty) return;
      await _run(
        () => _service.setOrderStatus(
          widget.session,
          orderId: id,
          status: 'cancelled',
          reason: note,
        ),
        'Purchase Order cancelled.',
      );
    }
  }

  Widget _grnTab() {
    return Column(
      children: [
        _toolbar('${_grns.length} goods received notes', null, ''),
        Expanded(
          child: _list(
            _grns,
            empty: 'No GRNs.',
            tile: (row) => ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.inventory_outlined),
              ),
              title: Text('${row['grn_number']} • ${row['supplier_name']}'),
              subtitle: Text(
                '${row['order_number']} • ${row['receipt_date']} • Accepted ${_qty(row['accepted_quantity'])} • Damaged ${_qty(row['damaged_quantity'])} • Rejected ${_qty(row['rejected_quantity'])}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _status(row['status']),
                  if (_canManage && row['status'] == 'draft') ...[
                    TextButton(
                      onPressed: () => _run(
                        () => _service.postGrn(widget.session, '${row['id']}'),
                        'GRN posted and stock updated.',
                      ),
                      child: const Text('POST'),
                    ),
                    IconButton(
                      tooltip: 'Cancel Draft GRN',
                      onPressed: () => _cancelGrn(row),
                      icon: const Icon(Icons.cancel_outlined),
                    ),
                  ],
                ],
              ),
              onTap: () => _showGrn('${row['id']}'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _invoiceTab() {
    return Column(
      children: [
        _toolbar('${_invoices.length} purchase invoices', null, ''),
        Expanded(
          child: _list(
            _invoices,
            empty: 'No Purchase Invoices.',
            tile: (row) => ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.receipt_long_outlined),
              ),
              title: Text('${row['invoice_number']} • ${row['supplier_name']}'),
              subtitle: Text(
                'Supplier Inv: ${row['supplier_invoice_number']} • ${row['invoice_date']} • Balance ${_money(row['balance_due'])}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _status(row['status']),
                  if (_canManage && row['status'] == 'draft')
                    TextButton(
                      onPressed: () => _run(
                        () => _service.postInvoice(
                          widget.session,
                          '${row['id']}',
                        ),
                        'Purchase Invoice posted to supplier ledger.',
                      ),
                      child: const Text('POST'),
                    ),
                  if (_canManage &&
                      const ['posted', 'part_paid'].contains(row['status']))
                    TextButton(
                      onPressed: () => _newPayment(invoice: row),
                      child: const Text('PAY'),
                    ),
                  if (_canManage &&
                      const ['draft', 'posted'].contains(row['status']) &&
                      _n(row['paid_total']) <= 0.005)
                    IconButton(
                      tooltip: 'Void Purchase Invoice',
                      onPressed: () => _voidInvoice(row),
                      icon: const Icon(Icons.block_outlined),
                    ),
                ],
              ),
              onTap: () => _showInvoice('${row['id']}'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ledgerTab() {
    final rows = (_ledger?['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _ledgerSupplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: _suppliers
                    .where((s) => s.isActive)
                    .map(
                      (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                    )
                    .toList(),
                onChanged: (value) async {
                  setState(() => _ledgerSupplierId = value);
                  if (value != null) {
                    final values = await Future.wait<dynamic>([
                      _service.supplierLedger(
                        widget.session,
                        supplierId: value,
                      ),
                      _service.payments(widget.session, supplierId: value),
                    ]);
                    if (mounted) {
                      setState(() {
                        _ledger = Map<String, dynamic>.from(values[0] as Map);
                        _supplierPayments = List<Map<String, dynamic>>.from(
                          values[1] as List,
                        );
                      });
                    }
                  } else if (mounted) {
                    setState(() {
                      _ledger = null;
                      _supplierPayments = const [];
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            if (_canManage)
              FilledButton.icon(
                onPressed: () => _newPayment(),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Supplier Payment'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_ledger != null)
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Total Invoices',
                  _money(_ledger!['total_debit']),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metric('Payments', _money(_ledger!['total_credit'])),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metric(
                  'Balance Due',
                  _money(_ledger!['closing_balance']),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (_supplierPayments.isNotEmpty) ...[
          SizedBox(
            height: 142,
            child: Card(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Text(
                      'Supplier Payments',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: _supplierPayments.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, index) {
                        final payment = _supplierPayments[index];
                        return SizedBox(
                          width: 260,
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.payments_outlined),
                            title: Text(
                              '${payment['payment_number']} • ${_money(payment['amount'])}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${payment['payment_date']} • ${payment['payment_method']} • ${payment['status']}',
                            ),
                            trailing:
                                _canManage && payment['status'] == 'posted'
                                ? IconButton(
                                    tooltip: 'Void payment',
                                    onPressed: () =>
                                        _voidSupplierPayment(payment),
                                    icon: const Icon(Icons.undo_outlined),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: _ledgerSupplierId == null
              ? const Center(
                  child: Text('Select a supplier to view the ledger.'),
                )
              : _list(
                  rows,
                  empty: 'No supplier ledger entries.',
                  tile: (row) => ListTile(
                    leading: Icon(
                      _n(row['debit']) > 0
                          ? Icons.receipt_outlined
                          : Icons.payments_outlined,
                    ),
                    title: Text(
                      '${row['reference'] ?? ''} • ${row['description'] ?? ''}',
                    ),
                    subtitle: Text(
                      '${row['entry_date']} • ${row['entry_type']}',
                    ),
                    trailing: Text(
                      'Dr ${_money(row['debit'])}   Cr ${_money(row['credit'])}\nBal ${_money(row['balance'])}',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _priceTab() {
    return _list(
      _prices,
      empty: 'No purchase price history.',
      tile: (row) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.history)),
        title: Text('${row['product_name']} • ${row['sku'] ?? ''}'),
        subtitle: Text(
          '${row['supplier_name']} • ${row['purchase_date']} • ${row['document_number']} • Qty ${_qty(row['quantity'])}',
        ),
        trailing: Text(
          _money(row['unit_cost']),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _toolbar(String label, VoidCallback? action, String actionLabel) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (action != null)
              FilledButton.icon(
                onPressed: action,
                icon: const Icon(Icons.add),
                label: Text(actionLabel),
              ),
          ],
        ),
      );

  Widget _list(
    List<Map<String, dynamic>> rows, {
    required String empty,
    required Widget Function(Map<String, dynamic>) tile,
  }) {
    if (rows.isEmpty) return Center(child: Text(empty));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) => tile(rows[index]),
      ),
    );
  }

  Widget _status(dynamic raw) {
    final value = '${raw ?? ''}'.replaceAll('_', ' ').toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _metric(String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Future<String?> _textPrompt(String title, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _newRequest() async {
    if (_products.isEmpty) return;
    final purpose = TextEditingController();
    final requestNotes = TextEditingController();
    DateTime? requiredDate;
    final qty = TextEditingController(text: '1');
    final cost = TextEditingController();
    String priority = 'normal';
    String? supplierId;
    String? variantId = _products.first.variantId;
    final lines = <Map<String, dynamic>>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Purchase Request'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: purpose,
                    decoration: const InputDecoration(
                      labelText: 'Purpose / reason',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate:
                                  requiredDate ??
                                  DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 1),
                              ),
                              lastDate: DateTime(2200),
                            );
                            if (picked != null) {
                              setDialogState(() => requiredDate = picked);
                            }
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text(
                            requiredDate == null
                                ? 'Required Date (optional)'
                                : 'Required: ${requiredDate!.toIso8601String().split('T').first}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: requestNotes,
                          decoration: const InputDecoration(
                            labelText: 'Request notes',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                          ),
                          items: const ['low', 'normal', 'high', 'urgent']
                              .map(
                                (x) => DropdownMenuItem(
                                  value: x,
                                  child: Text(x.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => priority = v ?? 'normal'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: supplierId,
                          decoration: const InputDecoration(
                            labelText: 'Preferred supplier (optional)',
                          ),
                          items: _suppliers
                              .where((s) => s.isActive)
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(s.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => supplierId = v),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  DropdownButtonFormField<String>(
                    initialValue: variantId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: _products
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.variantId,
                            child: Text('${p.productName} • ${p.sku}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() {
                      variantId = v;
                      final p = _products.firstWhere((x) => x.variantId == v);
                      cost.text = p.costPrice.toStringAsFixed(2);
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: cost,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Estimated unit cost',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          final p = _products.firstWhere(
                            (x) => x.variantId == variantId,
                          );
                          final q = double.tryParse(qty.text) ?? 0;
                          if (q <= 0) return;
                          setDialogState(() {
                            lines.removeWhere(
                              (x) => x['variant_id'] == p.variantId,
                            );
                            lines.add({
                              'variant_id': p.variantId,
                              'quantity': q,
                              'unit_cost':
                                  double.tryParse(cost.text) ?? p.costPrice,
                              '_label': '${p.productName} • ${p.sku}',
                            });
                          });
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...lines.map(
                    (x) => ListTile(
                      dense: true,
                      title: Text('${x['_label']}'),
                      subtitle: Text(
                        'Qty ${_qty(x['quantity'])} • ${_money(x['unit_cost'])}',
                      ),
                      trailing: IconButton(
                        onPressed: () => setDialogState(() => lines.remove(x)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: lines.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Create Draft'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(() async {
        await _service.createRequest(
          widget.session,
          items: lines
              .map((x) => Map<String, dynamic>.from(x)..remove('_label'))
              .toList(),
          requiredDate: requiredDate,
          priority: priority,
          preferredSupplierId: supplierId,
          purpose: purpose.text,
          notes: requestNotes.text,
        );
      }, 'Purchase Request created.');
    }
    purpose.dispose();
    requestNotes.dispose();
    qty.dispose();
    cost.dispose();
  }

  Future<void> _newOrder() async {
    if (_products.isEmpty || _suppliers.where((s) => s.isActive).isEmpty) {
      return;
    }
    String? supplierId = _suppliers.where((s) => s.isActive).first.id;
    String? variantId = _products.first.variantId;
    final qty = TextEditingController(text: '1');
    final cost = TextEditingController(
      text: _products.first.costPrice.toStringAsFixed(2),
    );
    final notes = TextEditingController();
    DateTime? expectedDate;
    final lines = <Map<String, dynamic>>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('New Purchase Order'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: _suppliers
                        .where((s) => s.isActive)
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => supplierId = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                      labelText: 'PO notes / delivery instructions',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate:
                              expectedDate ??
                              DateTime.now().add(const Duration(days: 7)),
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime(2200),
                        );
                        if (picked != null) {
                          setDialogState(() => expectedDate = picked);
                        }
                      },
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text(
                        expectedDate == null
                            ? 'Expected Delivery (optional)'
                            : 'Expected: ${expectedDate!.toIso8601String().split('T').first}',
                      ),
                    ),
                  ),
                  const Divider(height: 28),
                  DropdownButtonFormField<String>(
                    initialValue: variantId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: _products
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.variantId,
                            child: Text('${p.productName} • ${p.sku}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      variantId = value;
                      final p = _products.firstWhere(
                        (x) => x.variantId == value,
                      );
                      cost.text = p.costPrice.toStringAsFixed(2);
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: cost,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Unit cost',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: variantId == null
                            ? null
                            : () {
                                final p = _products.firstWhere(
                                  (x) => x.variantId == variantId,
                                );
                                final q = double.tryParse(qty.text) ?? 0;
                                final c =
                                    double.tryParse(cost.text) ?? p.costPrice;
                                if (q <= 0 || c < 0) return;
                                setDialogState(() {
                                  lines.removeWhere(
                                    (x) => x['variant_id'] == p.variantId,
                                  );
                                  lines.add({
                                    'variant_id': p.variantId,
                                    'quantity': q,
                                    'unit_cost': c,
                                    'tax_rate': p.taxRate,
                                    '_label': '${p.productName} • ${p.sku}',
                                  });
                                });
                              },
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...lines.map(
                    (line) => ListTile(
                      dense: true,
                      title: Text('${line['_label']}'),
                      subtitle: Text(
                        'Qty ${_qty(line['quantity'])} • ${_money(line['unit_cost'])} • Tax ${_qty(line['tax_rate'])}%',
                      ),
                      trailing: IconButton(
                        onPressed: () =>
                            setDialogState(() => lines.remove(line)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: supplierId == null || lines.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Create Draft PO'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && supplierId != null) {
      await _run(
        () => _service.createOrder(
          widget.session,
          supplierId: supplierId!,
          items: lines
              .map((e) => Map<String, dynamic>.from(e)..remove('_label'))
              .toList(),
          expectedDate: expectedDate,
          notes: notes.text.trim(),
        ),
        'Purchase Order created as Draft.',
      );
    }
    qty.dispose();
    cost.dispose();
    notes.dispose();
  }

  Future<void> _createPoFromRequest(String requestId) async {
    final detail = await _service.requestDetail(widget.session, requestId);
    final request = Map<String, dynamic>.from(
      detail['request'] as Map? ?? const {},
    );
    final items = (detail['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (!mounted) return;
    String? supplierId = request['preferred_supplier_id']?.toString();
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text('Create PO from ${request['request_number']}'),
          content: DropdownButtonFormField<String>(
            initialValue: supplierId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: _suppliers
                .where((s) => s.isActive)
                .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                .toList(),
            onChanged: (v) => setDialogState(() => supplierId = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: supplierId == null
                  ? null
                  : () => Navigator.pop(dialogContext, supplierId),
              child: const Text('Create PO'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await _run(() async {
      await _service.createOrder(
        widget.session,
        supplierId: selected,
        requestId: requestId,
        items: items
            .map(
              (i) => {
                'variant_id': i['variant_id'],
                'quantity': _n(i['quantity']),
                'unit_cost': _n(i['estimated_unit_cost']),
                'tax_rate':
                    _products
                        .where((p) => p.variantId == i['variant_id'])
                        .map((p) => p.taxRate)
                        .firstOrNull ??
                    0,
              },
            )
            .toList(),
        expectedDate: DateTime.tryParse('${request['required_date'] ?? ''}'),
        notes: 'Created from ${request['request_number']}',
      );
    }, 'Purchase Order created as Draft.');
  }

  Future<void> _receiveOrder(String orderId) async {
    final detail = await _service.orderDetail(widget.session, orderId);
    final order = Map<String, dynamic>.from(
      detail['order'] as Map? ?? const {},
    );
    final items = (detail['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((i) => _n(i['remaining_receive_quantity']) > 0)
        .toList();
    if (items.isEmpty || !mounted) return;
    final accepted = <String, TextEditingController>{};
    final damaged = <String, TextEditingController>{};
    final rejected = <String, TextEditingController>{};
    final tracking = <String, TextEditingController>{};
    final damageNotes = <String, TextEditingController>{};
    final rejectionReasons = <String, TextEditingController>{};
    final deliveryNote = TextEditingController();
    final grnNotes = TextEditingController();
    DateTime receiptDate = DateTime.now();
    for (final item in items) {
      final id = '${item['id']}';
      accepted[id] = TextEditingController(
        text: _qty(item['remaining_receive_quantity']),
      );
      damaged[id] = TextEditingController(text: '0');
      rejected[id] = TextEditingController(text: '0');
      tracking[id] = TextEditingController();
      damageNotes[id] = TextEditingController();
      rejectionReasons[id] = TextEditingController();
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Create GRN • ${order['order_number']}'),
          content: SizedBox(
            width: 900,
            height: 560,
            child: ListView(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: deliveryNote,
                        decoration: const InputDecoration(
                          labelText: 'Supplier Delivery Note / DC',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: receiptDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2200),
                          );
                          if (picked != null) {
                            setDialogState(() => receiptDate = picked);
                          }
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          'Receipt: ${receiptDate.toIso8601String().split('T').first}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: grnNotes,
                  decoration: const InputDecoration(
                    labelText: 'GRN notes / inspection remarks',
                  ),
                ),
                const Divider(height: 24),
                ...items.map((item) {
                  final id = '${item['id']}';
                  final mode = '${item['tracking_mode'] ?? 'none'}';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['product_name']} • ${item['sku'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Remaining ${_qty(item['remaining_receive_quantity'])} • Tracking: ${mode.toUpperCase()}',
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: accepted[id],
                                  decoration: const InputDecoration(
                                    labelText: 'Accepted',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: damaged[id],
                                  decoration: const InputDecoration(
                                    labelText: 'Damaged',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: rejected[id],
                                  decoration: const InputDecoration(
                                    labelText: 'Rejected',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: damageNotes[id],
                                  decoration: const InputDecoration(
                                    labelText: 'Damage note (if damaged)',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: rejectionReasons[id],
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Rejection reason (required if rejected)',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (mode == 'serial') ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: tracking[id],
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Serials',
                                helperText:
                                    'Accepted serials separated by comma/new line. For damaged use: accepted serials | damaged: serialA,serialB',
                              ),
                            ),
                          ] else if (mode == 'batch') ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: tracking[id],
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Batch lines',
                                helperText:
                                    'One per line: BATCH,accepted,damaged,expiry(YYYY-MM-DD),manufactured(optional)',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create Draft GRN'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final payload = <Map<String, dynamic>>[];
      String? validationError;
      for (final item in items) {
        final id = '${item['id']}';
        final a = double.tryParse(accepted[id]!.text) ?? 0;
        final d = double.tryParse(damaged[id]!.text) ?? 0;
        final r = double.tryParse(rejected[id]!.text) ?? 0;
        final total = a + d + r;
        if (a < 0 || d < 0 || r < 0) {
          validationError =
              '${item['product_name']}: quantities cannot be negative.';
          break;
        }
        if (total <= 0) continue;
        final remaining = _n(item['remaining_receive_quantity']);
        if (total > remaining + 0.000001) {
          validationError =
              '${item['product_name']}: receiving ${_qty(total)} exceeds remaining ${_qty(remaining)}.';
          break;
        }
        if (r > 0 && rejectionReasons[id]!.text.trim().isEmpty) {
          validationError =
              '${item['product_name']}: enter a rejection reason.';
          break;
        }
        final mode = '${item['tracking_mode'] ?? 'none'}';
        Map<String, dynamic> t = {};
        if (mode == 'serial') {
          final raw = tracking[id]!.text;
          final split = raw.split(
            RegExp(r'\|\s*damaged\s*:', caseSensitive: false),
          );
          List<String> parse(String v) => v
              .split(RegExp(r'[,\n;]'))
              .map((x) => x.trim())
              .where((x) => x.isNotEmpty)
              .toList();
          final acceptedSerials = parse(split.first);
          final damagedSerials = split.length > 1
              ? parse(split[1])
              : <String>[];
          if (a != a.truncateToDouble() || d != d.truncateToDouble()) {
            validationError =
                '${item['product_name']}: serial-tracked accepted/damaged quantities must be whole units.';
            break;
          }
          if (acceptedSerials.length != a.toInt() ||
              damagedSerials.length != d.toInt()) {
            validationError =
                '${item['product_name']}: provide exactly ${a.toInt()} accepted and ${d.toInt()} damaged serial number(s).';
            break;
          }
          final allSerials = [
            ...acceptedSerials,
            ...damagedSerials,
          ].map((e) => e.toLowerCase()).toList();
          if (allSerials.toSet().length != allSerials.length) {
            validationError =
                '${item['product_name']}: duplicate serial numbers are not allowed.';
            break;
          }
          t = {
            'serial_numbers': acceptedSerials,
            'damaged_serial_numbers': damagedSerials,
          };
        } else if (mode == 'batch') {
          final batches = <Map<String, dynamic>>[];
          var batchAccepted = 0.0;
          var batchDamaged = 0.0;
          final batchNames = <String>{};
          for (final line in tracking[id]!.text.split('\n')) {
            final parts = line.split(',').map((x) => x.trim()).toList();
            if (parts.isEmpty || parts.first.isEmpty) continue;
            final batchAcceptedQty = parts.length > 1
                ? double.tryParse(parts[1]) ?? 0
                : 0;
            final batchDamagedQty = parts.length > 2
                ? double.tryParse(parts[2]) ?? 0
                : 0;
            if (batchAcceptedQty < 0 ||
                batchDamagedQty < 0 ||
                batchAcceptedQty + batchDamagedQty <= 0) {
              validationError =
                  '${item['product_name']}: every batch line needs positive accepted/damaged quantity.';
              break;
            }
            if (!batchNames.add(parts[0].toLowerCase())) {
              validationError =
                  '${item['product_name']}: duplicate batch ${parts[0]}.';
              break;
            }
            batchAccepted += batchAcceptedQty;
            batchDamaged += batchDamagedQty;
            batches.add({
              'batch_number': parts[0],
              'accepted_quantity': batchAcceptedQty,
              'damaged_quantity': batchDamagedQty,
              'expiry_on': parts.length > 3 && parts[3].isNotEmpty
                  ? parts[3]
                  : null,
              'manufactured_on': parts.length > 4 && parts[4].isNotEmpty
                  ? parts[4]
                  : null,
            });
          }
          if (validationError != null) break;
          if ((batchAccepted - a).abs() > 0.000001 ||
              (batchDamaged - d).abs() > 0.000001) {
            validationError =
                '${item['product_name']}: batch accepted/damaged totals must match ${_qty(a)} / ${_qty(d)}.';
            break;
          }
          t = {'batches': batches};
        }
        payload.add({
          'purchase_order_item_id': id,
          'received_quantity': total,
          'accepted_quantity': a,
          'damaged_quantity': d,
          'rejected_quantity': r,
          'tracking': t,
          'rejection_reason': rejectionReasons[id]!.text.trim(),
          'damage_note': damageNotes[id]!.text.trim(),
        });
      }
      if (validationError != null) {
        _message(validationError);
      } else if (payload.isEmpty) {
        _message('Enter at least one quantity to receive.');
      } else {
        await _run(() async {
          await _service.createGrn(
            widget.session,
            purchaseOrderId: orderId,
            items: payload,
            receiptDate: receiptDate,
            deliveryNote: deliveryNote.text.trim(),
            notes: grnNotes.text.trim(),
          );
        }, 'Draft GRN created. Review and POST it from the GRN tab.');
      }
    }
    for (final c in [
      ...accepted.values,
      ...damaged.values,
      ...rejected.values,
      ...tracking.values,
      ...damageNotes.values,
      ...rejectionReasons.values,
    ]) {
      c.dispose();
    }
    deliveryNote.dispose();
    grnNotes.dispose();
  }

  Future<void> _createInvoiceFromOrder(String orderId) async {
    final detail = await _service.orderDetail(widget.session, orderId);
    final order = Map<String, dynamic>.from(
      detail['order'] as Map? ?? const {},
    );
    final items = (detail['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((i) => _n(i['remaining_invoice_quantity']) > 0)
        .toList();
    if (items.isEmpty || !mounted) return;

    final supplierInvoice = TextEditingController();
    final additional = TextEditingController(text: '0.00');
    final roundOff = TextEditingController(text: '0.00');
    final invoiceNotes = TextEditingController();
    DateTime invoiceDate = DateTime.now();
    DateTime? dueDate;

    double beforeRound() {
      final itemTotal = items.fold<double>(0, (sum, i) {
        final qty = _n(i['remaining_invoice_quantity']);
        final cost = _n(i['unit_cost']);
        final tax = _n(i['tax_rate']);
        return sum + (qty * cost * (1 + tax / 100));
      });
      return itemTotal + (double.tryParse(additional.text.trim()) ?? 0);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final roundValue = double.tryParse(roundOff.text.trim()) ?? 0;
          final grand = beforeRound() + roundValue;
          return AlertDialog(
            title: Text('Purchase Invoice • ${order['order_number']}'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: supplierInvoice,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Supplier Invoice Number',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: dialogContext,
                                initialDate: invoiceDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2200),
                              );
                              if (picked != null) {
                                setDialogState(() => invoiceDate = picked);
                              }
                            },
                            icon: const Icon(Icons.receipt_outlined),
                            label: Text(
                              'Invoice: ${invoiceDate.toIso8601String().split('T').first}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: dialogContext,
                                initialDate:
                                    dueDate ??
                                    invoiceDate.add(const Duration(days: 30)),
                                firstDate: invoiceDate,
                                lastDate: DateTime(2200),
                              );
                              if (picked != null) {
                                setDialogState(() => dueDate = picked);
                              }
                            },
                            icon: const Icon(Icons.event_available_outlined),
                            label: Text(
                              dueDate == null
                                  ? 'Due Date (optional)'
                                  : 'Due: ${dueDate!.toIso8601String().split('T').first}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: invoiceNotes,
                      decoration: const InputDecoration(
                        labelText: 'Invoice notes',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...items.map(
                      (i) => ListTile(
                        dense: true,
                        title: Text('${i['product_name']} • ${i['sku'] ?? ''}'),
                        subtitle: Text(
                          'Invoice qty ${_qty(i['remaining_invoice_quantity'])} × ${_money(i['unit_cost'])} • Tax ${_n(i['tax_rate']).toStringAsFixed(2)}%',
                        ),
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: additional,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Additional Charges',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: roundOff,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Round Off',
                              helperText: '-1.00 to 1.00',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            final raw = beforeRound();
                            final delta = raw.roundToDouble() - raw;
                            setDialogState(
                              () => roundOff.text = delta.abs() < 0.000001
                                  ? '0.00'
                                  : delta.toStringAsFixed(2),
                            );
                          },
                          icon: const Icon(Icons.exposure_zero),
                          label: const Text('Round'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Grand Total ${_money(grand)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Create Draft Invoice'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true && supplierInvoice.text.trim().isNotEmpty) {
      final additionalValue = double.tryParse(additional.text.trim()) ?? 0;
      final roundValue = double.tryParse(roundOff.text.trim()) ?? 0;
      if (roundValue.abs() > 1.000001) {
        _message('Round off must be between -1.00 and 1.00.');
      } else if (additionalValue < 0) {
        _message('Additional charges cannot be negative.');
      } else {
        await _run(() async {
          await _service.createInvoice(
            widget.session,
            purchaseOrderId: orderId,
            supplierInvoiceNumber: supplierInvoice.text.trim(),
            items: items
                .map(
                  (i) => {
                    'purchase_order_item_id': i['id'],
                    'quantity': _n(i['remaining_invoice_quantity']),
                    'unit_cost': _n(i['unit_cost']),
                    'tax_rate': _n(i['tax_rate']),
                  },
                )
                .toList(),
            invoiceDate: invoiceDate,
            dueDate: dueDate,
            additionalCharges: additionalValue,
            roundOff: roundValue,
            notes: invoiceNotes.text.trim(),
          );
        }, 'Draft Purchase Invoice created.');
      }
    }
    supplierInvoice.dispose();
    additional.dispose();
    roundOff.dispose();
    invoiceNotes.dispose();
  }

  Future<void> _newPayment({Map<String, dynamic>? invoice}) async {
    String? supplierId =
        invoice?['supplier_id']?.toString() ?? _ledgerSupplierId;
    String? invoiceId = invoice?['id']?.toString();
    final amount = TextEditingController(
      text: invoice == null
          ? ''
          : _n(invoice['balance_due']).toStringAsFixed(2),
    );
    final reference = TextEditingController();
    String method = 'bank';
    bool autoAllocate = invoice == null;
    final openInvoices = _invoices
        .where((i) => const ['posted', 'part_paid'].contains(i['status']))
        .toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) {
          final matching = openInvoices
              .where(
                (i) =>
                    supplierId == null || '${i['supplier_id']}' == supplierId,
              )
              .toList();
          return AlertDialog(
            title: const Text('Supplier Payment'),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: supplierId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: _suppliers
                        .where((s) => s.isActive)
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() {
                      supplierId = v;
                      invoiceId = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('invoice-allocation-$supplierId'),
                    initialValue: matching.any((i) => '${i['id']}' == invoiceId)
                        ? invoiceId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Allocate to invoice (optional)',
                    ),
                    items: matching
                        .map(
                          (i) => DropdownMenuItem(
                            value: '${i['id']}',
                            child: Text(
                              '${i['invoice_number']} • ${i['supplier_invoice_number']} • Bal ${_money(i['balance_due'])}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialogState(() {
                      invoiceId = v;
                      if (v != null) {
                        final row = matching.firstWhere(
                          (i) => '${i['id']}' == v,
                        );
                        amount.text = _n(row['balance_due']).toStringAsFixed(2);
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amount,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: method,
                          decoration: const InputDecoration(
                            labelText: 'Method',
                          ),
                          items: const ['cash', 'bank', 'card', 'upi']
                              .map(
                                (x) => DropdownMenuItem(
                                  value: x,
                                  child: Text(x.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => method = v ?? 'bank'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (invoiceId == null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: autoAllocate,
                      onChanged: (v) =>
                          setDialogState(() => autoAllocate = v ?? true),
                      title: const Text(
                        'Auto allocate payment to oldest open invoices',
                      ),
                      subtitle: const Text(
                        'Any amount left after clearing open invoices remains as supplier credit.',
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Reference / cheque / transfer no.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: supplierId == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: const Text('Post Payment'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && supplierId != null) {
      final value = double.tryParse(amount.text) ?? 0;
      if (value > 0) {
        await _run(() async {
          final allocations = <Map<String, dynamic>>[];
          if (invoiceId != null) {
            final selected = openInvoices.firstWhere(
              (i) => '${i['id']}' == invoiceId,
            );
            final balance = _n(selected['balance_due']);
            if (value > balance + 0.005) {
              throw StateError(
                'Payment allocation exceeds the selected invoice balance.',
              );
            }
            allocations.add({
              'purchase_invoice_id': invoiceId,
              'amount': value,
            });
          } else if (autoAllocate) {
            var remaining = value;
            final candidates =
                openInvoices
                    .where((i) => '${i['supplier_id']}' == supplierId)
                    .toList()
                  ..sort(
                    (a, b) =>
                        '${a['due_date'] ?? a['invoice_date'] ?? ''}'.compareTo(
                          '${b['due_date'] ?? b['invoice_date'] ?? ''}',
                        ),
                  );
            for (final open in candidates) {
              if (remaining <= 0.005) break;
              final balance = _n(open['balance_due']);
              if (balance <= 0.005) continue;
              final allocated = remaining < balance ? remaining : balance;
              allocations.add({
                'purchase_invoice_id': open['id'],
                'amount': allocated,
              });
              remaining -= allocated;
            }
          }
          await _service.createPayment(
            widget.session,
            supplierId: supplierId!,
            amount: value,
            paymentMethod: method,
            reference: reference.text,
            allocations: allocations,
          );
          if (_ledgerSupplierId == supplierId) {
            final values = await Future.wait<dynamic>([
              _service.supplierLedger(widget.session, supplierId: supplierId!),
              _service.payments(widget.session, supplierId: supplierId!),
            ]);
            _ledger = Map<String, dynamic>.from(values[0] as Map);
            _supplierPayments = List<Map<String, dynamic>>.from(
              values[1] as List,
            );
          }
        }, 'Supplier payment posted.');
      }
    }
    amount.dispose();
    reference.dispose();
  }

  Future<void> _cancelGrn(Map<String, dynamic> row) async {
    final reason = await _textPrompt('Cancel Draft GRN', 'Reason');
    if (reason == null || reason.trim().isEmpty) return;
    await _run(
      () => _service.cancelGrn(widget.session, '${row['id']}', reason),
      'Draft GRN cancelled.',
    );
  }

  Future<void> _voidInvoice(Map<String, dynamic> row) async {
    final reason = await _textPrompt('Void Purchase Invoice', 'Reason');
    if (reason == null || reason.trim().isEmpty) return;
    await _run(
      () => _service.voidInvoice(widget.session, '${row['id']}', reason),
      'Purchase Invoice voided and accounting/PO balances refreshed.',
    );
  }

  Future<void> _voidSupplierPayment(Map<String, dynamic> row) async {
    final reason = await _textPrompt('Void Supplier Payment', 'Reason');
    if (reason == null || reason.trim().isEmpty) return;
    await _run(() async {
      await _service.voidPayment(widget.session, '${row['id']}', reason);
      final supplierId = _ledgerSupplierId;
      if (supplierId != null) {
        final values = await Future.wait<dynamic>([
          _service.supplierLedger(widget.session, supplierId: supplierId),
          _service.payments(widget.session, supplierId: supplierId),
        ]);
        _ledger = Map<String, dynamic>.from(values[0] as Map);
        _supplierPayments = List<Map<String, dynamic>>.from(values[1] as List);
      }
    }, 'Supplier payment voided and Accounts Payable restored.');
  }

  Future<void> _showRequest(String id) async {
    final data = await _service.requestDetail(widget.session, id);
    final row = _requests.where((e) => '${e['id']}' == id).firstOrNull;
    final actions = row == null
        ? <_PurchaseDialogAction>[]
        : _requestActions(row)
              .map(
                (item) => _PurchaseDialogAction(
                  item.$2,
                  item.$1 == 'approve'
                      ? Icons.check_circle_outline
                      : item.$1 == 'reject'
                      ? Icons.cancel_outlined
                      : item.$1 == 'po'
                      ? Icons.shopping_cart_checkout_outlined
                      : Icons.send_outlined,
                  () => _requestAction(row, item.$1),
                  primary: item.$1 == 'approve' || item.$1 == 'po',
                ),
              )
              .toList();
    await _showPurchaseDocument('Purchase Request', data, actions: actions);
  }

  Future<void> _showOrder(String id) async {
    final values = await Future.wait<dynamic>([
      _service.orderDetail(widget.session, id),
      _service
          .cycleSummary(widget.session, id)
          .catchError((_) => <String, dynamic>{}),
    ]);
    final data = Map<String, dynamic>.from(values[0] as Map);
    final cycle = Map<String, dynamic>.from(values[1] as Map);
    final row = _orders.where((e) => '${e['id']}' == id).firstOrNull;
    final actions = row == null
        ? <_PurchaseDialogAction>[]
        : _orderActions(row)
              .map(
                (item) => _PurchaseDialogAction(
                  item.$2,
                  item.$1 == 'receive'
                      ? Icons.inventory_outlined
                      : item.$1 == 'invoice'
                      ? Icons.receipt_long_outlined
                      : item.$1 == 'approve'
                      ? Icons.check_circle_outline
                      : item.$1 == 'reject'
                      ? Icons.cancel_outlined
                      : Icons.send_outlined,
                  () => _orderAction(row, item.$1),
                  primary:
                      item.$1 == 'receive' ||
                      item.$1 == 'invoice' ||
                      item.$1 == 'approve',
                ),
              )
              .toList();
    await _showPurchaseDocument(
      'Purchase Order',
      data,
      cycle: cycle,
      actions: actions,
    );
  }

  Future<void> _showGrn(String id) async {
    final data = await _service.grnDetail(widget.session, id);
    final row = _grns.where((e) => '${e['id']}' == id).firstOrNull;
    final actions = <_PurchaseDialogAction>[
      if (_canManage && row?['status'] == 'draft')
        _PurchaseDialogAction(
          'Post GRN & Update Stock',
          Icons.inventory_2_outlined,
          () => _run(
            () => _service.postGrn(widget.session, id),
            'GRN posted and stock updated.',
          ),
          primary: true,
        ),
      if (_canManage && row?['status'] == 'draft')
        _PurchaseDialogAction(
          'Cancel Draft GRN',
          Icons.cancel_outlined,
          () => _cancelGrn(row!),
        ),
    ];
    await _showPurchaseDocument('Goods Received Note', data, actions: actions);
  }

  Future<void> _showInvoice(String id) async {
    final data = await _service.invoiceDetail(widget.session, id);
    final row = _invoices.where((e) => '${e['id']}' == id).firstOrNull;
    final actions = <_PurchaseDialogAction>[
      if (_canManage && row?['status'] == 'draft')
        _PurchaseDialogAction(
          'Post Invoice to Accounts',
          Icons.post_add_outlined,
          () => _run(
            () => _service.postInvoice(widget.session, id),
            'Purchase Invoice posted to supplier ledger and Accounts Payable.',
          ),
          primary: true,
        ),
      if (_canManage &&
          row != null &&
          const ['posted', 'part_paid'].contains(row['status']))
        _PurchaseDialogAction(
          'Pay Supplier',
          Icons.payments_outlined,
          () => _newPayment(invoice: row),
          primary: true,
        ),
      if (_canManage &&
          row != null &&
          const ['draft', 'posted'].contains(row['status']) &&
          _n(row['paid_total']) <= 0.005)
        _PurchaseDialogAction(
          'Void Invoice',
          Icons.block_outlined,
          () => _voidInvoice(row),
        ),
    ];
    await _showPurchaseDocument('Purchase Invoice', data, actions: actions);
  }

  Future<void> _showPurchaseDocument(
    String title,
    Map<String, dynamic> data, {
    Map<String, dynamic>? cycle,
    List<_PurchaseDialogAction> actions = const [],
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 1040,
          height: 650,
          child: _PurchaseWorkflowDetail(
            title: title,
            data: data,
            cycle: cycle ?? const {},
            currencyCode: _currency,
          ),
        ),
        actions: [
          ...actions.map(
            (action) => action.primary
                ? FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      action.onPressed();
                    },
                    icon: Icon(action.icon),
                    label: Text(action.label),
                  )
                : TextButton.icon(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      action.onPressed();
                    },
                    icon: Icon(action.icon),
                    label: Text(action.label),
                  ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _PurchaseDialogAction {
  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool primary;

  const _PurchaseDialogAction(
    this.label,
    this.icon,
    this.onPressed, {
    this.primary = false,
  });
}

class _PurchaseWorkflowDetail extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  final Map<String, dynamic> cycle;
  final String currencyCode;

  const _PurchaseWorkflowDetail({
    required this.title,
    required this.data,
    required this.cycle,
    required this.currencyCode,
  });

  Map<String, dynamic> get _header {
    const keys = ['request', 'order', 'grn', 'invoice'];
    for (final key in keys) {
      final value = data[key];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  List<Map<String, dynamic>> _rows(String key) =>
      (data[key] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

  String _text(dynamic value, [String fallback = '—']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  String _money(dynamic value) =>
      '$currencyCode ${_number(value).toStringAsFixed(2)}';

  String _qty(dynamic value) {
    final n = _number(value);
    return n == n.roundToDouble()
        ? n.toInt().toString()
        : n
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          _summaryHeader(context),
          const SizedBox(height: 10),
          const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Items'),
              Tab(text: 'Workflow'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                _overview(context),
                _items(context),
                _workflow(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryHeader(BuildContext context) {
    final number =
        _header['request_number'] ??
        _header['order_number'] ??
        _header['grn_number'] ??
        _header['invoice_number'];
    final status = _text(_header['status'], 'unknown');
    final supplier =
        _header['supplier_name'] ?? _header['preferred_supplier_name'];
    final location = _header['location_name'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 28,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _fact('Document', _text(number)),
          _fact('Status', status.toUpperCase()),
          if (supplier != null) _fact('Supplier', _text(supplier)),
          if (location != null) _fact('Store', _text(location)),
          if (_header.containsKey('grand_total'))
            _fact('Total', _money(_header['grand_total'])),
          if (_header.containsKey('balance_due'))
            _fact('Balance', _money(_header['balance_due'])),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Widget _overview(BuildContext context) {
    final entries = <(String, dynamic)>[];
    void add(String label, String key) {
      if (_header.containsKey(key) &&
          _header[key] != null &&
          '${_header[key]}'.trim().isNotEmpty) {
        entries.add((label, _header[key]));
      }
    }

    add('Request number', 'request_number');
    add('Order number', 'order_number');
    add('GRN number', 'grn_number');
    add('Invoice number', 'invoice_number');
    add('Supplier invoice', 'supplier_invoice_number');
    add('Request date', 'request_date');
    add('Order date', 'order_date');
    add('Receipt date', 'receipt_date');
    add('Invoice date', 'invoice_date');
    add('Required by', 'required_by');
    add('Expected delivery', 'expected_delivery_date');
    add('Due date', 'due_date');
    add('Priority', 'priority');
    add('Purpose', 'purpose');
    add('Delivery note', 'supplier_delivery_note');
    add('Notes', 'notes');
    add('Rejection reason', 'rejection_reason');

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: entries
              .map(
                (e) =>
                    SizedBox(width: 280, child: _detailTile(e.$1, _text(e.$2))),
              )
              .toList(),
        ),
        if (_header.containsKey('subtotal') ||
            _header.containsKey('tax_total')) ...[
          const SizedBox(height: 16),
          const Text(
            'Financial Summary',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (_header.containsKey('subtotal'))
                _metricCard('Subtotal', _money(_header['subtotal'])),
              if (_header.containsKey('tax_total'))
                _metricCard('Tax', _money(_header['tax_total'])),
              if (_header.containsKey('additional_charges'))
                _metricCard(
                  'Additional',
                  _money(_header['additional_charges']),
                ),
              if (_header.containsKey('round_off'))
                _metricCard('Round off', _money(_header['round_off'])),
              if (_header.containsKey('grand_total'))
                _metricCard('Grand total', _money(_header['grand_total'])),
              if (_header.containsKey('paid_total'))
                _metricCard('Paid', _money(_header['paid_total'])),
              if (_header.containsKey('balance_due'))
                _metricCard('Balance due', _money(_header['balance_due'])),
            ],
          ),
        ],
      ],
    );
  }

  Widget _detailTile(String label, String value) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.black12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _metricCard(String label, String value) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _items(BuildContext context) {
    final rows = _rows('items');
    if (rows.isEmpty) return const Center(child: Text('No line items.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final row = rows[index];
        final qty = row['quantity'] ?? row['received_quantity'] ?? 0;
        final unit = row['unit_cost'] ?? row['estimated_unit_cost'];
        final lineTotal = row['line_total'];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 5,
          ),
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(
            '${_text(row['product_name'])} • ${_text(row['sku'], '')}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Wrap(
            spacing: 16,
            runSpacing: 3,
            children: [
              Text('Qty ${_qty(qty)}'),
              if (unit != null) Text('Unit ${_money(unit)}'),
              if (row['tax_rate'] != null)
                Text('Tax ${_qty(row['tax_rate'])}%'),
              if (row['accepted_quantity'] != null)
                Text('Accepted ${_qty(row['accepted_quantity'])}'),
              if (row['damaged_quantity'] != null)
                Text('Damaged ${_qty(row['damaged_quantity'])}'),
              if (row['rejected_quantity'] != null)
                Text('Rejected ${_qty(row['rejected_quantity'])}'),
              if (row['received_quantity'] != null && title == 'Purchase Order')
                Text('Received ${_qty(row['received_quantity'])}'),
              if (row['invoiced_quantity'] != null)
                Text('Invoiced ${_qty(row['invoiced_quantity'])}'),
            ],
          ),
          trailing: lineTotal == null
              ? null
              : Text(
                  _money(lineTotal),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
        );
      },
    );
  }

  Widget _workflow(BuildContext context) {
    final history = _rows('history');
    final grns = _rows('grns');
    final invoices = _rows('invoices');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (cycle.isNotEmpty) ...[
          const Text(
            'Purchase Cycle Progress',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricCard('Ordered', _qty(cycle['ordered_quantity'])),
              _metricCard('Received', _qty(cycle['received_quantity'])),
              _metricCard('Accepted', _qty(cycle['accepted_quantity'])),
              _metricCard('Damaged', _qty(cycle['damaged_quantity'])),
              _metricCard('Rejected', _qty(cycle['rejected_quantity'])),
              _metricCard(
                'Remaining receipt',
                _qty(cycle['remaining_receive_quantity']),
              ),
              _metricCard('Invoiced', _qty(cycle['invoiced_quantity'])),
              _metricCard(
                'Remaining invoice',
                _qty(cycle['remaining_invoice_quantity']),
              ),
              _metricCard(
                'Posted invoices',
                _money(cycle['posted_invoice_total']),
              ),
              _metricCard(
                'Payable balance',
                _money(cycle['invoice_balance_due']),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
        if (grns.isNotEmpty) ...[
          const Text(
            'Goods Receipts',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          ...grns.map(
            (row) => ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(_text(row['grn_number'])),
              subtitle: Text(
                '${_text(row['receipt_date'])} • ${_text(row['status']).toUpperCase()}',
              ),
            ),
          ),
          const Divider(),
        ],
        if (invoices.isNotEmpty) ...[
          const Text(
            'Purchase Invoices',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          ...invoices.map(
            (row) => ListTile(
              dense: true,
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(
                '${_text(row['invoice_number'])} • ${_money(row['grand_total'])}',
              ),
              subtitle: Text(
                '${_text(row['invoice_date'])} • ${_text(row['status']).toUpperCase()} • Balance ${_money(row['balance_due'])}',
              ),
            ),
          ),
          const Divider(),
        ],
        if (history.isNotEmpty) ...[
          const Text(
            'Status History',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          ...history.map(
            (row) => ListTile(
              dense: true,
              leading: const Icon(Icons.timeline_outlined),
              title: Text(
                '${_text(row['from_status'])} → ${_text(row['to_status'])}',
              ),
              subtitle: Text(
                '${_text(row['changed_at'] ?? row['created_at'])}${row['reason'] == null && row['note'] == null ? '' : ' • ${_text(row['reason'] ?? row['note'])}'}',
              ),
            ),
          ),
        ],
        if (cycle.isEmpty &&
            history.isEmpty &&
            grns.isEmpty &&
            invoices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(
              child: Text('No additional workflow history for this document.'),
            ),
          ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
