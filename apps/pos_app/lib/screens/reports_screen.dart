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
                const Expanded(
                  child: Text(
                    'Reports',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.date_range, size: 14),
                  label: Text('From ${_date(_from)}'),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.date_range, size: 14),
                  label: Text('To ${_date(_to)}'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
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

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1050
                        ? 5
                        : constraints.maxWidth >= 780
                        ? 4
                        : constraints.maxWidth >= 560
                        ? 3
                        : 2;
                    const gap = 5.0;
                    final width =
                        (constraints.maxWidth - ((columns - 1) * gap)) /
                        columns;

                    return Align(
                      alignment: Alignment.topLeft,
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: rows
                            .map(
                              (row) => SizedBox(
                                width: width,
                                child: _reportMetric(row),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportMetric(_ReportCardData row) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            row.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
          Text(
            row.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 7, color: scheme.onSurfaceVariant),
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
