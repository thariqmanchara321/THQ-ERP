import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../models/dashboard_data.dart';
import '../models/dashboard_insights.dart';
import '../services/dashboard_service.dart';
import '../services/location_scope_service.dart';
import '../ui/v43_theme.dart';

class _DashboardFutureCacheEntry<T> {
  const _DashboardFutureCacheEntry({
    required this.loadedAt,
    required this.future,
  });

  final DateTime loadedAt;
  final Future<T> future;
}

class DashboardScreen extends StatefulWidget {
  final ClientSession session;
  const DashboardScreen({super.key, required this.session});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Duration _dashboardCacheTtl = Duration(seconds: 30);
  static const Duration _dashboardCacheRetention = Duration(minutes: 2);
  static final Map<String, _DashboardFutureCacheEntry<DashboardData>>
  _summaryCache = <String, _DashboardFutureCacheEntry<DashboardData>>{};
  static final Map<String, _DashboardFutureCacheEntry<DashboardInsights>>
  _insightsCache = <String, _DashboardFutureCacheEntry<DashboardInsights>>{};
  static final Map<String, _DashboardFutureCacheEntry<Map<String, dynamic>>>
  _businessIntelligenceCache =
      <String, _DashboardFutureCacheEntry<Map<String, dynamic>>>{};

  final DashboardService _service = DashboardService();
  late Future<DashboardData> _summary;
  late Future<DashboardInsights> _insights;
  late Future<Map<String, dynamic>> _businessIntelligence;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dashboardCacheKey {
    final locationId = LocationScopeService.currentForRead(widget.session);
    return '${widget.session.business.id}|${locationId ?? 'all'}';
  }

  Future<T> _cachedFuture<T>({
    required Map<String, _DashboardFutureCacheEntry<T>> cache,
    required String key,
    required bool force,
    required Future<T> Function() loader,
  }) {
    final now = DateTime.now();
    cache.removeWhere(
      (_, entry) => now.difference(entry.loadedAt) > _dashboardCacheRetention,
    );

    final cached = cache[key];
    if (!force &&
        cached != null &&
        now.difference(cached.loadedAt) < _dashboardCacheTtl) {
      return cached.future;
    }

    final future = loader();
    cache[key] = _DashboardFutureCacheEntry<T>(loadedAt: now, future: future);
    return future;
  }

  void _load({bool force = false}) {
    final key = _dashboardCacheKey;
    _summary = _cachedFuture<DashboardData>(
      cache: _summaryCache,
      key: key,
      force: force,
      loader: () => _service.load(session: widget.session),
    );
    _insights = _cachedFuture<DashboardInsights>(
      cache: _insightsCache,
      key: key,
      force: force,
      loader: () => _service.insights(session: widget.session),
    );
    _businessIntelligence = _cachedFuture<Map<String, dynamic>>(
      cache: _businessIntelligenceCache,
      key: key,
      force: force,
      loader: () => _service.businessIntelligence(session: widget.session),
    );
  }

  Future<void> _refresh() async {
    setState(() => _load(force: true));
    await Future.wait([_summary, _insights, _businessIntelligence]);
  }

