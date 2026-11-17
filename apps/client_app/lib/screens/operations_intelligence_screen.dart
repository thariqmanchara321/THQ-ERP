import 'dart:math' as math;
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/operations_intelligence_service.dart';

class OperationsIntelligenceScreen extends StatefulWidget {
  final ClientSession session;
  final OperationsIntelligenceService? service;
  const OperationsIntelligenceScreen({
    super.key,
    required this.session,
    this.service,
  });

  @override
  State<OperationsIntelligenceScreen> createState() =>
      _OperationsIntelligenceScreenState();
}

class _OperationsIntelligenceScreenState
    extends State<OperationsIntelligenceScreen>
    with SingleTickerProviderStateMixin {
  late final OperationsIntelligenceService _service;
  final TextEditingController _search = TextEditingController();
  late TabController _tabs;

  bool _loading = true;
  String? _error;
  int _days = 30;

  // Live Intelligence Data
  ExecutiveHealthSnapshot? _summary;
  List<InsightRecord> _insights = const [];
  List<ActionProposal> _actions = const [];
  List<Map<String, dynamic>> _inventory = const [];
  List<Map<String, dynamic>> _customers = const [];
  List<Map<String, dynamic>> _suppliers = const [];
  List<Map<String, dynamic>> _reorder = const [];
  List<Map<String, dynamic>> _orders = const [];
  final Set<String> _selectedReorder = <String>{};

  // Interactive Simulators State
  double _simPriceChangePct = 0.0;
  double _simElasticity = -1.2;
  double _simOrderQty = 500.0;
  double _simBulkDiscountPct = 10.0;
  double _simTargetDsoDays = 30.0;

  String get _tenantId => widget.session.business.id;
  String? get _locationId => LocationScopeService.selectedLocationId.value;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OperationsIntelligenceService();
    _tabs = TabController(length: 10, vsync: this);
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

      // Parallel fetch of v830 intelligence data and existing operational datasets
      final results = await Future.wait<dynamic>([
        _service.getExecutiveSummary(
          tenantId: _tenantId,
          locationId: _locationId,
          days: _days,
        ),
        _service.inventoryV830(
          tenantId: _tenantId,
          locationId: _locationId,
          days: _days,
          query: query,
        ),
        _service.getInsights(
          tenantId: _tenantId,
          locationId: _locationId,
          query: query,
        ),
        _service.getActions(
          tenantId: _tenantId,
          locationId: _locationId,
        ),
        _service.customerCredit(
          tenantId: _tenantId,
          locationId: _locationId,
          query: query,
        ),
        _service.supplierPayables(
          tenantId: _tenantId,
          locationId: _locationId,
          query: query,
        ),
        _service.reorder(
          tenantId: _tenantId,
          locationId: _locationId,
          days: _days,
          query: query,
        ),
        _service.purchaseOrders(
          tenantId: _tenantId,
          locationId: _locationId,
          query: query,
        ),
      ]);

      if (!mounted) return;

      final summary = results[0] as ExecutiveHealthSnapshot;
      final inventory = List<Map<String, dynamic>>.from(results[1] as List);
      var insights = List<InsightRecord>.from(results[2] as List);
      var actions = List<ActionProposal>.from(results[3] as List);
      final customers = List<Map<String, dynamic>>.from(results[4] as List);
      final suppliers = List<Map<String, dynamic>>.from(results[5] as List);
      final reorder = List<Map<String, dynamic>>.from(results[6] as List);
      final orders = List<Map<String, dynamic>>.from(results[7] as List);

      // If database has no saved insights yet, evaluate all collectors in-memory
      if (insights.isEmpty) {
        final context = OperationsIntelligenceContext(
          tenantId: _tenantId,
          locationId: _locationId,
          periodDays: _days,
          now: DateTime.now(),
        );
        insights = await _service.runCollection(context, persist: false);
      }

      // Generate proposals for display if none currently stored
      if (actions.isEmpty && insights.isNotEmpty) {
        actions = _generateProposalsFromInsights(insights);
      }

      setState(() {
        _summary = summary;
        _inventory = inventory;
        _insights = insights;
        _actions = actions;
        _customers = customers;
        _suppliers = suppliers;
        _reorder = reorder;
        _orders = orders;
        _selectedReorder.removeWhere(
          (key) => !_reorder.any((row) => _reorderKey(row) == key),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ActionProposal> _generateProposalsFromInsights(List<InsightRecord> insights) {
    final proposals = <ActionProposal>[];
    for (final ins in insights) {
      if (ins.severity == InsightSeverity.critical || ins.severity == InsightSeverity.warning) {
        final actionType = ins.category.contains('stock') || ins.category.contains('inventory')
            ? ActionType.createPurchaseOrder
            : (ins.category.contains('credit')
                ? ActionType.sendPaymentReminder
                : ActionType.adjustReorderLevel);

        proposals.add(
          ActionProposal(
            id: 'prop-${ins.id}',
            tenantId: ins.tenantId,
            locationId: ins.locationId,
            insightId: ins.id,
            actionType: actionType,
            payload: {'source_insight': ins.id, 'metric': ins.evidence.currentValue},
            previewSummary: '${ins.title} — ${ins.description}',
            status: ActionStatus.pendingApproval,
            createdAt: ins.createdAt,
          ),
        );
      }
    }
    return proposals;
  }

  void _openAiAssistantSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => ThqAiAssistantSheet(
        assistant: _service.aiAssistant,
        tenantId: _tenantId,
        locationId: _locationId,
      ),
    );
  }

  double _n(dynamic value) => (value as num?)?.toDouble() ?? 0;
  String _money(dynamic value) =>
      '${widget.session.currencyCode} ${_n(value).toStringAsFixed(2)}';
  String _qty(dynamic value) =>
      _n(value).toStringAsFixed(_n(value) % 1 == 0 ? 0 : 2);
  String _reorderKey(Map<String, dynamic> row) =>
      '${row['location_id']}|${row['variant_id']}';

  String _healthStatus(double score) => score >= 85
      ? 'Excellent'
      : score >= 70
          ? 'Good'
          : score >= 50
              ? 'Watch'
              : 'At Risk';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Executive Health'),
            Tab(icon: Icon(Icons.trending_up_outlined), text: 'Sales Intelligence'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Inventory & ABC'),
            Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'Financial & CCC'),
            Tab(icon: Icon(Icons.people_outline), text: 'Customer Credit'),
            Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Supplier Payables'),
            Tab(icon: Icon(Icons.shopping_cart_checkout_outlined), text: 'Procurement & Ops'),
            Tab(icon: Icon(Icons.shield_outlined), text: 'Risk & Anomalies'),
            Tab(icon: Icon(Icons.query_stats_outlined), text: 'Forecast & Simulation'),
            Tab(icon: Icon(Icons.task_alt_outlined), text: 'Action Centre'),
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
                    _tabExecutiveHealth(),
                    _tabSalesIntelligence(),
                    _tabInventoryIntelligence(),
                    _tabFinancialIntelligence(),
                    _tabCustomerCredit(),
                    _tabSupplierPayables(),
                    _tabProcurementAndOps(),
                    _tabRiskAndAnomalies(),
                    _tabForecastAndSimulations(),
                    _tabActionCentre(),
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
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Deterministic enterprise analytics, risk watchdog, predictive forecasting & actionable decision engine.',
                ),
              ],
            ),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search metrics / SKUs...',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _days,
            items: const [14, 30, 60, 90]
                .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _days = value);
              _load();
            },
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh intelligence',
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _openAiAssistantSheet,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Ask AI Assistant'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              const Text(
                'Operations Intelligence could not load.',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // ==========================================
  // TAB 1: EXECUTIVE HEALTH CONTROL CENTRE
  // ==========================================
  Widget _tabExecutiveHealth() {
    final s = _summary ?? ExecutiveHealthSnapshot(
      periodDays: _days,
      fromDate: DateTime.now().subtract(Duration(days: _days)),
      toDate: DateTime.now(),
      grossSales: 0,
      salesReturns: 0,
      netSales: 0,
      grossProfit: 0,
      grossMarginPct: 0,
      expenses: 0,
      netOperatingProfit: 0,
      orderCount: 0,
      averageOrderValue: 0,
      inventoryValue: 0,
      totalMonitoredVariants: 0,
      lowStockCount: 0,
      outOfStockCount: 0,
      deadStockCount: 0,
      overstockCount: 0,
      receivables: 0,
      overdueReceivables: 0,
      payables: 0,
      overduePayables: 0,
      unresolvedInsightsCount: 0,
      criticalInsightsCount: 0,
      pendingActionsCount: 0,
      compositeHealthScore: 80,
    );

    final workingCapital = s.inventoryValue + s.receivables - s.payables;
    final cogs = math.max(1.0, s.netSales - s.grossProfit);
    final dio = s.netSales > 0 ? (s.inventoryValue / cogs) * 365.0 : 0.0;
    final dso = s.netSales > 0 ? (s.receivables / s.netSales) * 365.0 : 0.0;
    final dpo = s.payables > 0 ? (s.payables / cogs) * 365.0 : 0.0;
    final ccc = dio + dso - dpo;
    final opexRatio = s.netSales > 0 ? (s.expenses / s.netSales) * 100.0 : 0.0;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Composite Score Banner
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: s.compositeHealthScore / 100.0,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey.withAlpha(50),
                        color: s.compositeHealthScore >= 80
                            ? Colors.green
                            : s.compositeHealthScore >= 60
                            ? Colors.amber
                            : Colors.red,
                      ),
                    ),
                    Text(
                      '${s.compositeHealthScore.toInt()}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Business Health Index',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (s.compositeHealthScore >= 80 ? Colors.green : Colors.amber).withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _healthStatus(s.compositeHealthScore).toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: s.compositeHealthScore >= 80 ? Colors.green : Colors.amber,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Evaluation window: $_days days • Operational scope: ${_locationId ?? 'All Business Stores'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _categoryScore('Gross Margin', s.grossMarginPct * 2.5),
                          const SizedBox(width: 24),
                          _categoryScore('Stock Health', math.max(0.0, 100.0 - (s.outOfStockCount * 5.0))),
                          const SizedBox(width: 24),
                          _categoryScore('Collection', math.max(0.0, 100.0 - (s.receivables > 0 ? (s.overdueReceivables / s.receivables) * 100.0 : 0.0))),
                          const SizedBox(width: 24),
                          _categoryScore('Operations', math.max(0.0, 100.0 - (s.criticalInsightsCount * 10.0))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Key Metric Cards
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Net Revenue ($_days d)',
                value: _money(s.netSales),
                subtitle: 'Gross Margin: ${s.grossMarginPct.toStringAsFixed(1)}%',
                icon: Icons.trending_up,
                color: Colors.blue,
              ),
            ),
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Inventory Value',
                value: _money(s.inventoryValue),
                subtitle: 'Stockouts: ${s.outOfStockCount} SKUs',
                icon: Icons.warehouse_outlined,
                color: Colors.purple,
              ),
            ),
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Net Working Capital',
                value: _money(workingCapital),
                subtitle: workingCapital >= 0 ? 'Adequate liquidity' : 'Capital deficit',
                icon: Icons.account_balance,
                color: workingCapital >= 0 ? Colors.green : Colors.red,
              ),
            ),
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Cash Conversion Cycle',
                value: '${ccc.toStringAsFixed(0)} days',
                subtitle: 'DIO + DSO - DPO',
                icon: Icons.repeat,
                color: ccc <= 60 ? Colors.teal : Colors.orange,
              ),
            ),
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'OpEx Ratio',
                value: '${opexRatio.toStringAsFixed(1)}%',
                subtitle: opexRatio <= 30 ? 'Controlled OpEx' : 'High overhead',
                icon: Icons.pie_chart_outline,
                color: opexRatio <= 30 ? Colors.green : Colors.amber,
              ),
            ),
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Overdue Receivables',
                value: _money(s.overdueReceivables),
                subtitle: 'Total debt: ${_money(s.receivables)}',
                icon: Icons.schedule_outlined,
                color: s.overdueReceivables == 0 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        const Text('Priority Insights & What Needs Attention',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        if (_insights.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('All operational indicators are healthy.')),
            ),
          )
        else
          ..._insights.take(5).map(
                (insight) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ThqInsightCard(
                    insight: insight,
                    onAcknowledge: () => _updateInsightStatus(insight.id, InsightStatus.acknowledged),
                    onResolve: () => _updateInsightStatus(insight.id, InsightStatus.resolved),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _categoryScore(String label, double score) {
    final clamped = score.clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(
              width: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: clamped / 100.0,
                  backgroundColor: Colors.grey.withAlpha(50),
                  color: clamped >= 80 ? Colors.green : (clamped >= 60 ? Colors.amber : Colors.red),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('${clamped.toInt()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: SALES INTELLIGENCE
  // ==========================================
  Widget _tabSalesIntelligence() {
    final s = _summary;
    final rev = s?.netSales ?? 0.0;
    final avgDaily = _days > 0 ? rev / _days : 0.0;
    final salesInsights = _insights.where((i) => i.engine == IntelligenceEngineType.sales).toList();

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Sales Velocity',
                value: '${_money(avgDaily)}/day',
                subtitle: '$_days-day run rate',
                icon: Icons.speed,
                color: Colors.blue,
              ),
            ),
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Gross Margin',
                value: '${(s?.grossMarginPct ?? 0).toStringAsFixed(1)}%',
                subtitle: 'Gross Profit: ${_money(s?.grossProfit ?? 0)}',
                icon: Icons.savings_outlined,
                color: (s?.grossMarginPct ?? 0) >= 20 ? Colors.green : Colors.orange,
              ),
            ),
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Net Margin',
                value: '${rev > 0 ? (((s?.netOperatingProfit ?? 0) / rev) * 100).toStringAsFixed(1) : 0}%',
                subtitle: 'Net Profit: ${_money(s?.netOperatingProfit ?? 0)}',
                icon: Icons.monetization_on_outlined,
                color: (s?.netOperatingProfit ?? 0) >= 0 ? Colors.green : Colors.red,
              ),
            ),
            SizedBox(
              width: 240,
              child: ThqIntelligenceMetricCard(
                label: 'Average Order Value',
                value: _money(s?.averageOrderValue ?? 0),
                subtitle: '${s?.orderCount ?? 0} total sales orders',
                icon: Icons.shopping_bag_outlined,
                color: Colors.indigo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Sales Intelligence Signals', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (salesInsights.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No sales anomalies or concentration risks detected.')),
            ),
          )
        else
          ...salesInsights.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ThqInsightCard(
                insight: i,
                onAcknowledge: () => _updateInsightStatus(i.id, InsightStatus.acknowledged),
                onResolve: () => _updateInsightStatus(i.id, InsightStatus.resolved),
              ),
            ),
          ),
      ],
    );
  }

  // ==========================================
  // TAB 3: INVENTORY & ABC CLASSIFICATION
  // ==========================================
  Widget _tabInventoryIntelligence() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_inventory.length} active inventory items • Universal variants with ABC Pareto distribution',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _table(
            columns: const [
              'Class',
              'Product',
              'SKU',
              'Store',
              'Available',
              'Reorder',
              'Avg/day',
              'Cover',
              'Stock Value',
              'Revenue Value',
              'Status',
            ],
            rows: _inventory.map((r) {
              final abc = (r['abc_class'] ?? 'C').toString();
              return [
                _abcBadge(abc),
                r['product_name'] ?? '—',
                r['sku'] ?? '—',
                r['location_name'] ?? '—',
                _qty(r['available_stock']),
                _qty(r['reorder_level']),
                _qty(r['avg_daily_sales']),
                r['days_of_cover'] == null ? '—' : '${_n(r['days_of_cover']).toStringAsFixed(1)} d',
                _money(r['stock_value']),
                _money(r['total_sales_value']),
                _status(r['status']),
              ];
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _abcBadge(String abc) {
    final color = switch (abc) {
      'A' => Colors.purple,
      'B' => Colors.blue,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        'Class $abc',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: color),
      ),
    );
  }

  // ==========================================
  // TAB 4: FINANCIAL & CCC
  // ==========================================
  Widget _tabFinancialIntelligence() {
    final s = _summary;
    final finInsights = _insights.where((i) => i.engine == IntelligenceEngineType.financial).toList();

    final workingCapital = (s?.inventoryValue ?? 0) + (s?.receivables ?? 0) - (s?.payables ?? 0);
    final cogs = math.max(1.0, (s?.netSales ?? 0) - (s?.grossProfit ?? 0));
    final dio = (s?.netSales ?? 0) > 0 ? ((s?.inventoryValue ?? 0) / cogs) * 365.0 : 0.0;
    final dso = (s?.netSales ?? 0) > 0 ? ((s?.receivables ?? 0) / (s?.netSales ?? 1)) * 365.0 : 0.0;
    final dpo = (s?.payables ?? 0) > 0 ? ((s?.payables ?? 0) / cogs) * 365.0 : 0.0;
    final ccc = dio + dso - dpo;
    final opexRatio = (s?.netSales ?? 0) > 0 ? ((s?.expenses ?? 0) / (s?.netSales ?? 1)) * 100.0 : 0.0;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: ThqIntelligenceMetricCard(
                label: 'Working Capital',
                value: _money(workingCapital),
                subtitle: 'Current Assets - Current Liabilities',
                icon: Icons.account_balance,
                color: workingCapital >= 0 ? Colors.green : Colors.red,
              ),
            ),
            SizedBox(
              width: 260,
              child: ThqIntelligenceMetricCard(
                label: 'Cash Conversion Cycle',
                value: '${ccc.toStringAsFixed(0)} days',
                subtitle: 'Speed of cash recovery cycle',
                icon: Icons.timelapse,
                color: Colors.blue,
              ),
            ),
            SizedBox(
              width: 260,
              child: ThqIntelligenceMetricCard(
                label: 'Operating Expense Ratio',
                value: '${opexRatio.toStringAsFixed(1)}%',
                subtitle: 'OpEx relative to total revenue',
                icon: Icons.pie_chart,
                color: opexRatio <= 35 ? Colors.teal : Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Financial & Capital Intelligence', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (finInsights.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Financial ratios and working capital are currently stable.')),
            ),
          )
        else
          ...finInsights.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ThqInsightCard(
                insight: i,
                onAcknowledge: () => _updateInsightStatus(i.id, InsightStatus.acknowledged),
                onResolve: () => _updateInsightStatus(i.id, InsightStatus.resolved),
              ),
            ),
          ),
      ],
    );
  }

  // ==========================================
  // TAB 5: CUSTOMER CREDIT
  // ==========================================
  Widget _tabCustomerCredit() => _table(
    columns: const [
      'Customer',
      'Phone',
      'Outstanding',
      'Credit Limit',
      'Available',
      'Usage %',
      'Current',
      '1–30 d',
      '31–60 d',
      '61–90 d',
      '90+ d Overdue',
      'Status',
    ],
    rows: _customers
        .map(
          (r) => [
            r['customer_name'] ?? '—',
            r['phone'] ?? '—',
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
          ],
        )
        .toList(),
  );

  // ==========================================
  // TAB 6: SUPPLIER PAYABLES
  // ==========================================
  Widget _tabSupplierPayables() => _table(
    columns: const [
      'Supplier',
      'Phone',
      'Outstanding',
      'Current',
      '1–30 d',
      '31–60 d',
      '61–90 d',
      '90+ d Overdue',
      'Open Invoices',
      'Oldest Due',
      'Status',
    ],
    rows: _suppliers
        .map(
          (r) => [
            r['supplier_name'] ?? '—',
            r['phone'] ?? '—',
            _money(r['total_outstanding']),
            _money(r['current_amount']),
            _money(r['days_1_30']),
            _money(r['days_31_60']),
            _money(r['days_61_90']),
            _money(r['days_90_plus']),
            '${r['open_invoice_count'] ?? 0}',
            r['oldest_due_date'] ?? '—',
            _status(r['status']),
          ],
        )
        .toList(),
  );

  // ==========================================
  // TAB 7: PROCUREMENT & OPERATIONS
  // ==========================================
  Widget _tabProcurementAndOps() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_reorder.length} reorder suggestions • ${_selectedReorder.length} selected for purchase order creation',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              FilledButton.icon(
                onPressed: _selectedReorder.isEmpty
                    ? null
                    : _createSelectedPurchaseOrders,
                icon: const Icon(Icons.add_shopping_cart),
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
              'Reorder Level',
              'Avg/day',
              'Cover',
              'Suggested Order',
              'Last Supplier',
              'Last Unit Cost',
            ],
            sourceRows: _reorder,
            rowBuilder: (r) => [
              r['location_name'] ?? '—',
              r['product_name'] ?? '—',
              r['sku'] ?? '—',
              _qty(r['current_stock']),
              _qty(r['reorder_level']),
              _qty(r['avg_daily_sales']),
              r['days_cover'] == null
                  ? '—'
                  : '${_n(r['days_cover']).toStringAsFixed(1)} d',
              _qty(r['suggested_quantity']),
              r['last_supplier_name'] ?? 'No supplier history',
              _money(r['last_unit_cost']),
            ],
          ),
        ),
        if (_orders.isNotEmpty) ...[
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
            alignment: Alignment.centerLeft,
            child: Text(
              'Active Purchase Orders (${_orders.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          SizedBox(
            height: 180,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              itemCount: _orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final row = _orders[index];
                return Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      '${row['order_number']} • ${row['supplier_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${row['location_name']} • ${row['item_count']} items • ${_money(row['grand_total'])}',
                    ),
                    trailing: _status(row['status']),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================
  // TAB 8: RISK & ANOMALIES WATCHDOG
  // ==========================================
  Widget _tabRiskAndAnomalies() {
    final anomalies = _insights
        .where((i) =>
            i.engine == IntelligenceEngineType.riskAnomaly ||
            i.severity == InsightSeverity.critical ||
            i.severity == InsightSeverity.warning)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Operational Risk & Anomaly Watchdog',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Automated surveillance of negative margins, unusual cashier discounts, duplicate payments, and sudden return spikes.',
        ),
        const SizedBox(height: 16),
        if (anomalies.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No critical risk anomalies detected across active transactions.'),
              ),
            ),
          )
        else
          ...anomalies.map(
            (anomaly) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ThqInsightCard(
                insight: anomaly,
                onAcknowledge: () => _updateInsightStatus(anomaly.id, InsightStatus.acknowledged),
                onResolve: () => _updateInsightStatus(anomaly.id, InsightStatus.resolved),
              ),
            ),
          ),
      ],
    );
  }

  // ==========================================
  // TAB 9: FORECAST & SIMULATIONS
  // ==========================================
  Widget _tabForecastAndSimulations() {
    // Run simulations in memory based on current state
    final simElasticityResult = _service.simulatePricingChange(
      baseSellingPrice: 100.0,
      baseCostPrice: 60.0,
      baseVolume: 1000.0,
      priceChangePercent: _simPriceChangePct,
      priceElasticity: _simElasticity,
    );

    final simBulkResult = _service.simulateBulkPurchase(
      standardUnitCost: 100.0,
      bulkUnitCost: 100.0 * (1.0 - _simBulkDiscountPct / 100.0),
      orderQuantity: _simOrderQty,
      annualHoldingCostRate: 0.20,
      estimatedMonthsToSell: 3.0,
    );

    final simCreditResult = _service.simulateCreditPolicy(
      currentAnnualCreditSales: (_summary?.netSales ?? 100000) * 0.8,
      currentAverageCollectionDays: 55.0,
      proposedAverageCollectionDays: _simTargetDsoDays,
    );

    final profitDelta = (simElasticityResult['profit_delta'] as num?)?.toDouble() ?? 0.0;
    final netBenefit = (simBulkResult['net_benefit'] as num?)?.toDouble() ?? 0.0;
    final wcReleased = (simCreditResult['working_capital_released'] as num?)?.toDouble() ?? 0.0;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Business Simulation & Decision Engine',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Explore hypothetical pricing elasticity, bulk volume purchasing, and credit collection policy without mutating live ledgers.'),
        const SizedBox(height: 18),

        // Simulator 1: Price Elasticity
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text('Pricing Elasticity Simulator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('Projected Profit Impact: ${_money(profitDelta)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: profitDelta >= 0 ? Colors.green : Colors.red)),
                  ],
                ),
                const SizedBox(height: 12),
                ThqSimulationSlider(
                  label: 'Price Adjustment',
                  value: _simPriceChangePct,
                  min: -30,
                  max: 30,
                  divisions: 12,
                  suffix: '%',
                  onChanged: (v) => setState(() => _simPriceChangePct = v),
                ),
                ThqSimulationSlider(
                  label: 'Demand Elasticity Coefficient',
                  value: _simElasticity,
                  min: -2.5,
                  max: -0.2,
                  divisions: 23,
                  suffix: '',
                  onChanged: (v) => setState(() => _simElasticity = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Projected Volume: ${((simElasticityResult['new_volume'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} units • Projected Revenue: ${_money(simElasticityResult['new_revenue'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Simulator 2: Bulk Purchase vs Holding Cost
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Text('Bulk Purchase Trade-off Simulator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('Net Annual Benefit: ${_money(netBenefit)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: netBenefit >= 0 ? Colors.green : Colors.red)),
                  ],
                ),
                const SizedBox(height: 12),
                ThqSimulationSlider(
                  label: 'Order Batch Size',
                  value: _simOrderQty,
                  min: 100,
                  max: 2000,
                  divisions: 19,
                  suffix: ' units',
                  onChanged: (v) => setState(() => _simOrderQty = v),
                ),
                ThqSimulationSlider(
                  label: 'Supplier Volume Discount',
                  value: _simBulkDiscountPct,
                  min: 1,
                  max: 30,
                  divisions: 29,
                  suffix: '%',
                  onChanged: (v) => setState(() => _simBulkDiscountPct = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Discount Savings: ${_money(simBulkResult['discount_savings'])} • Holding Cost: ${_money(simBulkResult['carrying_cost'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Simulator 3: Credit Policy & DSO
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.savings, color: Colors.teal),
                    const SizedBox(width: 8),
                    const Text('Credit Terms & DSO Simulator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('Working Capital Released: ${_money(wcReleased)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 12),
                ThqSimulationSlider(
                  label: 'Target Days Sales Outstanding (DSO)',
                  value: _simTargetDsoDays,
                  min: 15,
                  max: 60,
                  divisions: 45,
                  suffix: ' days',
                  onChanged: (v) => setState(() => _simTargetDsoDays = v),
                ),
                const SizedBox(height: 8),
                Text(
                  'Projected annual cost of capital savings: ${_money(simCreditResult['annual_capital_savings'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 10: ACTION CENTRE
  // ==========================================
  Widget _tabActionCentre() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Intelligence Action Centre',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Actionable recommendations proposed by BI engines requiring authorized human review.'),
                ],
              ),
            ),
            Text('${_actions.length} Total Proposals', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        if (_actions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No pending action proposals at this time.')),
            ),
          )
        else
          ..._actions.map(
            (action) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            action.actionType.code.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            action.previewSummary,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ),
                        _status(action.status.name),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (action.status == ActionStatus.pendingApproval) ...[
                          OutlinedButton(
                            onPressed: () => _decideActionProposal(action.id, false),
                            child: const Text('Reject Proposal'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => _decideActionProposal(action.id, true),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Approve Action'),
                          ),
                        ] else
                          Text(
                            'Decision recorded: ${action.status.name}',
                            style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // --- Insight & Action Mutations ---

  Future<void> _updateInsightStatus(String insightId, InsightStatus status) async {
    try {
      await _service.updateInsightStatus(
        tenantId: _tenantId,
        insightId: insightId,
        status: status,
      );
      await _load();
      if (mounted) {
        ThqNotify.success(context, 'Insight marked as ${status.name}.');
      }
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _decideActionProposal(String actionId, bool approve) async {
    try {
      await _service.decideAction(
        tenantId: _tenantId,
        actionId: actionId,
        approve: approve,
      );
      await _load();
      if (mounted) {
        ThqNotify.success(
          context,
          approve ? 'Action proposal approved.' : 'Action proposal rejected.',
        );
      }
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text('Action update failed: $e')));
      }
    }
  }

  // --- Purchase Order Creation from Reorder ---

  Future<void> _createSelectedPurchaseOrders() async {
    final rows = _reorder
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
              'Created from THQ reorder suggestions ($_days-day demand window).',
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
      await _load();
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

  // --- Data Table & Formatting Helpers ---

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
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
    final severe =
        text.contains('critical') ||
        text.contains('out of stock') ||
        text.contains('over limit');
    final warn =
        text.contains('low stock') || text == 'overdue' || text == 'submitted';
    final color = severe
        ? Theme.of(context).colorScheme.errorContainer
        : warn
        ? Color.alphaBlend(
            context.thqSemanticColors.warning.withAlpha(30),
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
