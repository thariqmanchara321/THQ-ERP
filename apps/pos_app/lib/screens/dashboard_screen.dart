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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('Sales, cash flow, stock and customer performance'),
                  ],
                ),
              ),
              IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  FutureBuilder<DashboardData>(
                    future: _summary,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text(snapshot.error.toString());
                      }
                      final d = snapshot.data!;
                      return GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.75,
                        children: [
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
                          height: 300,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text(snapshot.error.toString());
                      }
                      final d = snapshot.data!;
                      return Column(
                        children: [
                          _SalesBars(rows: d.dailySales, money: _money),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _ListCard(
                                  title: 'Top Selling Products',
                                  rows: d.topProducts
                                      .map(
                                        (x) => (
                                          '${x.productName} • ${x.quantity.toStringAsFixed(0)} qty',
                                          _money(x.sales),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _ListCard(
                                  title: 'Top Customers',
                                  rows: d.topCustomers
                                      .map(
                                        (x) => (
                                          '${x.customerName} • ${x.invoiceCount} invoices',
                                          _money(x.sales),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
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

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      children: [
        CircleAvatar(child: Icon(icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ListCard extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _ListCard({required this.title, required this.rows});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const Text('No data yet.')
          else
            ...rows
                .take(10)
                .map(
                  (x) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(x.$1, overflow: TextOverflow.ellipsis),
                        ),
                        Text(
                          x.$2,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    ),
  );
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
