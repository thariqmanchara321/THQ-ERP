import 'package:flutter/material.dart';
import '../models/client_session.dart';
import '../models/dashboard_data.dart';
import '../models/dashboard_insights.dart';
import '../services/dashboard_service.dart';

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
    _summary = _service.load(tenantId: widget.session.business.id);
    _insights = _service.insights(tenantId: widget.session.business.id);
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
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dashboard',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Sales, cash flow, stock and customer performance',
                        style: TextStyle(
                          fontSize: 8.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh dashboard',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    FutureBuilder<DashboardData>(
                      future: _summary,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox(
                            height: 100,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(snapshot.error.toString()),
                          );
                        }
                        final d = snapshot.data!;
                        final metrics = <Widget>[
                          _Metric(
                            'Today Sales',
                            _money(d.todaySales),
                            Icons.point_of_sale,
                          ),
                          _Metric(
                            'Month Sales',
                            _money(d.monthSales),
                            Icons.trending_up,
                          ),
                          _Metric(
                            'Net Profit',
                            _money(d.monthNetProfit),
                            Icons.account_balance_wallet_outlined,
                          ),
                          _Metric(
                            'Receivables',
                            _money(d.receivables),
                            Icons.request_quote_outlined,
                          ),
                          _Metric(
                            'Payables',
                            _money(d.payables),
                            Icons.payments_outlined,
                          ),
                          _Metric(
                            'Expenses',
                            _money(d.monthExpenses),
                            Icons.receipt_long_outlined,
                          ),
                          _Metric(
                            'Low Stock',
                            d.lowStockCount.toString(),
                            Icons.warning_amber,
                          ),
                          _Metric(
                            'Products',
                            d.productCount.toString(),
                            Icons.inventory_2_outlined,
                          ),
                        ];

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 1000
                                ? 4
                                : constraints.maxWidth >= 700
                                ? 3
                                : 2;
                            const gap = 5.0;
                            final width =
                                (constraints.maxWidth - ((columns - 1) * gap)) /
                                columns;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: metrics
                                  .map(
                                    (metric) =>
                                        SizedBox(width: width, child: metric),
                                  )
                                  .toList(),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 5),
                    FutureBuilder<DashboardInsights>(
                      future: _insights,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(snapshot.error.toString()),
                          );
                        }

                        final d = snapshot.data!;
                        return Column(
                          children: [
                            _SalesBars(rows: d.dailySales, money: _money),
                            const SizedBox(height: 5),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final products = _ListCard(
                                  title: 'Top Selling Products',
                                  rows: d.topProducts
                                      .map(
                                        (x) => (
                                          '${x.productName} | '
                                              '${x.quantity.toStringAsFixed(0)} qty',
                                          _money(x.sales),
                                        ),
                                      )
                                      .toList(),
                                );
                                final customers = _ListCard(
                                  title: 'Top Customers',
                                  rows: d.topCustomers
                                      .map(
                                        (x) => (
                                          '${x.customerName} | '
                                              '${x.invoiceCount} invoices',
                                          _money(x.sales),
                                        ),
                                      )
                                      .toList(),
                                );

                                if (constraints.maxWidth < 760) {
                                  return Column(
                                    children: [
                                      products,
                                      const SizedBox(height: 5),
                                      customers,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: products),
                                    const SizedBox(width: 5),
                                    Expanded(child: customers),
                                  ],
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 7.5,
                    color: scheme.onSurfaceVariant,
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

class _ListCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _ListCard({required this.title, required this.rows});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          if (rows.isEmpty)
            Text(
              'No data yet.',
              style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant),
            )
          else
            ...rows
                .take(8)
                .map(
                  (x) => SizedBox(
                    height: 25,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            x.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 7.8),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          x.$2,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 7.8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _SalesBars extends StatelessWidget {
  final List<DailySalesInsight> rows;
  final String Function(double) money;
  const _SalesBars({required this.rows, required this.money});
  @override
  Widget build(BuildContext context) {
    final data = rows.length > 14 ? rows.sublist(rows.length - 14) : rows;
    final maxValue = data.fold<double>(
      0,
      (max, x) => x.sales > max ? x.sales : max,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales Trend • Last 14 Days',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((x) {
                  final ratio = maxValue <= 0
                      ? 0.02
                      : (x.sales / maxValue).clamp(0.02, 1.0);
                  return Expanded(
                    child: Tooltip(
                      message:
                          '${x.date.toLocal().toString().split(' ').first} • ${money(x.sales)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          height: 140 * ratio,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
