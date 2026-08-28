import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/dashboard_data.dart';
import '../models/dashboard_insights.dart';
import '../services/dashboard_service.dart';
import '../ui/v43_theme.dart';

class DashboardScreen extends StatefulWidget {
  final ClientSession session;
  const DashboardScreen({super.key, required this.session});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _service = DashboardService();
  late Future<DashboardData> _summary;
  late Future<DashboardInsights> _insights;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _summary = _service.load(session: widget.session);
    _insights = _service.insights(session: widget.session);
  }

  Future<void> _refresh() async {
    setState(_load);
    await Future.wait([_summary, _insights]);
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
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 30),
          children: [
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
                  fontSize: 28,
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