  String _money(double value) => widget.session.currencyCode == 'INR'
      ? '₹${value.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final profile = UiDesignScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: profile.background,
        gradient: profile.gradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  profile.background,
                  Color.alphaBlend(
                    profile.primary.withValues(alpha: 0.055),
                    profile.background,
                  ),
                  profile.background,
                ],
              )
            : null,
      ),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: DesktopReleaseStatus(
                showVersion: false,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 6),
            _pageHeader(context),
            const SizedBox(height: 18),
            FutureBuilder<DashboardData>(
              future: _summary,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorCard(
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }
                final data = snapshot.data!;
                return Column(
                  children: [
                    _metricGrid(context, data),
                    const SizedBox(height: 16),
                    _secondaryMetrics(context, data),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            FutureBuilder<Map<String, dynamic>>(
              future: _businessIntelligence,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 96,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorCard(
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }
                return _v5BusinessIntelligencePanel(
                  snapshot.data ?? const <String, dynamic>{},
                );
              },
            ),
            const SizedBox(height: 18),
            FutureBuilder<DashboardInsights>(
              future: _insights,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 360,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorCard(
                    message: snapshot.error.toString(),
                    onRetry: _refresh,
                  );
                }
                final insights = snapshot.data!;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1050;
                    final trend = _TrendCard(
                      rows: insights.dailySales,
                      money: _money,
                    );
                    final topProducts = _RankedCard(
                      title: 'Top selling products',
                      subtitle: 'Best performers in the selected store scope',
                      icon: Icons.inventory_2_outlined,
                      rows: insights.topProducts
                          .map(
                            (x) => _RankedRow(
                              x.productName,
                              '${x.quantity.toStringAsFixed(0)} sold',
                              _money(x.sales),
                            ),
                          )
                          .toList(),
                    );
                    if (!wide) {
                      return Column(
                        children: [
                          trend,
                          const SizedBox(height: 16),
                          topProducts,
                          const SizedBox(height: 16),
                          _customersCard(insights),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: trend),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: topProducts),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _customersCard(insights),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _v5BusinessIntelligencePanel(Map<String, dynamic> data) {
    double n(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    int i(dynamic value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    List<Map<String, dynamic>> rows(String key) => data[key] is List
        ? (data[key] as List)
              .whereType<Map>()
              .map((x) => Map<String, dynamic>.from(x))
              .toList()
        : const <Map<String, dynamic>>[];
    final storeRows = rows('store_comparison');
    final posRows = rows('pos_comparison');
    return V43Surface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Business Intelligence v5',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Return-aware profit, cash/bank, dead stock and store/POS comparison',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _biChip(
                'Gross profit',
                _money(n(data['gross_profit'])),
                Icons.insights_outlined,
              ),
              _biChip(
                'Gross margin',
                '${n(data['gross_margin_pct']).toStringAsFixed(2)}%',
                Icons.percent,
              ),
              _biChip(
                'Expenses',
                _money(n(data['expenses'])),
                Icons.receipt_long_outlined,
              ),
              _biChip(
                'Cash / bank',
                _money(n(data['cash_bank'])),
                Icons.account_balance_wallet_outlined,
              ),
              _biChip(
                'Customer outstanding',
                _money(n(data['receivables'])),
                Icons.request_quote_outlined,
              ),
              _biChip(
                'Supplier dues',
                _money(n(data['payables'])),
                Icons.payments_outlined,
              ),
              _biChip(
                'Low stock',
                '${i(data['low_stock_count'])}',
                Icons.warning_amber_rounded,
              ),
              _biChip(
                'Dead stock',
                '${i(data['dead_stock_count'])}',
                Icons.inventory_2_outlined,
              ),
            ],
          ),
          if (storeRows.isNotEmpty || posRows.isNotEmpty) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, c) {
                final children = <Widget>[
                  if (storeRows.isNotEmpty)
                    Expanded(
                      child: _comparisonList(
                        'Store comparison',
                        storeRows,
                        'name',
                      ),
                    ),
                  if (storeRows.isNotEmpty && posRows.isNotEmpty)
                    const SizedBox(width: 12),
                  if (posRows.isNotEmpty)
                    Expanded(
                      child: _comparisonList(
                        'POS comparison',
                        posRows,
                        'device',
                      ),
                    ),
                ];
                if (c.maxWidth < 760) {
                  return Column(
                    children: [
                      if (storeRows.isNotEmpty)
                        _comparisonList('Store comparison', storeRows, 'name'),
                      if (storeRows.isNotEmpty && posRows.isNotEmpty)
                        const SizedBox(height: 10),
                      if (posRows.isNotEmpty)
                        _comparisonList('POS comparison', posRows, 'device'),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _biChip(String label, String value, IconData icon) => Container(
    width: 190,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10.5)),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _comparisonList(
    String title,
    List<Map<String, dynamic>> rows,
    String labelKey,
  ) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...rows
              .take(6)
              .map(
                (r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (r[labelKey] ?? r['location_code'] ?? 'Unknown')
                              .toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _money(
                          (r['net_sales'] is num
                                  ? r['net_sales'] as num
                                  : num.tryParse(
                                          r['net_sales']?.toString() ?? '',
                                        ) ??
                                        0)
                              .toDouble(),
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    ),
  );

  Widget _pageHeader(BuildContext context) {
    final profile = UiDesignScope.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sales, profit, stock and cash flow at a glance',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: profile.surface,
            borderRadius: BorderRadius.circular(profile.radius * .75),
            border: Border.all(color: profile.border),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 17, color: profile.primary),
              const SizedBox(width: 7),
              Text(
                profile.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: _refresh,
          tooltip: 'Refresh dashboard',
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _metricGrid(BuildContext context, DashboardData d) {
    final metrics = [
      _MetricData(
        'Today sales',
        _money(d.todaySales),
        'Live business',
        Icons.point_of_sale_outlined,
        true,
      ),
      _MetricData(
        'Month sales',
        _money(d.monthSales),
        'Current month',
        Icons.trending_up_rounded,
        true,
      ),
      _MetricData(
        'Net profit',
        _money(d.monthNetProfit),
        'After expenses',
        Icons.account_balance_wallet_outlined,
        d.monthNetProfit >= 0,
      ),
      _MetricData(
        'Receivables',
        _money(d.receivables),
        'Customer balance',
        Icons.request_quote_outlined,
        false,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 1120
            ? 4
            : c.maxWidth >= 650
            ? 2
            : 1;
        final gap = 12.0;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map(
                (m) => SizedBox(
                  width: width,
                  child: _MetricCard(data: m),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _secondaryMetrics(BuildContext context, DashboardData d) {
    final items = [
      ('Purchases', _money(d.monthPurchases), Icons.shopping_cart_outlined),
      ('Expenses', _money(d.monthExpenses), Icons.receipt_long_outlined),
      ('Payables', _money(d.payables), Icons.payments_outlined),
      ('Low stock', '${d.lowStockCount}', Icons.warning_amber_rounded),
      ('Products', '${d.productCount}', Icons.inventory_2_outlined),
      ('Customers', '${d.customerCount}', Icons.groups_outlined),
      ('Suppliers', '${d.supplierCount}', Icons.local_shipping_outlined),
    ];
    return V43Surface(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: LayoutBuilder(
        builder: (context, c) {
          return Wrap(
            children: items.map((item) {
              final width = c.maxWidth >= 1050
                  ? c.maxWidth / 7
                  : c.maxWidth >= 650
                  ? c.maxWidth / 4
                  : c.maxWidth / 2;
              return SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.$3,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$1,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _customersCard(DashboardInsights insights) {
    return _RankedCard(
      title: 'Top customers',
      subtitle: 'Customers contributing the most sales',
      icon: Icons.groups_outlined,
      horizontal: true,
      rows: insights.topCustomers
          .map(
            (x) => _RankedRow(
              x.customerName,
              '${x.invoiceCount} invoices',
              _money(x.sales),
            ),
          )
          .toList(),
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final bool positive;
  const _MetricData(
    this.label,
    this.value,
    this.caption,
    this.icon,
    this.positive,
  );
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;
  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final p = UiDesignScope.of(context);
    return V43Surface(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                p.primary.withValues(alpha: .11),
                p.surface,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(data.icon, size: 20, color: p.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.caption,
                  style: TextStyle(
                    fontSize: 10,
                    color: data.positive
                        ? p.success
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<DailySalesInsight> rows;
  final String Function(double) money;
  const _TrendCard({required this.rows, required this.money});

  @override
  Widget build(BuildContext context) {
    final p = UiDesignScope.of(context);
    final data = rows.length > 14 ? rows.sublist(rows.length - 14) : rows;
    final total = data.fold<double>(0, (sum, e) => sum + e.sales);
    return V43Surface(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sales trend',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Last ${data.length} days • ${money(total)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _LegendDot(color: p.primary, label: 'Daily sales'),
              ],
            ),
            const SizedBox(height: 22),
            Expanded(
              child: data.isEmpty
                  ? const Center(child: Text('No sales trend yet.'))
                  : CustomPaint(
                      painter: _LineChartPainter(
                        values: data.map((e) => e.sales).toList(),
                        color: p.primary,
                        grid: p.border,
                      ),
                      child: const SizedBox.expand(),
                    ),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: data.isEmpty
                  ? const []
                  : [data.first, data[data.length ~/ 2], data.last]
                        .map(
                          (e) => Text(
                            '${e.date.day}/${e.date.month}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                        .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color grid;
  const _LineChartPainter({
    required this.values,
    required this.color,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: .75)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.isEmpty) return;
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final maxV = rawMax < 1.0 ? 1.0 : rawMax;
    final step = values.length == 1
        ? size.width
        : size.width / (values.length - 1);
    final path = Path();
    final fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * step;
      final y =
          size.height -
          (values[i] / maxV) * (size.height * .84) -
          size.height * .06;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .20), color.withValues(alpha: .01)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (values.length > 1) {
      final i = values.length - 1;
      final x = i * step;
      final y =
          size.height -
          (values[i] / maxV) * (size.height * .84) -
          size.height * .06;
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = color);
      canvas.drawCircle(Offset(x, y), 2.1, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.grid != grid;
}

class _RankedRow {
  final String title;
  final String caption;
  final String value;
  const _RankedRow(this.title, this.caption, this.value);
}

class _RankedCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<_RankedRow> rows;
  final bool horizontal;
  const _RankedCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.rows,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = UiDesignScope.of(context);
    final content = rows.isEmpty
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text('No data yet.')),
          )
        : horizontal
        ? Wrap(
            spacing: 10,
            runSpacing: 10,
            children: rows
                .take(6)
                .map(
                  (row) => SizedBox(
                    width: 250,
                    child: _row(context, p, row, rows.indexOf(row)),
                  ),
                )
                .toList(),
          )
        : Column(
            children: rows
                .take(7)
                .toList()
                .asMap()
                .entries
                .map((e) => _row(context, p, e.value, e.key))
                .toList(),
          );
    return V43Surface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    p.primary.withValues(alpha: .10),
                    p.surface,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: p.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.more_horiz,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 14),
          content,
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    UiDesignProfile p,
    _RankedRow row,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                p.primary.withValues(alpha: .08),
                p.surface,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: p.primary,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  row.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            row.value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => V43Surface(
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        const Icon(Icons.error_outline),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
