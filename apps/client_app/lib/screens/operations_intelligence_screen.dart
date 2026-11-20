import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/client_navigation_scope.dart';
import '../services/location_scope_service.dart';
import '../services/operations_intelligence_service.dart';

/// Supported intelligence demand & review period windows.
enum IntelligencePeriod {
  today(1, 'Today'),
  days7(7, '7 Days'),
  days30(30, '30 Days'),
  days90(90, '90 Days');

  final int days;
  final String label;
  const IntelligencePeriod(this.days, this.label);
}

/// Generic state holder for independent asynchronous loading of workspace sections.
class SectionState<T> {
  final T data;
  final bool loading;
  final String? error;
  final DateTime? lastLoaded;

  const SectionState({
    required this.data,
    this.loading = false,
    this.error,
    this.lastLoaded,
  });

  bool get hasError => error != null;
  bool get hasData => error == null;

  SectionState<T> toLoading() => SectionState<T>(
        data: data,
        loading: true,
        error: null,
        lastLoaded: lastLoaded,
      );

  SectionState<T> toSuccess(T newData) => SectionState<T>(
        data: newData,
        loading: false,
        error: null,
        lastLoaded: DateTime.now(),
      );

  SectionState<T> toError(String err) => SectionState<T>(
        data: data,
        loading: false,
        error: err,
        lastLoaded: lastLoaded,
      );
}

/// Helper model for period-over-period metric comparisons.
class ComparisonMetric {
  final double current;
  final double previous;
  final double difference;
  final double? percentChange;
  final bool hasPrevious;

  const ComparisonMetric({
    required this.current,
    required this.previous,
    required this.difference,
    required this.percentChange,
    required this.hasPrevious,
  });

  bool get isPositive => difference > 0;
  bool get isNegative => difference < 0;
  bool get isNeutral => difference == 0;

  factory ComparisonMetric.calculate(double current, double previous) {
    final diff = current - previous;
    double? pct;
    if (previous > 0) {
      pct = (diff / previous) * 100.0;
    } else if (previous == 0 && current > 0) {
      pct = 100.0;
    } else if (previous == 0 && current == 0) {
      pct = 0.0;
    } else {
      pct = null;
    }
    return ComparisonMetric(
      current: current,
      previous: previous,
      difference: diff,
      percentChange: pct,
      hasPrevious: previous != 0 || current != 0,
    );
  }
}

class OperationsIntelligenceScreen extends StatefulWidget {
  final ClientSession session;
  final int? initialTab;
  final OperationsIntelligenceService? service;

  const OperationsIntelligenceScreen({
    super.key,
    required this.session,
    this.initialTab,
    this.service,
  });

  @override
  State<OperationsIntelligenceScreen> createState() =>
      _OperationsIntelligenceScreenState();
}

