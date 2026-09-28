import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import '../../widgets/mobile_workspace_widgets.dart';
import 'mobile_tools_pages.dart';

class MobileSalesWorkspace extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileSalesWorkspace({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
  });

  @override
  State<MobileSalesWorkspace> createState() => _MobileSalesWorkspaceState();
}

class _MobileSalesWorkspaceState extends State<MobileSalesWorkspace> {
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MobileSalesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationId != widget.locationId) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = widget.service.sales(
      widget.session,
      locationId: widget.locationId,
      limit: 250,
    );
  }

  Future<void> _refresh() async {
    final next = widget.service.sales(
      widget.session,
      locationId: widget.locationId,
      limit: 250,
    );
    setState(() => _future = next);
    await next;
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = _search.text.trim().toLowerCase();
    return rows.where((row) {
      final status = row['status']?.toString().toLowerCase() ?? '';
      final statusOk = _status == 'all' || status == _status;
      if (!statusOk) {
        return false;
      }
      if (q.isEmpty) {
        return true;
      }
      return [
        row['sale_number'],
        row['customer_name'],
        row['location_name'],
        row['status'],
        row['sale_date'],
      ].any((value) => value?.toString().toLowerCase().contains(q) == true);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const WorkspaceLoadingList();
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
            ],
          );
        }
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final rows = _filter(allRows);
        final statuses = <String>{
          'all',
          ...allRows
              .map((row) => row['status']?.toString().toLowerCase() ?? '')
              .where((value) => value.isNotEmpty),
        }.take(6).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
            children: [
              ThqMobileSearchField(
                controller: _search,
                hintText: 'Invoice, customer, store or status',
                onChanged: (_) => setState(() {}),
                onClear: () {
                  _search.clear();
                  setState(() {});
                },
              ),
              if (statuses.length > 1) ...[
                const SizedBox(height: 9),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: statuses
                        .map(
                          (status) => Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ChoiceChip(
                              label: Text(workspaceLabel(status)),
                              selected: _status == status,
                              onSelected: (_) => setState(() => _status = status),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ThqMobileSectionHeader(
                title: 'Sales activity',
                subtitle: '${rows.length} of ${allRows.length} recent invoices',
              ),
              const SizedBox(height: 9),
              if (rows.isEmpty)
                const ThqMobileEmptyState(
                  title: 'No sales match',
                  message: 'Try another search or status filter.',
                  icon: Icons.receipt_long_outlined,
                )
              else
                ...rows.map((row) {
                  final balance = row['balance_due'];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: WorkspaceRecordCard(
                      title: row['sale_number']?.toString() ?? 'Sale',
                      subtitle: row['customer_name']?.toString() ?? 'Walk-in customer',
                      status: row['status']?.toString(),
                      trailing: workspaceMoney(widget.session, row['grand_total']),
                      fields: [
                        WorkspaceRecordField(
                          'Date',
                          workspaceDate(row['sale_date']),
                          icon: Icons.calendar_today_outlined,
                        ),
                        WorkspaceRecordField(
                          'Paid',
                          workspaceMoney(widget.session, row['paid_total']),
                          icon: Icons.payments_outlined,
                        ),
                        WorkspaceRecordField(
                          'Balance',
                          workspaceMoney(widget.session, balance),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        WorkspaceRecordField(
                          'Store',
                          row['location_name']?.toString() ?? '',
                          icon: Icons.storefront_outlined,
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class MobileInventoryWorkspace extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;
  final VoidCallback? onOpenTraceability;

  const MobileInventoryWorkspace({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
    this.onOpenTraceability,
  });

  @override
  State<MobileInventoryWorkspace> createState() =>
      _MobileInventoryWorkspaceState();
}

class _MobileInventoryWorkspaceState extends State<MobileInventoryWorkspace> {
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MobileInventoryWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationId != widget.locationId) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = widget.service.inventory(
      widget.session,
      locationId: widget.locationId,
      limit: 500,
    );
  }

  Future<void> _refresh() async {
    final next = widget.service.inventory(
      widget.session,
      locationId: widget.locationId,
      limit: 500,
    );
    setState(() => _future = next);
    await next;
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = _search.text.trim().toLowerCase();
    return rows.where((row) {
      final status = row['status']?.toString().toLowerCase() ?? '';
      final statusOk = _status == 'all' || status == _status;
      if (!statusOk) {
        return false;
      }
      if (q.isEmpty) {
        return true;
      }
      return [row['product_name'], row['sku'], row['location_name'], row['status']]
          .any((value) => value?.toString().toLowerCase().contains(q) == true);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const WorkspaceLoadingList();
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
            ],
          );
        }
        final allRows = snapshot.data ?? const <Map<String, dynamic>>[];
        final rows = _filter(allRows);
        final low = allRows
            .where((row) => row['status']?.toString().toLowerCase() == 'low_stock')
            .length;
        final out = allRows
            .where((row) => row['status']?.toString().toLowerCase() == 'out_of_stock')
            .length;
        final statuses = <String>{
          'all',
          ...allRows
              .map((row) => row['status']?.toString().toLowerCase() ?? '')
              .where((value) => value.isNotEmpty),
        }.take(6).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: ThqMobileSearchField(
                      controller: _search,
                      hintText: 'Product, SKU or store',
                      onChanged: (_) => setState(() {}),
                      onClear: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
                  ),
                  if (widget.onOpenTraceability != null) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Serial, batch and warranty',
                      onPressed: widget.onOpenTraceability,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ThqMobileMetricCard(
                      label: 'Visible items',
                      value: '${allRows.length}',
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThqMobileMetricCard(
                      label: 'Low stock',
                      value: '$low',
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThqMobileMetricCard(
                      label: 'Out',
                      value: '$out',
                      icon: Icons.remove_shopping_cart_outlined,
                    ),
                  ),
                ],
              ),
              if (statuses.length > 1) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: statuses
                        .map(
                          (status) => Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ChoiceChip(
                              label: Text(workspaceLabel(status)),
                              selected: _status == status,
                              onSelected: (_) => setState(() => _status = status),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ThqMobileSectionHeader(
                title: 'Stock by location',
                subtitle: '${rows.length} matching rows',
              ),
              const SizedBox(height: 9),
              if (rows.isEmpty)
                const ThqMobileEmptyState(
                  title: 'No inventory match',
                  message: 'Try another product, SKU or status.',
                  icon: Icons.inventory_2_outlined,
                )
              else
                ...rows.map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: WorkspaceRecordCard(
                      title: row['product_name']?.toString() ?? 'Product',
                      subtitle: row['sku']?.toString() ?? '',
                      status: row['status']?.toString(),
                      trailing:
                          '${workspaceNumber(row['available'], decimals: 2)} available',
                      fields: [
                        WorkspaceRecordField(
                          'Store',
                          row['location_name']?.toString() ?? '',
                          icon: Icons.storefront_outlined,
                        ),
                        WorkspaceRecordField(
                          'Reorder',
                          workspaceNumber(row['reorder_level'], decimals: 2),
                          icon: Icons.low_priority_rounded,
                        ),
                        WorkspaceRecordField(
                          'Value',
                          workspaceMoney(widget.session, row['stock_value']),
                          icon: Icons.currency_rupee_rounded,
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

class MobileMoneyWorkspace extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileMoneyWorkspace({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
  });

  @override
  State<MobileMoneyWorkspace> createState() => _MobileMoneyWorkspaceState();
}

class _MobileMoneyWorkspaceState extends State<MobileMoneyWorkspace> {
  final _search = TextEditingController();
  late Future<List<List<Map<String, dynamic>>>> _future;
  bool _customers = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MobileMoneyWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationId != widget.locationId) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = Future.wait<List<Map<String, dynamic>>>([
      widget.service.customerOutstanding(
        widget.session,
        locationId: widget.locationId,
        limit: 500,
      ),
      widget.service.supplierOutstanding(
        widget.session,
        locationId: widget.locationId,
        limit: 500,
      ),
    ]);
  }

  Future<void> _refresh() async {
    final next = Future.wait<List<Map<String, dynamic>>>([
      widget.service.customerOutstanding(
        widget.session,
        locationId: widget.locationId,
        limit: 500,
      ),
      widget.service.supplierOutstanding(
        widget.session,
        locationId: widget.locationId,
        limit: 500,
      ),
    ]);
    setState(() => _future = next);
    await next;
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> rows) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) {
      return rows;
    }
    return rows.where((row) {
      return row.values.any(
        (value) => value?.toString().toLowerCase().contains(q) == true,
      );
    }).toList();
  }

  double _sum(List<Map<String, dynamic>> rows, String key) => rows.fold<double>(
        0,
        (sum, row) =>
            sum +
            (row[key] is num
                ? (row[key] as num).toDouble()
                : double.tryParse(row[key]?.toString() ?? '') ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const WorkspaceLoadingList();
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
            ],
          );
        }
        final customers = snapshot.data?[0] ?? const <Map<String, dynamic>>[];
        final suppliers = snapshot.data?[1] ?? const <Map<String, dynamic>>[];
        final rows = _filter(_customers ? customers : suppliers);
        final customerDue = _sum(customers, 'total_outstanding');
        final supplierDue = _sum(suppliers, 'total_outstanding');

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: ThqMobileMetricCard(
                      label: 'Customer due',
                      value: workspaceMoney(widget.session, customerDue),
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ThqMobileMetricCard(
                      label: 'Supplier due',
                      value: workspaceMoney(widget.session, supplierDue),
                      icon: Icons.payments_outlined,
                    ),
                  ),
                ],
              ),
              if (widget.session.canReceiveCustomerPayment) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MobileCustomerPaymentPage(
                          session: widget.session,
                          service: widget.service,
                          locationId: widget.locationId,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add_card_rounded),
                    label: const Text('Receive customer payment'),
                  ),
                ),
              ],
              const SizedBox(height: 11),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Customers'),
                    icon: Icon(Icons.people_alt_outlined),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Suppliers'),
                    icon: Icon(Icons.local_shipping_outlined),
                  ),
                ],
                selected: {_customers},
                onSelectionChanged: (value) => setState(() {
                  _customers = value.first;
                  _search.clear();
                }),
              ),
              const SizedBox(height: 10),
              ThqMobileSearchField(
                controller: _search,
                hintText: _customers
                    ? 'Customer name, phone or status'
                    : 'Supplier name, phone or status',
                onChanged: (_) => setState(() {}),
                onClear: () {
                  _search.clear();
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              ThqMobileSectionHeader(
                title: _customers ? 'Receivables' : 'Payables',
                subtitle: '${rows.length} matching accounts',
              ),
              const SizedBox(height: 9),
              if (rows.isEmpty)
                ThqMobileEmptyState(
                  title: _customers ? 'No receivables found' : 'No payables found',
                  message: 'There is nothing matching the current search.',
                  icon: Icons.account_balance_wallet_outlined,
                )
              else
                ...rows.map((row) {
                  final name = _customers
                      ? row['customer_name']?.toString()
                      : row['supplier_name']?.toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: WorkspaceRecordCard(
                      title: name ?? 'Account',
                      subtitle: row['phone']?.toString() ?? '',
                      status: row['status']?.toString(),
                      trailing:
                          workspaceMoney(widget.session, row['total_outstanding']),
                      fields: [
                        WorkspaceRecordField(
                          'Invoices',
                          '${row['open_invoice_count'] ?? 0}',
                          icon: Icons.receipt_long_outlined,
                        ),
                        WorkspaceRecordField(
                          '90+ days',
                          workspaceMoney(widget.session, row['days_90_plus']),
                          icon: Icons.schedule_rounded,
                        ),
                        WorkspaceRecordField(
                          'Oldest',
                          workspaceDate(row['oldest_due_date']),
                          icon: Icons.event_busy_outlined,
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
