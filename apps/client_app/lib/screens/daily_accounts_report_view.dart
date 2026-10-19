import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:thq_ui/thq_ui.dart';

import '../features/audit_intelligence/audit_intelligence_service.dart';
import '../features/audit_intelligence/transaction_story_dialog.dart';
import '../models/client_session.dart';
import '../services/accounting_workspace_service.dart';
import '../services/daily_accounts_export_service.dart';
import '../services/location_scope_service.dart';
import 'purchase_detail_screen.dart';
import 'sale_detail_screen.dart';

class DailyDetailedAccountsView extends StatefulWidget {
  final ClientSession session;

  const DailyDetailedAccountsView({
    super.key,
    required this.session,
  });

  @override
  State<DailyDetailedAccountsView> createState() =>
      _DailyDetailedAccountsViewState();
}

class _DailyDetailedAccountsViewState extends State<DailyDetailedAccountsView> {
  final DateFormat _dateFmt = DateFormat('dd MMM yyyy');
  final DailyAccountsExportService _exportService = DailyAccountsExportService();

  late DateTime _from;
  late DateTime _to;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day);
    _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _fetch();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final effectiveLocation = LocationScopeService.currentForRead(widget.session);
      final service = AccountingWorkspaceService(
        widget.session.business.id,
        effectiveLocation,
      );
      final result = await service.dailyDetailedAccounts(
        from: _from,
        to: _to,
        locationId: effectiveLocation,
      );

      if (!mounted) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _m(num? value) {
    final v = value ?? 0;
    final cur = widget.session.currencyCode;
    return '$cur ${v.toStringAsFixed(2)}';
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;

    setState(() {
      if (isFrom) {
        _from = DateTime(picked.year, picked.month, picked.day);
        if (_from.isAfter(_to)) _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      } else {
        _to = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        if (_to.isBefore(_from)) _from = DateTime(picked.year, picked.month, picked.day);
      }
    });
    _fetch();
  }

  void _setDatePreset(String preset) {
    final now = DateTime.now();
    setState(() {
      if (preset == 'today') {
        _from = DateTime(now.year, now.month, now.day);
        _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else if (preset == 'yesterday') {
        final y = now.subtract(const Duration(days: 1));
        _from = DateTime(y.year, y.month, y.day);
        _to = DateTime(y.year, y.month, y.day, 23, 59, 59);
      } else if (preset == 'this_month') {
        _from = DateTime(now.year, now.month, 1);
        _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
      }
    });
    _fetch();
  }

  Future<void> _export(String format) async {
    if (_data == null || _exporting) return;
    setState(() => _exporting = true);

    try {
      final locLabel = LocationScopeService.scopeLabel(widget.session);
      if (format == 'xlsx') {
        await _exportService.saveExcel(
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationLabel: locLabel,
          data: _data!,
        );
      } else if (format == 'pdf') {
        await _exportService.savePdf(
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationLabel: locLabel,
          data: _data!,
        );
      } else if (format == 'print') {
        await _exportService.printReport(
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationLabel: locLabel,
          data: _data!,
        );
      }
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Exported Daily Accounts Report ($format).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openJournalStory(Map<String, dynamic> journal) {
    final jId = journal['journal_id'] ?? journal['id'];
    final sType = journal['source_type']?.toString();
    final sId = journal['source_id']?.toString();

    if (sType == 'sale' && sId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SaleDetailScreen(session: widget.session, saleId: sId)),
      );
      return;
    }
    if (sType == 'purchase' && sId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PurchaseDetailScreen(session: widget.session, purchaseId: sId)),
      );
      return;
    }

    if (jId != null) {
      showTransactionStoryDialog(
        context: context,
        service: AuditIntelligenceService(),
        tenantId: widget.session.business.id,
        entityType: 'journal_entry',
        entityId: jId.toString(),
        session: widget.session,
        locationId: LocationScopeService.currentForRead(widget.session),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Controls Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickDate(true),
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text('From: ${_dateFmt.format(_from)}'),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.event, size: 14),
                label: Text('To: ${_dateFmt.format(_to)}'),
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              ActionChip(
                label: const Text('Today', style: TextStyle(fontSize: 12)),
                onPressed: () => _setDatePreset('today'),
                visualDensity: VisualDensity.compact,
              ),
              ActionChip(
                label: const Text('Yesterday', style: TextStyle(fontSize: 12)),
                onPressed: () => _setDatePreset('yesterday'),
                visualDensity: VisualDensity.compact,
              ),
              ActionChip(
                label: const Text('This Month', style: TextStyle(fontSize: 12)),
                onPressed: () => _setDatePreset('this_month'),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _loading ? null : _fetch,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                enabled: _data != null && !_exporting,
                tooltip: 'Export report',
                onSelected: _export,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'xlsx', child: Text('Excel (.xlsx)')),
                  PopupMenuItem(value: 'pdf', child: Text('PDF Report')),
                  PopupMenuItem(value: 'print', child: Text('Print Report')),
                ],
                child: FilledButton.icon(
                  onPressed: null,
                  icon: _exporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download, size: 16),
                  label: const Text('Export'),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
        ),

        // Main Content Area
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: scheme.error),
                          const SizedBox(height: 12),
                          Text('Failed to load daily accounts: $_error'),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _fetch, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : _data == null
                      ? const Center(child: Text('No data loaded.'))
                      : _buildReportBody(scheme),
        ),
      ],
    );
  }

  Widget _buildReportBody(ColorScheme scheme) {
    final d = _data!;
    final cash = Map<String, dynamic>.from(d['cash'] as Map? ?? {});
    final bank = Map<String, dynamic>.from(d['bank'] as Map? ?? {});
    final sales = Map<String, dynamic>.from(d['sales'] as Map? ?? {});
    final purchases = Map<String, dynamic>.from(d['purchases'] as Map? ?? {});
    final receipts = Map<String, dynamic>.from(d['receipts'] as Map? ?? {});
    final payments = Map<String, dynamic>.from(d['payments'] as Map? ?? {});
    final receivables = Map<String, dynamic>.from(d['receivables'] as Map? ?? {});
    final payables = Map<String, dynamic>.from(d['payables'] as Map? ?? {});
    final returns = Map<String, dynamic>.from(d['returns'] as Map? ?? {});
    final journals = (d['day_journals'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final exceptions = (d['exceptions'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final status = d['reconciliation_status']?.toString() ?? 'Passed';
    final statement = d['closing_statement']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Closing Statement & Status
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: status == 'Passed'
                  ? scheme.primaryContainer.withValues(alpha: 0.3)
                  : scheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: status == 'Passed' ? scheme.primary : scheme.error,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  status == 'Passed' ? Icons.verified_outlined : Icons.warning_amber_rounded,
                  color: status == 'Passed' ? scheme.primary : scheme.error,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Daily Closing Statement',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: status == 'Passed' ? scheme.primary : scheme.error,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: status == 'Passed' ? scheme.primary : scheme.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statement,
                        style: TextStyle(fontSize: 12, color: scheme.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Cash & Bank Position Cards
          Row(
            children: [
              Expanded(
                child: _buildBalanceCard(
                  title: 'Cash Book Movement',
                  opening: cash['opening'] as num? ?? 0,
                  inflow: cash['received'] as num? ?? 0,
                  outflow: cash['paid'] as num? ?? 0,
                  closing: cash['closing'] as num? ?? 0,
                  scheme: scheme,
                  icon: Icons.payments_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBalanceCard(
                  title: 'Bank Accounts Movement',
                  opening: bank['opening'] as num? ?? 0,
                  inflow: bank['received'] as num? ?? 0,
                  outflow: bank['paid'] as num? ?? 0,
                  closing: bank['closing'] as num? ?? 0,
                  scheme: scheme,
                  icon: Icons.account_balance_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildArApCard(
                  title: 'Accounts Receivable (AR)',
                  opening: receivables['opening'] as num? ?? 0,
                  movement: receivables['net_movement'] as num? ?? 0,
                  closing: receivables['closing'] as num? ?? 0,
                  scheme: scheme,
                  icon: Icons.arrow_downward_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildArApCard(
                  title: 'Accounts Payable (AP)',
                  opening: payables['opening'] as num? ?? 0,
                  movement: payables['net_movement'] as num? ?? 0,
                  closing: payables['closing'] as num? ?? 0,
                  scheme: scheme,
                  icon: Icons.arrow_upward_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Operational Activity Breakdown
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Operational & Trading Activity',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.onSurface),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _metricChip('Total Invoiced Sales', _m(sales['total'] as num?), '${sales['count'] ?? 0} invoices', scheme),
                    _metricChip('Cash Sales', _m(sales['cash'] as num?), 'Paid on bill', scheme),
                    _metricChip('Credit Sales', _m(sales['credit'] as num?), 'Due / on account', scheme),
                    _metricChip('Sales GST', _m(sales['tax'] as num?), 'Tax component', scheme),
                    _metricChip('Total Purchases Billed', _m(purchases['total'] as num?), '${purchases['count'] ?? 0} bills', scheme),
                    _metricChip('Cash Purchases', _m(purchases['cash'] as num?), 'Paid on bill', scheme),
                    _metricChip('Credit Purchases', _m(purchases['credit'] as num?), 'Payable later', scheme),
                    _metricChip('Customer Receipts', _m(receipts['customer_receipts'] as num?), 'Collected on dues', scheme),
                    _metricChip('Supplier Payments', _m(payments['supplier_payments'] as num?), 'Settled bills', scheme),
                    _metricChip('Operating Expenses', _m(payments['operating_expenses'] as num?), 'Direct expenses', scheme),
                    _metricChip('Sales Returns', _m(returns['sales_total'] as num?), '${returns['sales_count'] ?? 0} returns', scheme),
                    _metricChip('Purchase Returns', _m(returns['purchase_total'] as num?), '${returns['purchase_count'] ?? 0} returns', scheme),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Exceptions section (if any)
          if (exceptions.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.error),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: scheme.error, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Financial Exceptions (${exceptions.length})',
                        style: TextStyle(fontWeight: FontWeight.bold, color: scheme.error, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final ex in exceptions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• [${ex['type']}] ${ex['reference']}: ${ex['note']}',
                        style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Day Journals Register Table
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Day Journals (${journals.length} entries)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const Spacer(),
                      const Text(
                        'Double-click or tap to drill down into transaction story',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (journals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No journal entries posted in this date range.')),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 34,
                      dataRowMinHeight: 32,
                      dataRowMaxHeight: 36,
                      columnSpacing: 18,
                      columns: const [
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Entry #')),
                        DataColumn(label: Text('Source Type')),
                        DataColumn(label: Text('Reference')),
                        DataColumn(label: Text('Description')),
                        DataColumn(label: Text('Debits', textAlign: TextAlign.right), numeric: true),
                        DataColumn(label: Text('Credits', textAlign: TextAlign.right), numeric: true),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: journals.map((j) {
                        final isBalanced = j['is_balanced'] == true;
                        return DataRow(
                          onSelectChanged: (_) => _openJournalStory(j),
                          cells: [
                            DataCell(Text(j['entry_date']?.toString() ?? '—', style: const TextStyle(fontSize: 11.5))),
                            DataCell(Text(j['entry_number']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5))),
                            DataCell(Text(j['source_type']?.toString() ?? '—', style: const TextStyle(fontSize: 11.5))),
                            DataCell(Text(j['reference']?.toString() ?? '—', style: const TextStyle(fontSize: 11.5))),
                            DataCell(Text(j['description']?.toString() ?? '—', style: const TextStyle(fontSize: 11.5))),
                            DataCell(Text(_m(j['debit_total'] as num?), style: const TextStyle(fontSize: 11.5))),
                            DataCell(Text(_m(j['credit_total'] as num?), style: const TextStyle(fontSize: 11.5))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isBalanced
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isBalanced ? 'Balanced' : 'Unbalanced',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isBalanced ? Colors.green.shade800 : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard({
    required String title,
    required num opening,
    required num inflow,
    required num outflow,
    required num closing,
    required ColorScheme scheme,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _cardRow('Opening:', _m(opening), scheme.onSurfaceVariant),
          _cardRow('Inflows:', '+${_m(inflow)}', Colors.green.shade700),
          _cardRow('Outflows:', '-${_m(outflow)}', Colors.red.shade700),
          const Divider(height: 10),
          _cardRow('Closing:', _m(closing), scheme.primary, isBold: true),
        ],
      ),
    );
  }

  Widget _buildArApCard({
    required String title,
    required num opening,
    required num movement,
    required num closing,
    required ColorScheme scheme,
    required IconData icon,
  }) {
    final isPos = movement >= 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _cardRow('Opening Balance:', _m(opening), scheme.onSurfaceVariant),
          _cardRow('Period Movement:', '${isPos ? '+' : ''}${_m(movement)}', isPos ? Colors.blue.shade700 : Colors.purple.shade700),
          const SizedBox(height: 16),
          const Divider(height: 10),
          _cardRow('Closing Balance:', _m(closing), scheme.secondary, isBold: true),
        ],
      ),
    );
  }

  Widget _cardRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value, String sub, ColorScheme scheme) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant), maxLines: 1),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text(sub, style: TextStyle(fontSize: 9.5, color: scheme.outline), maxLines: 1),
        ],
      ),
    );
  }
}