class _OperationsIntelligenceScreenState
    extends State<OperationsIntelligenceScreen>
    with SingleTickerProviderStateMixin {
  late final OperationsIntelligenceService _service =
      widget.service ?? OperationsIntelligenceService();
  final TextEditingController _search = TextEditingController();
  late TabController _tabs;

  IntelligencePeriod _selectedPeriod = IntelligencePeriod.days30;
  int _requestSequence = 0;

  // Independent section states
  SectionState<Map<String, dynamic>> _overviewState =
      const SectionState(data: {});
  SectionState<Map<String, dynamic>> _prevOverviewState =
      const SectionState(data: {});
  SectionState<List<Map<String, dynamic>>> _inventoryState =
      const SectionState(data: []);
  SectionState<List<Map<String, dynamic>>> _customerCreditState =
      const SectionState(data: []);
  SectionState<List<Map<String, dynamic>>> _supplierPayablesState =
      const SectionState(data: []);
  SectionState<List<Map<String, dynamic>>> _reorderState =
      const SectionState(data: []);
  SectionState<List<Map<String, dynamic>>> _ordersState =
      const SectionState(data: []);
  SectionState<List<Map<String, dynamic>>> _storesState =
      const SectionState(data: []);

  final Set<String> _selectedReorder = <String>{};
  String _stockFilter = 'all';
  String _orderStatusFilter = 'all';

  String get _tenantId => widget.session.business.id;
  String? get _locationId => LocationScopeService.selectedLocationId.value;
  bool get _canViewCost =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('inventory.view_cost') ||
      widget.session.hasPermission('inventory.manage');
  bool get _isMultiLocation => widget.session.locations.length > 1;

  @override
  void initState() {
    super.initState();
    final tabCount = 6;
    final initial = (widget.initialTab ?? 0).clamp(0, tabCount - 1);
    _tabs = TabController(length: tabCount, vsync: this, initialIndex: initial);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });

    LocationScopeService.selectedLocationId.addListener(_onLocationScopeChanged);
    _loadAll();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_onLocationScopeChanged);
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onLocationScopeChanged() {
    if (!mounted) return;
    _loadAll(force: true);
  }

  /// Triggers independent async loading for each workspace section.
  /// A failure in any one section does not crash or block the others.
  void _loadAll({bool force = false}) {
    final seq = ++_requestSequence;
    _loadOverview(seq);
    _loadInventory(seq);
    _loadCustomerCredit(seq);
    _loadSupplierPayables(seq);
    _loadReorder(seq);
    _loadPurchaseOrders(seq);
    if (_isMultiLocation && _locationId == null) {
      _loadStoreComparison(seq);
    }
  }

  Future<void> _loadOverview([int? seq]) async {
    final currentSeq = seq ?? ++_requestSequence;
    setState(() {
      _overviewState = _overviewState.toLoading();
      _prevOverviewState = _prevOverviewState.toLoading();
    });

    // 1. Current period summary
    try {
      final summary = await _service.operationsSummary(
        tenantId: _tenantId,
        locationId: _locationId,
        days: _selectedPeriod.days,
      );
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _overviewState = _overviewState.toSuccess(summary));
    } catch (e) {
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _overviewState = _overviewState.toError(e.toString()));
    }

    // 2. Comparison period summary (double days window)
    try {
      final doubleSummary = await _service.operationsSummary(
        tenantId: _tenantId,
        locationId: _locationId,
        days: _selectedPeriod.days * 2,
      );
      if (!mounted || currentSeq != _requestSequence) return;
      setState(
        () => _prevOverviewState = _prevOverviewState.toSuccess(doubleSummary),
      );
    } catch (_) {
      // Comparison failure is non-fatal: fallback to neutral comparison
      if (mounted && currentSeq == _requestSequence) {
        setState(
          () => _prevOverviewState = _prevOverviewState.toSuccess(const {}),
        );
      }
    }
  }

  Future<void> _loadInventory([int? seq]) async {
    final currentSeq = seq ?? ++_requestSequence;
    setState(() => _inventoryState = _inventoryState.toLoading());
    try {
      final query = _search.text.trim();
      final rows = await _service.inventory(
        tenantId: _tenantId,
        locationId: _locationId,
        days: _selectedPeriod.days,
        query: query,
        useV830: true,
      );
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _inventoryState = _inventoryState.toSuccess(rows));
    } catch (e) {
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _inventoryState = _inventoryState.toError(e.toString()));
    }
  }

  Future<void> _loadCustomerCredit([int? seq]) async {
    final currentSeq = seq ?? ++_requestSequence;
    setState(() => _customerCreditState = _customerCreditState.toLoading());
    try {
      final query = _search.text.trim();
      final rows = await _service.customerCredit(
        tenantId: _tenantId,
        locationId: _locationId,
        query: query,
      );
      if (!mounted || currentSeq != _requestSequence) return;
      setState(
        () => _customerCreditState = _customerCreditState.toSuccess(rows),
      );
    } catch (e) {
      if (!mounted || currentSeq != _requestSequence) return;
      setState(
        () => _customerCreditState = _customerCreditState.toError(e.toString()),
      );
    }
  }

  Future<void> _loadSupplierPayables([int? seq]) async {
    final currentSeq = seq ?? ++_requestSequence;
    setState(() => _supplierPayablesState = _supplierPayablesState.toLoading());
    try {
      final query = _search.text.trim();
      final rows = await _service.supplierPayables(
        tenantId: _tenantId,
        locationId: _locationId,
        query: query,
      );
      if (!mounted || currentSeq != _requestSequence) return;
      setState(
        () => _supplierPayablesState = _supplierPayablesState.toSuccess(rows),
      );
    } catch (e) {
      if (!mounted || currentSeq != _requestSequence) return;
      setState(
        () => _supplierPayablesState =
            _supplierPayablesState.toError(e.toString()),
      );
    }
  }

  Future<void> _loadReorder([int? seq]) async {
    final currentSeq = seq ?? ++_requestSequence;
    setState(() => _reorderState = _reorderState.toLoading());
    try {
      final query = _search.text.trim();
      final rows = await _service.reorder(
        tenantId: _tenantId,
        locationId: _locationId,
        days: _selectedPeriod.days,
        query: query,
      );
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() {
        _reorderState = _reorderState.toSuccess(rows);
        _selectedReorder.removeWhere(
          (key) => !rows.any((r) => _reorderKey(r) == key),
        );
      });
    } catch (e) {
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _reorderState = _reorderState.toError(e.toString()));
    }
  }

  Future<void> _loadPurchaseOrders([int? seq]) async {
    final currentSeq = seq ?? ++_requestSequence;
    setState(() => _ordersState = _ordersState.toLoading());
    try {
      final query = _search.text.trim();
      final rows = await _service.purchaseOrders(
        tenantId: _tenantId,
        locationId: _locationId,
        query: query,
      );
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _ordersState = _ordersState.toSuccess(rows));
    } catch (e) {
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _ordersState = _ordersState.toError(e.toString()));
    }
  }

  Future<void> _loadStoreComparison([int? seq]) async {
    final currentSeq = seq ?? ++_requestSequence;
    setState(() => _storesState = _storesState.toLoading());
    try {
      final storeRows = <Map<String, dynamic>>[];
      for (final loc in widget.session.locations) {
        final locSummary = await _service.operationsSummary(
          tenantId: _tenantId,
          locationId: loc.id,
          days: _selectedPeriod.days,
        );
        storeRows.add({
          'location_id': loc.id,
          'location_code': loc.code,
          'location_name': loc.name,
          'summary': locSummary,
        });
      }
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _storesState = _storesState.toSuccess(storeRows));
    } catch (e) {
      if (!mounted || currentSeq != _requestSequence) return;
      setState(() => _storesState = _storesState.toError(e.toString()));
    }
  }

  double _n(dynamic value) => (value as num?)?.toDouble() ?? 0;
  String _money(dynamic value) =>
      '${widget.session.currencyCode} ${_n(value).toStringAsFixed(2)}';
  String _qty(dynamic value) =>
      _n(value).toStringAsFixed(_n(value) % 1 == 0 ? 0 : 2);
  String _reorderKey(Map<String, dynamic> row) =>
      '${row['location_id']}|${row['variant_id']}';

  ComparisonMetric _calcFlowMetric(String key) {
    final curr = _n(_overviewState.data[key]);
    final doubleTotal = _n(_prevOverviewState.data[key]);
    final prev = math.max(0.0, doubleTotal - curr);
    return ComparisonMetric.calculate(curr, prev);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            const Tab(text: 'Overview'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Stock Intelligence'),
                  if (_inventoryState.loading) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Customer Credit'),
                  if (_customerCreditState.loading) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Supplier Payables'),
                  if (_supplierPayablesState.loading) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Purchase Planning'),
                  if (_reorderState.loading) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Purchase Orders'),
                  if (_ordersState.loading) ...[
                    const SizedBox(width: 6),
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _overviewTab(),
              _stockTab(),
              _customerCreditTab(),
              _supplierPayablesTab(),
              _planningTab(),
              _purchaseOrdersTab(),
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
                Text(
                  'Operations Intelligence',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2),
                Text(
                  'Live operational analytics, demand planning, credit exposure, and multi-store health.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _loadAll(force: true),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Search product / customer / supplier',
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _search.clear();
                          _loadAll(force: true);
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<IntelligencePeriod>(
            segments: IntelligencePeriod.values
                .map(
                  (p) => ButtonSegment(
                    value: p,
                    label: Text(p.label, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
            selected: {_selectedPeriod},
            onSelectionChanged: (set) {
              if (set.isNotEmpty) {
                setState(() => _selectedPeriod = set.first);
                _loadAll(force: true);
              }
            },
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () => _loadAll(force: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh all intelligence',
          ),
        ],
      ),
    );
  }

  Widget _sectionError(String title, String? error, VoidCallback onRetry) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$title could not be loaded',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (error != null && error.isNotEmpty)
                  Text(
                    error,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // TAB 0: EXECUTIVE BUSINESS OVERVIEW
  // ==========================================================================

  Widget _overviewTab() {
    if (_overviewState.loading && _overviewState.data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_overviewState.hasError && _overviewState.data.isEmpty) {
      return _sectionError(
        'Executive Overview',
        _overviewState.error,
        _loadOverview,
      );
    }

    final data = _overviewState.data;
    final grossSales = _calcFlowMetric('gross_sales');
    final netSales = _calcFlowMetric('net_sales');
    final returns = _calcFlowMetric('sales_returns');
    final orderCount = _calcFlowMetric('order_count');
    final aov = _calcFlowMetric('average_order_value');
    final grossProfit = _calcFlowMetric('gross_profit');
    final expenses = _calcFlowMetric('expenses');
    final netProfit = _calcFlowMetric('net_operating_profit');

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        if (_overviewState.hasError)
          _sectionError(
            'Executive Overview (showing cached figures)',
            _overviewState.error,
            _loadOverview,
          ),

        // Section 1: Sales & Commercial Performance
        _sectionHeader(
          'Sales & Revenue',
          Icons.trending_up,
          subtitle:
              'Period window: ${_selectedPeriod.label} (${data['from_date'] ?? ''} to ${data['to_date'] ?? ''})',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              title: 'Gross Sales',
              value: _money(grossSales.current),
              icon: Icons.point_of_sale,
              metric: grossSales,
            ),
            _metricCard(
              title: 'Net Sales',
              value: _money(netSales.current),
              icon: Icons.payments_outlined,
              metric: netSales,
            ),
            _metricCard(
              title: 'Sales Returns',
              value: _money(returns.current),
              icon: Icons.assignment_return_outlined,
              metric: returns,
              invertTrend: true,
            ),
            _metricCard(
              title: 'Total Transactions',
              value: grossSales.current > 0 || orderCount.current > 0
                  ? orderCount.current.toInt().toString()
                  : '0',
              icon: Icons.receipt_long,
              metric: orderCount,
            ),
            _metricCard(
              title: 'Average Order Value (AOV)',
              value: _money(aov.current),
              icon: Icons.query_stats,
              metric: aov,
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Section 2: Profitability & Margins (with cost permission enforcement)
        _sectionHeader(
          'Profitability',
          Icons.account_balance_outlined,
          subtitle: _canViewCost
              ? 'Authoritative margins computed from real inventory costs'
              : 'Cost visibility is restricted for your role',
          action: !_canViewCost
              ? _statusBadge('Cost Restricted', isWarning: true)
              : null,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              title: 'Gross Profit',
              value: _canViewCost ? _money(grossProfit.current) : null,
              icon: Icons.savings_outlined,
              metric: _canViewCost ? grossProfit : null,
              isRestricted: !_canViewCost,
            ),
            _metricCard(
              title: 'Gross Margin',
              value: _canViewCost
                  ? '${_n(data['gross_margin_pct']).toStringAsFixed(1)}%'
                  : null,
              icon: Icons.pie_chart_outline,
              isRestricted: !_canViewCost,
            ),
            _metricCard(
              title: 'Operating Expenses',
              value: _money(expenses.current),
              icon: Icons.receipt_outlined,
              metric: expenses,
              invertTrend: true,
            ),
            _metricCard(
              title: 'Net Operating Profit',
              value: _canViewCost ? _money(netProfit.current) : null,
              icon: Icons.show_chart,
              metric: _canViewCost ? netProfit : null,
              isRestricted: !_canViewCost,
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Section 3: Inventory Health & Stock Value
        _sectionHeader('Inventory Health', Icons.warehouse_outlined),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              title: 'Total Stock Value',
              value: _canViewCost ? _money(data['inventory_value']) : null,
              icon: Icons.attach_money,
              isRestricted: !_canViewCost,
            ),
            _metricCard(
              title: 'Monitored Variants',
              value: '${data['total_monitored_variants'] ?? 0}',
              icon: Icons.category_outlined,
            ),
            _metricCard(
              title: 'Out of Stock',
              value: '${data['out_of_stock'] ?? data['out_of_stock_count'] ?? 0}',
              icon: Icons.remove_shopping_cart_outlined,
              isWarning: _n(data['out_of_stock']) > 0,
            ),
            _metricCard(
              title: 'Low Stock Alerts',
              value: '${data['low_stock'] ?? data['low_stock_count'] ?? 0}',
              icon: Icons.warning_amber_outlined,
              isWarning: _n(data['low_stock']) > 0,
            ),
            _metricCard(
              title: 'Dead Stock (>90d idle)',
              value: '${data['dead_stock'] ?? data['dead_stock_count'] ?? 0}',
              icon: Icons.inventory_2_outlined,
            ),
            _metricCard(
              title: 'Overstock Items',
              value: '${data['overstock'] ?? data['overstock_count'] ?? 0}',
              icon: Icons.unarchive_outlined,
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Section 4: Working Capital Position
        _sectionHeader('Business Position', Icons.account_balance_wallet_outlined),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              title: 'Customer Receivables',
              value: _money(data['receivables']),
              icon: Icons.account_balance_wallet_outlined,
              extraLabel: _n(data['overdue_receivables']) > 0
                  ? 'Overdue: ${_money(data['overdue_receivables'])}'
                  : null,
            ),
            _metricCard(
              title: 'Supplier Payables',
              value: _money(data['payables']),
              icon: Icons.credit_card_outlined,
              extraLabel: _n(data['overdue_payables']) > 0
                  ? 'Overdue: ${_money(data['overdue_payables'])}'
                  : null,
            ),
            _metricCard(
              title: 'Cash & Bank Balances',
              value: null,
              icon: Icons.account_balance,
              extraLabel: 'Accounting ledger integration required',
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Section 5: Operational Attention Indicators
        _sectionHeader('Operational Attention', Icons.notification_important_outlined),
        const SizedBox(height: 10),
        _operationalPipelinesGrid(data),
        const SizedBox(height: 22),

        // Section 6: Multi-Store Comparison (for authorized multi-store users)
        if (_isMultiLocation) ...[
          _sectionHeader(
            'Store Comparison',
            Icons.store_mall_directory_outlined,
            subtitle: _locationId == null
                ? 'Consolidated breakdown across all active locations'
                : 'Viewing single store context (${LocationScopeService.scopeLabel(widget.session)})',
          ),
          const SizedBox(height: 10),
          _storeComparisonSection(),
          const SizedBox(height: 22),
        ],

        // Section 7: Top Selling Products
        if ((data['top_products'] as List? ?? const []).isNotEmpty) ...[
          _sectionHeader('Top Selling Products', Icons.local_fire_department_outlined),
          const SizedBox(height: 10),
          _topProductsTable(data['top_products'] as List),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, {String? subtitle, Widget? action}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else if (action != null)
          const Spacer(),
        ?action,
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String? value,
    required IconData icon,
    ComparisonMetric? metric,
    bool isWarning = false,
    bool isRestricted = false,
    bool invertTrend = false,
    String? extraLabel,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: 215,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isWarning
            ? colors.errorContainer.withValues(alpha: 0.25)
            : colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isWarning
              ? colors.error.withValues(alpha: 0.35)
              : colors.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isWarning ? colors.error : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isWarning ? colors.error : colors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isRestricted) ...[
            Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Access restricted',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ] else if (value == null) ...[
            Text(
              'Not available',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
          ] else ...[
            Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: isWarning ? colors.error : colors.onSurface,
              ),
            ),
          ],
          if (metric != null && metric.percentChange != null) ...[
            const SizedBox(height: 6),
            _trendBadge(metric.percentChange!, invert: invertTrend),
          ],
          if (extraLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              extraLabel,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: isWarning ? colors.error : colors.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _trendBadge(double pct, {bool invert = false}) {
    final isPositive = pct > 0;
    final isNeutral = pct == 0;
    final isGood = invert ? !isPositive : isPositive;
    final color = isNeutral
        ? Colors.grey
        : isGood
            ? Colors.green.shade700
            : Colors.red.shade700;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isNeutral
              ? Icons.remove
              : isPositive
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
          size: 11,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}% vs prev',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String label, {bool isWarning = false}) {
    final theme = Theme.of(context);
    final color =
        isWarning ? theme.colorScheme.error : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _operationalPipelinesGrid(Map<String, dynamic> data) {
    final pipelines = <(String, dynamic, IconData)>[
      (
        'PR approvals awaiting',
        data['purchase_requests_awaiting_approval'] ?? 0,
        Icons.approval_outlined,
      ),
      (
        'PO approvals awaiting',
        data['purchase_orders_awaiting_approval'] ?? 0,
        Icons.fact_check_outlined,
      ),
      (
        'Draft GRNs',
        data['draft_grns'] ?? 0,
        Icons.inventory_outlined,
      ),
      (
        'Draft invoices',
        data['draft_purchase_invoices'] ?? 0,
        Icons.receipt_long_outlined,
      ),
      (
        'Transfers in transit',
        data['transfers_in_transit'] ?? 0,
        Icons.local_shipping_outlined,
      ),
      (
        'Offline POS conflicts',
        data['offline_pos_conflicts'] ?? 0,
        Icons.sync_problem_outlined,
      ),
      (
        'Batches expiring ≤30d',
        data['batches_expiring_30d'] ?? 0,
        Icons.event_busy_outlined,
      ),
      (
        'Warranties expiring ≤30d',
        data['warranties_expiring_30d'] ?? 0,
        Icons.verified_user_outlined,
      ),
      (
        'Restaurant open orders',
        data['restaurant_open_orders'] ?? 0,
        Icons.restaurant_outlined,
      ),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: pipelines.map((item) {
        final count = _n(item.$2).toInt();
        final hasAttention = count > 0;
        return Container(
          width: 175,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: hasAttention
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasAttention
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(item.$3, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.$1,
                  style: const TextStyle(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: hasAttention
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: hasAttention
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _storeComparisonSection() {
    if (_locationId != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Focused on location: ${LocationScopeService.scopeLabel(widget.session)}. Reset location filter in the top bar to compare all stores.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => LocationScopeService.selectedLocationId.value = null,
            icon: const Icon(Icons.clear, size: 14),
            label: const Text('View All Stores'),
          ),
        ],
      );
    }

    if (_storesState.loading && _storesState.data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_storesState.hasError && _storesState.data.isEmpty) {
      return _sectionError(
        'Store Comparison',
        _storesState.error,
        _loadStoreComparison,
      );
    }

    final storeRows = _storesState.data;
    if (storeRows.isEmpty) {
      return const Text('No location data available.');
    }

    return DataTable(
      columnSpacing: 18,
      columns: [
        const DataColumn(label: Text('Store / Location')),
        const DataColumn(label: Text('Net Sales')),
        if (_canViewCost) const DataColumn(label: Text('Gross Profit')),
        const DataColumn(label: Text('Orders')),
        const DataColumn(label: Text('Low / Out Stock')),
        const DataColumn(label: Text('Receivables')),
        const DataColumn(label: Text('Action')),
      ],
      rows: storeRows.map((s) {
        final locId = s['location_id'] as String;
        final sum = s['summary'] as Map<String, dynamic>? ?? const {};
        final lowStock = _n(sum['low_stock']).toInt();
        final outStock = _n(sum['out_of_stock']).toInt();
        return DataRow(
          cells: [
            DataCell(Text('${s['location_name']} (${s['location_code']})')),
            DataCell(Text(_money(sum['net_sales']))),
            if (_canViewCost) DataCell(Text(_money(sum['gross_profit']))),
            DataCell(Text('${sum['order_count'] ?? 0}')),
            DataCell(Text('$lowStock low • $outStock out')),
            DataCell(Text(_money(sum['receivables']))),
            DataCell(
              TextButton(
                onPressed: () =>
                    LocationScopeService.selectedLocationId.value = locId,
                child: const Text('Filter Store'),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _topProductsTable(List topProducts) {
    return DataTable(
      columnSpacing: 24,
      columns: const [
        DataColumn(label: Text('Product')),
        DataColumn(label: Text('SKU')),
        DataColumn(label: Text('Quantity Sold')),
        DataColumn(label: Text('Revenue')),
      ],
      rows: topProducts.map((p) {
        final row = Map<String, dynamic>.from(p as Map);
        return DataRow(
          cells: [
            DataCell(Text(row['product_name']?.toString() ?? '')),
            DataCell(Text(row['sku']?.toString() ?? '')),
            DataCell(Text(_qty(row['quantity_sold']))),
            DataCell(Text(_money(row['revenue']))),
          ],
        );
      }).toList(),
    );
  }

  // ==========================================================================
  // TAB 1: STOCK INTELLIGENCE
  // ==========================================================================

  Widget _stockTab() {
    if (_inventoryState.loading && _inventoryState.data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_inventoryState.hasError && _inventoryState.data.isEmpty) {
      return _sectionError(
        'Stock Intelligence',
        _inventoryState.error,
        _loadInventory,
      );
    }

    final raw = _inventoryState.data;
    final filtered = raw.where((r) {
      if (_stockFilter == 'all') return true;
      final st = r['status']?.toString().toLowerCase() ?? '';
      return st == _stockFilter;
    }).toList();

    return Column(
      children: [
        if (_inventoryState.hasError)
          _sectionError(
            'Stock Intelligence (cached view)',
            _inventoryState.error,
            _loadInventory,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('all', 'All (${raw.length})'),
                      const SizedBox(width: 6),
                      _filterChip(
                        'out_of_stock',
                        'Out of Stock (${raw.where((r) => r['status'] == 'out_of_stock').length})',
                      ),
                      const SizedBox(width: 6),
                      _filterChip(
                        'low_stock',
                        'Low Stock (${raw.where((r) => r['status'] == 'low_stock').length})',
                      ),
                      const SizedBox(width: 6),
                      _filterChip(
                        'dead_stock',
                        'Dead Stock (${raw.where((r) => r['status'] == 'dead_stock').length})',
                      ),
                      const SizedBox(width: 6),
                      _filterChip(
                        'overstock',
                        'Overstock (${raw.where((r) => r['status'] == 'overstock').length})',
                      ),
                    ],
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  // Seamlessly switch to Smart Inventory inside the same unified shell
                  ClientNavigationScope.navigate(context, 'smart_inventory');
                },
                icon: const Icon(Icons.qr_code_scanner, size: 16),
                label: const Text('Smart Inventory'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _table(
            columns: [
              'Store',
              'ABC',
              'Product',
              'SKU',
              'Available',
              'Reorder',
              'Max',
              'Avg/day',
              'Cover',
              'Suggested',
              'Value',
              'Status',
            ],
            rows: filtered.map((r) {
              final abc = r['abc_class']?.toString() ?? 'C';
              return [
                r['location_name'],
                _abcBadge(abc),
                r['product_name'],
                r['sku'],
                _qty(r['available']),
                _qty(r['reorder_level']),
                _qty(r['max_stock']),
                _qty(r['avg_daily_sales']),
                r['days_cover'] == null
                    ? '—'
                    : '${_n(r['days_cover']).toStringAsFixed(1)} d',
                _qty(r['suggested_reorder']),
                _canViewCost ? _money(r['stock_value']) : '—',
                _status(r['status']),
              ];
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String key, String label) {
    final active = _stockFilter == key;
    return ChoiceChip(
      selected: active,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onSelected: (_) => setState(() => _stockFilter = key),
    );
  }

  Widget _abcBadge(String abc) {
    final color = abc == 'A'
        ? Colors.green.shade700
        : abc == 'B'
            ? Colors.orange.shade700
            : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        abc,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  // ==========================================================================
  // TAB 2: CUSTOMER CREDIT
  // ==========================================================================

  Widget _customerCreditTab() {
    if (_customerCreditState.loading && _customerCreditState.data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_customerCreditState.hasError && _customerCreditState.data.isEmpty) {
      return _sectionError(
        'Customer Credit',
        _customerCreditState.error,
        _loadCustomerCredit,
      );
    }

    return Column(
      children: [
        if (_customerCreditState.hasError)
          _sectionError(
            'Customer Credit (cached view)',
            _customerCreditState.error,
            _loadCustomerCredit,
          ),
        Expanded(
          child: _table(
            columns: const [
              'Customer',
              'Phone',
              'Outstanding',
              'Limit',
              'Available',
              'Usage',
              'Current',
              '1–30',
              '31–60',
              '61–90',
              '90+',
              'Status',
            ],
            rows: _customerCreditState.data.map((r) => [
              r['customer_name'],
              r['phone'],
              _money(r['total_outstanding']),
              _money(r['credit_limit']),
              _money(r['available_credit']),
              r['utilization_pct'] == null
                  ? '—'
                  : '${_n(r['utilization_pct']).toStringAsFixed(1)}%',
              _money(r['current_amount']),
              _money(r['days_1_30']),
              _money(r['days_31_60']),
              _money(r['days_61_90']),
              _money(r['days_90_plus']),
              _status(r['status']),
            ]).toList(),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 3: SUPPLIER PAYABLES
  // ==========================================================================

  Widget _supplierPayablesTab() {
    if (_supplierPayablesState.loading && _supplierPayablesState.data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_supplierPayablesState.hasError && _supplierPayablesState.data.isEmpty) {
      return _sectionError(
        'Supplier Payables',
        _supplierPayablesState.error,
        _loadSupplierPayables,
      );
    }

    return Column(
      children: [
        if (_supplierPayablesState.hasError)
          _sectionError(
            'Supplier Payables (cached view)',
            _supplierPayablesState.error,
            _loadSupplierPayables,
          ),
        Expanded(
          child: _table(
            columns: const [
              'Supplier',
              'Phone',
              'Outstanding',
              'Current',
              '1–30',
              '31–60',
              '61–90',
              '90+',
              'Status',
            ],
            rows: _supplierPayablesState.data.map((r) => [
              r['supplier_name'],
              r['phone'],
              _money(r['total_outstanding']),
              _money(r['current_amount']),
              _money(r['days_1_30']),
              _money(r['days_31_60']),
              _money(r['days_61_90']),
              _money(r['days_90_plus']),
              _status(r['status']),
            ]).toList(),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 4: PURCHASE PLANNING (REORDER SUGGESTIONS)
  // ==========================================================================

  Widget _planningTab() {
    if (_reorderState.loading && _reorderState.data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reorderState.hasError && _reorderState.data.isEmpty) {
      return _sectionError(
        'Purchase Planning',
        _reorderState.error,
        _loadReorder,
      );
    }

    final reorder = _reorderState.data;

    return Column(
      children: [
        if (_reorderState.hasError)
          _sectionError(
            'Purchase Planning (cached view)',
            _reorderState.error,
            _loadReorder,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${reorder.length} reorder suggestions • ${_selectedReorder.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                onPressed: _selectedReorder.isEmpty
                    ? null
                    : _createSelectedPurchaseOrders,
                icon: const Icon(Icons.add_shopping_cart, size: 16),
                label: const Text('Create PO from selected'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _table(
            leading: true,
            columns: const [
              'Store',
              'Product',
              'SKU',
              'Stock',
              'Reorder',
              'Avg/day',
              'Cover',
              'Suggested',
              'Last supplier',
              'Last cost',
            ],
            sourceRows: reorder,
            rowBuilder: (r) => [
              r['location_name'],
              r['product_name'],
              r['sku'],
              _qty(r['current_stock']),
              _qty(r['reorder_level']),
              _qty(r['avg_daily_sales']),
              r['days_cover'] == null
                  ? '—'
                  : '${_n(r['days_cover']).toStringAsFixed(1)} d',
              _qty(r['suggested_quantity']),
              r['last_supplier_name'] ?? 'No supplier history',
              _canViewCost ? _money(r['last_unit_cost']) : '—',
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 5: PURCHASE ORDERS WORKFLOW
  // ==========================================================================

  Widget _purchaseOrdersTab() {
    if (_ordersState.loading && _ordersState.data.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ordersState.hasError && _ordersState.data.isEmpty) {
      return _sectionError(
        'Purchase Orders',
        _ordersState.error,
        _loadPurchaseOrders,
      );
    }

    final allOrders = _ordersState.data;
    final filtered = allOrders.where((o) {
      if (_orderStatusFilter == 'all') return true;
      return o['status']?.toString().toLowerCase() == _orderStatusFilter;
    }).toList();

    return Column(
      children: [
        if (_ordersState.hasError)
          _sectionError(
            'Purchase Orders (cached view)',
            _ordersState.error,
            _loadPurchaseOrders,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _orderFilterChip('all', 'All (${allOrders.length})'),
                    const SizedBox(width: 6),
                    _orderFilterChip('draft', 'Draft'),
                    const SizedBox(width: 6),
                    _orderFilterChip('submitted', 'Submitted'),
                    const SizedBox(width: 6),
                    _orderFilterChip('approved', 'Approved'),
                    const SizedBox(width: 6),
                    _orderFilterChip('ordered', 'Ordered'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No purchase orders found.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = filtered[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.description_outlined),
                        ),
                        title: Text(
                          '${row['order_number']} • ${row['supplier_name']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${row['location_name']} • ${row['order_date']} • ${row['item_count']} items • ${_money(row['grand_total'])}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _status(row['status']),
                            PopupMenuButton<String>(
                              tooltip: 'Change status',
                              onSelected: (value) =>
                                  _changeOrderStatus(row, value),
                              itemBuilder: (_) =>
                                  _nextStatuses(row['status']?.toString() ?? '')
                                      .map(
                                        (s) => PopupMenuItem(
                                          value: s,
                                          child: Text(s.toUpperCase()),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ],
                        ),
                        onTap: () => _showOrder(row['id'].toString()),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _orderFilterChip(String status, String label) {
    final active = _orderStatusFilter == status;
    return ChoiceChip(
      selected: active,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onSelected: (_) => setState(() => _orderStatusFilter = status),
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

  Future<void> _changeOrderStatus(
    Map<String, dynamic> row,
    String action,
  ) async {
    final purchaseOrderId = row['id'].toString();
    try {
      if (action == 'approve' || action == 'reject') {
        var draftNote = '';
        final approving = action == 'approve';
        final note = await showThqDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              approving ? 'Approve purchase order' : 'Reject purchase order',
            ),
            content: TextField(
              onChanged: (value) => draftNote = value,
              decoration: InputDecoration(
                labelText: approving
                    ? 'Approval note (optional)'
                    : 'Rejection reason',
              ),
              autofocus: !approving,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Back'),
              ),
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
          final result = await showThqDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Cancel purchase order'),
              content: TextField(
                onChanged: (value) => draftReason = value,
                decoration: const InputDecoration(labelText: 'Reason'),
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Back'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, draftReason.trim()),
                  child: const Text('Cancel PO'),
                ),
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
      _loadPurchaseOrders();
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('PO update failed: $error')),
        );
      }
    }
  }

  Future<void> _showOrder(String id) async {
    try {
      final detail = await _service.purchaseOrderDetail(
        tenantId: _tenantId,
        purchaseOrderId: id,
      );
      if (!mounted) return;
      final order = Map<String, dynamic>.from(
        detail['order'] as Map? ?? const {},
      );
      final items = (detail['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final history = (detail['history'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      await showThqDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '${order['order_number'] ?? 'Purchase Order'} • ${order['status'] ?? ''}',
          ),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order['supplier_name'] ?? ''} • ${order['location_name'] ?? ''}',
                  ),
                  const SizedBox(height: 12),
                  ...items.map(
                    (i) => ListTile(
                      dense: true,
                      title: Text('${i['product_name']} • ${i['sku'] ?? ''}'),
                      subtitle: Text(
                        '${_qty(i['quantity'])} × ${_money(i['unit_cost'])}',
                      ),
                      trailing: Text(_money(i['line_total'])),
                    ),
                  ),
                  const Divider(),
                  const Text(
                    'Status history',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  ...history.map(
                    (h) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.history, size: 18),
                      title: Text(
                        '${h['from_status'] ?? 'created'} → ${h['to_status']}',
                      ),
                      subtitle: Text(
                        '${h['changed_at'] ?? ''}${(h['reason'] ?? '').toString().isEmpty ? '' : ' • ${h['reason']}'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Could not open PO: $error')),
        );
      }
    }
  }

  Future<void> _createSelectedPurchaseOrders() async {
    final rows = _reorderState.data
        .where((r) => _selectedReorder.contains(_reorderKey(r)))
        .toList();
    if (rows.any((r) => (r['last_supplier_id']?.toString() ?? '').isEmpty)) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(
          content: Text(
            'Some selected products have no purchase supplier history. Select products with a supplier.',
          ),
        ),
      );
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
          notes:
              'Created from THQ reorder suggestions (${_selectedPeriod.days}-day demand window).',
          items: entry.value
              .map(
                (r) => <String, dynamic>{
                  'variant_id': r['variant_id'],
                  'quantity': _n(r['suggested_quantity']),
                  'unit_cost': _n(r['last_unit_cost']),
                  'tax_rate': _n(r['tax_rate']),
                },
              )
              .toList(),
        );
      }
      _selectedReorder.clear();
      _loadReorder();
      _loadPurchaseOrders();
      if (mounted) {
        ThqNotify.success(
          context,
          '${groups.length} purchase order(s) created as Draft.',
        );
      }
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('PO creation failed: $error')),
        );
      }
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
    if (dataRows.isEmpty) {
      return const Center(child: Text('No matching records.'));
    }
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              if (leading) const DataColumn(label: Text('')),
              ...columns.map(
                (c) => DataColumn(
                  label: Text(
                    c,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            rows: List<DataRow>.generate(dataRows.length, (index) {
              final source = sourceRows == null ? null : sourceRows[index];
              final selected = source == null
                  ? false
                  : _selectedReorder.contains(_reorderKey(source));
              return DataRow(
                selected: selected,
                cells: [
                  if (leading)
                    DataCell(
                      Checkbox(
                        value: selected,
                        onChanged: (value) => setState(() {
                          final key = _reorderKey(source!);
                          if (value == true) {
                            _selectedReorder.add(key);
                          } else {
                            _selectedReorder.remove(key);
                          }
                        }),
                      ),
                    ),
                  ...dataRows[index].map(
                    (value) => DataCell(
                      value is Widget ? value : Text(value?.toString() ?? ''),
                    ),
                  ),
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
    final severe = text.contains('critical') ||
        text.contains('out of stock') ||
        text.contains('over limit');
    final warn = text.contains('low stock') ||
        text == 'overdue' ||
        text == 'submitted';
    final color = severe
        ? Theme.of(context).colorScheme.errorContainer
        : warn
            ? Color.alphaBlend(
                context.thqSemanticColors.warning.withValues(alpha: .12),
                Theme.of(context).colorScheme.surface,
              )
            : Theme.of(context).colorScheme.secondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.isEmpty ? '—' : text.toUpperCase(),
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
