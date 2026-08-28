import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/report_summary.dart';
import '../services/report_service.dart';

class ReportsScreen extends StatefulWidget {
  final ClientSession session;

  const ReportsScreen({super.key, required this.session});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ReportService _service = ReportService();

  late DateTime _from;
  late DateTime _to;
  late Future<ReportSummary> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  void _load() {
    _future = _service.summary(
      tenantId: widget.session.business.id,
      from: _from,
      to: _to,
    );
  }

  void _reload() => setState(_load);

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';
  }

  String _date(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-${value.year}';
  }

  Future<void> _pick(bool isFrom) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (selected == null) return;

    setState(() {
      if (isFrom) {
        _from = selected;
      } else {
        _to = selected;
      }
      if (_from.isAfter(_to)) {
        final temp = _from;
        _from = _to;
        _to = temp;
      }
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reports',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text('Sales, purchase, tax, profit and stock summary'),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pick(true),
                icon: const Icon(Icons.date_range),
                label: Text('From ${_date(_from)}'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pick(false),
                icon: const Icon(Icons.date_range),
                label: Text('To ${_date(_to)}'),
              ),
              FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: FutureBuilder<ReportSummary>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final report = snapshot.data!;
                final rows = <_ReportCardData>[
                  _ReportCardData(
                    'Sales',
                    _money(report.sales),
                    '${report.saleCount} invoices',
                  ),
                  _ReportCardData(
                    'Sales Tax',
                    _money(report.salesTax),
                    'Output tax',
                  ),
                  _ReportCardData(
                    'Purchases',
                    _money(report.purchases),
                    '${report.purchaseCount} bills',
                  ),
                  _ReportCardData(
                    'Purchase Tax',
                    _money(report.purchaseTax),
                    'Input tax',
                  ),
                  _ReportCardData(
                    'Expenses',
                    _money(report.expenses),
                    '${report.expenseCount} expenses',
                  ),
                  _ReportCardData(
                    'Gross Profit',
                    _money(report.grossProfit),
                    'Before expenses',
                  ),
                  _ReportCardData(
                    'Net Profit',
                    _money(report.netProfit),
                    'Gross profit - expenses',
                  ),
                  _ReportCardData(
                    'Receivables',
                    _money(report.receivables),
                    'Customer balance',
                  ),
                  _ReportCardData(
                    'Payables',
                    _money(report.payables),
                    'Supplier balance',
                  ),
                  _ReportCardData(
                    'Stock Value',
                    _money(report.stockValue),
                    'Current cost value',
                  ),
                ];

                return GridView.extent(
                  maxCrossAxisExtent: 340,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.0,
                  children: rows
                      .map(
                        (row) => Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                row.label,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                row.value,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                row.caption,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCardData {
  final String label;
  final String value;
  final String caption;

  const _ReportCardData(this.label, this.value, this.caption);
}
