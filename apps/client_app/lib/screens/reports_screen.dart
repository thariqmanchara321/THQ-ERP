import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/report_summary.dart';
import '../services/report_service.dart';
import '../services/report_export_service.dart';
import '../services/location_scope_service.dart';
import 'purchases_screen.dart';
import 'sales_screen.dart';
import 'returns_register_screen.dart';
import 'reports_center_v500_screen.dart';

class ReportsScreen extends StatefulWidget {
  final ClientSession session;

  const ReportsScreen({super.key, required this.session});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final ReportService _service = ReportService();
  final ReportExportService _exportService = ReportExportService();
  bool _exporting = false;

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

  Future<void> _export(String format) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final locationId = LocationScopeService.currentForRead(widget.session);
    final location = LocationScopeService.selectedLocation(widget.session);
    final locationLabel = location == null
        ? 'All Stores'
        : '${location.code} • ${location.name}';
    try {
      if (format == 'xlsx') {
        await _exportService.saveExcel(
          tenantId: widget.session.business.id,
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationId: locationId,
          locationLabel: locationLabel,
        );
      } else if (format == 'pdf') {
        await _exportService.savePdf(
          tenantId: widget.session.business.id,
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationId: locationId,
          locationLabel: locationLabel,
        );
      } else {
        await _exportService.printReport(
          tenantId: widget.session.business.id,
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationId: locationId,
          locationLabel: locationLabel,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              format == 'print'
                  ? 'Print dialog opened.'
                  : '${format.toUpperCase()} report created.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openHistory({required bool sales}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(sales ? 'Sales History' : 'Purchase History'),
          ),
          body: sales
              ? SalesScreen(session: widget.session, historyOnly: true)
              : PurchasesScreen(session: widget.session, historyOnly: true),
        ),
      ),
    );
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
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 26,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reports',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Sales, purchase, tax, profit and stock summary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ReportsCenterV500Screen(session: widget.session),
                    ),
                  ),
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: const Text('Reports Center'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final controls = <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => _pick(true),
                    icon: const Icon(Icons.date_range, size: 15),
                    label: Text('From ${_date(_from)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(false),
                    icon: const Icon(Icons.event, size: 15),
                    label: Text('To ${_date(_to)}'),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openHistory(sales: true),
                    icon: const Icon(Icons.receipt_long_outlined, size: 15),
                    label: const Text('Sales'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openHistory(sales: false),
                    icon: const Icon(Icons.shopping_cart_outlined, size: 15),
                    label: const Text('Purchases'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ReturnsRegisterScreen(session: widget.session),
                      ),
                    ),
                    icon: const Icon(
                      Icons.assignment_return_outlined,
                      size: 15,
                    ),
                    label: const Text('Returns'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Print / Export',
                    enabled: !_exporting,
                    onSelected: _export,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'print', child: Text('Print')),
                      PopupMenuItem(value: 'pdf', child: Text('Save PDF')),
                      PopupMenuItem(value: 'xlsx', child: Text('Save Excel')),
                    ],
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_exporting)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(Icons.ios_share_outlined, size: 15),
                          const SizedBox(width: 5),
                          const Text(
                            'Export',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ];
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final control in controls) ...[
                        control,
                        const SizedBox(width: 5),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
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
                    'Net Sales',
                    _money(report.sales),
                    '${report.saleCount} invoices',
                  ),
                  _ReportCardData(
                    'Sales Returns',
                    _money(report.salesReturns),
                    'Returns in period',
                  ),
                  _ReportCardData(
                    'Sales Tax',
                    _money(report.salesTax),
                    'Output tax',
                  ),
                  _ReportCardData(
                    'Net Purchases',
                    _money(report.purchases),
                    '${report.purchaseCount} bills',
                  ),
                  _ReportCardData(
                    'Purchase Returns',
                    _money(report.purchaseReturns),
                    'Returns in period',
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
                    final columns = constraints.maxWidth >= 1100
                        ? 4
                        : constraints.maxWidth >= 760
                        ? 3
                        : 2;
                    const gap = 6.0;
                    final width =
                        (constraints.maxWidth - ((columns - 1) * gap)) /
                        columns;
                    return SingleChildScrollView(
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
    final icon = row.label.contains('Purchase')
        ? Icons.shopping_cart_outlined
        : row.label.contains('Tax')
        ? Icons.percent_outlined
        : row.label.contains('Profit')
        ? Icons.trending_up
        : row.label == 'Receivables'
        ? Icons.call_received
        : row.label == 'Payables'
        ? Icons.call_made
        : row.label == 'Stock Value'
        ? Icons.inventory_2_outlined
        : Icons.point_of_sale_outlined;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: scheme.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.8,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  row.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 7.8,
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

class _ReportCardData {
  final String label;
  final String value;
  final String caption;

  const _ReportCardData(this.label, this.value, this.caption);
}
