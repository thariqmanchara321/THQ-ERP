import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/expense.dart';
import '../services/expense_report_export_service.dart';
import '../services/expense_service.dart';
import '../services/location_scope_service.dart';

class AdvancedExpenseReportScreen extends StatefulWidget {
  final ClientSession session;

  const AdvancedExpenseReportScreen({super.key, required this.session});

  @override
  State<AdvancedExpenseReportScreen> createState() =>
      _AdvancedExpenseReportScreenState();
}

class _AdvancedExpenseReportScreenState
    extends State<AdvancedExpenseReportScreen> with SingleTickerProviderStateMixin {
  final ExpenseService _service = ExpenseService();
  final ExpenseReportExportService _exportService =
      ExpenseReportExportService();
  final TextEditingController _searchCtrl = TextEditingController();

  late TabController _tabController;
  late DateTime _from;
  late DateTime _to;

  String _preset = 'this_month';
  String? _selectedCategory;
  String? _selectedPaymentMethod;
  String? _selectedStatus;
  double? _minAmount;
  double? _maxAmount;

  String _sortColumn = 'date';
  bool _sortAsc = false;

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  Map<String, dynamic> _dataset = {};
  List<Map<String, dynamic>> _rawExpenses = [];
  List<Map<String, dynamic>> _yardCosts = [];
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _prevSummary = {};
  List<ExpenseCategory> _categories = [];

  final DateFormat _dateFormat = DateFormat('dd-MM-yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _applyPreset('this_month', reload: false);
    LocationScopeService.selectedLocationId.addListener(_onLocationChanged);
    _loadData();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_onLocationChanged);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    _loadData();
  }

  void _applyPreset(String preset, {bool reload = true}) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (preset) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        start = DateTime(y.year, y.month, y.day);
        end = DateTime(y.year, y.month, y.day, 23, 59, 59);
        break;
      case 'this_week':
        start = now.subtract(Duration(days: now.weekday - 1));
        start = DateTime(start.year, start.month, start.day);
        break;
      case 'this_month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'last_month':
        final prevMonth = DateTime(now.year, now.month - 1, 1);
        start = prevMonth;
        final lastDay = DateTime(now.year, now.month, 0);
        end = DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59);
        break;
      case 'ytd':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = _from;
        end = _to;
    }

    _preset = preset;
    _from = start;
    _to = end;

    if (reload) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final locId = LocationScopeService.selectedLocationId.value;
      final results = await Future.wait<dynamic>([
        _service.getAdvancedReportDataset(
          tenantId: widget.session.business.id,
          from: _from,
          to: _to,
          locationId: locId,
        ),
        _service.getCategories(tenantId: widget.session.business.id),
      ]);

      if (!mounted) return;

      final ds = results[0] is Map ? Map<String, dynamic>.from(results[0] as Map) : <String, dynamic>{};
      final cats = results[1] is List ? (results[1] as List<ExpenseCategory>) : <ExpenseCategory>[];

      setState(() {
        _dataset = ds;
        _categories = cats;
        _rawExpenses = (ds['expenses'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _yardCosts = (ds['yard_costs'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _summary = ds['summary'] is Map ? Map<String, dynamic>.from(ds['summary'] as Map) : {};
        _prevSummary = ds['previous_summary'] is Map ? Map<String, dynamic>.from(ds['previous_summary'] as Map) : {};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _m(num value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';
  }

  List<Map<String, dynamic>> _filteredExpenses() {
    final query = _searchCtrl.text.trim().toLowerCase();

    final filtered = _rawExpenses.where((e) {
      if (_selectedCategory != null && e['category_id'] != _selectedCategory) {
        return false;
      }
      if (_selectedPaymentMethod != null &&
          e['payment_method']?.toString().toLowerCase() !=
              _selectedPaymentMethod!.toLowerCase()) {
        return false;
      }
      if (_selectedStatus != null && _selectedStatus != 'all') {
        if (e['status']?.toString().toLowerCase() != _selectedStatus) {
          return false;
        }
      }
      final total = (e['total_amount'] as num? ?? 0).toDouble();
      if (_minAmount != null && total < _minAmount!) return false;
      if (_maxAmount != null && total > _maxAmount!) return false;

      if (query.isNotEmpty) {
        final expNum = e['expense_number']?.toString().toLowerCase() ?? '';
        final payee = e['payee']?.toString().toLowerCase() ?? '';
        final desc = e['description']?.toString().toLowerCase() ?? '';
        final cat = e['category_name']?.toString().toLowerCase() ?? '';
        final ref = e['reference_number']?.toString().toLowerCase() ?? '';
        if (!expNum.contains(query) &&
            !payee.contains(query) &&
            !desc.contains(query) &&
            !cat.contains(query) &&
            !ref.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'amount':
          final aVal = (a['total_amount'] as num? ?? 0).toDouble();
          final bVal = (b['total_amount'] as num? ?? 0).toDouble();
          cmp = aVal.compareTo(bVal);
          break;
        case 'category':
          cmp = (a['category_name']?.toString() ?? '')
              .compareTo(b['category_name']?.toString() ?? '');
          break;
        case 'payee':
          cmp = (a['payee']?.toString() ?? '')
              .compareTo(b['payee']?.toString() ?? '');
          break;
        case 'status':
          cmp = (a['status']?.toString() ?? '')
              .compareTo(b['status']?.toString() ?? '');
          break;
        case 'date':
        default:
          final aDate = a['expense_date']?.toString() ?? '';
          final bDate = b['expense_date']?.toString() ?? '';
          cmp = aDate.compareTo(bDate);
          break;
      }
      return _sortAsc ? cmp : -cmp;
    });

    return filtered;
  }

  List<Map<String, dynamic>> _buildCategoryAnalysis(
    List<Map<String, dynamic>> expenses,
  ) {
    return _exportService.buildCategoryAnalysis(
      expenses,
      prevSummary: _prevSummary,
    );
  }

  List<Map<String, dynamic>> _buildPaymentBreakdown(
    List<Map<String, dynamic>> expenses,
  ) {
    return _exportService.buildPaymentBreakdown(expenses);
  }

  List<Map<String, dynamic>> _buildDailyTrends(
    List<Map<String, dynamic>> expenses,
  ) {
    return _exportService.buildDailyTrends(expenses);
  }

  (String, List<Map<String, dynamic>>) _checkReconciliation(
    List<Map<String, dynamic>> expenses,
  ) {
    return _exportService.checkReconciliation(expenses);
  }

  Future<void> _customDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null && mounted) {
      setState(() {
        _preset = 'custom';
        _from = picked.start;
        _to = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
      _loadData();
    }
  }

  Future<void> _export(String format) async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final expenses = _filteredExpenses();
      final catAnalysis = _buildCategoryAnalysis(expenses);
      final paymentBreakdown = _buildPaymentBreakdown(expenses);
      final dailyTrends = _buildDailyTrends(expenses);
      final (reconStatus, reconExceptions) = _checkReconciliation(expenses);

      final loc = LocationScopeService.selectedLocation(widget.session);
      final locLabel =
          loc == null ? 'All Stores' : '${loc.code} • ${loc.name}';

      final enrichedSummary = {
        ..._summary,
        'average': expenses.isNotEmpty
            ? (expenses.map((e) => (e['total_amount'] as num? ?? 0).toDouble()).reduce((a, b) => a + b) / expenses.length)
            : 0.0,
        'largest': expenses.isNotEmpty
            ? expenses.map((e) => (e['total_amount'] as num? ?? 0).toDouble()).reduce((a, b) => a > b ? a : b)
            : 0.0,
      };

      if (format == 'xlsx') {
        await _exportService.saveExcel(
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationLabel: locLabel,
          summary: enrichedSummary,
          expenses: expenses,
          categoryAnalysis: catAnalysis,
          dailyTrends: dailyTrends,
          paymentBreakdown: paymentBreakdown,
          yardCosts: _yardCosts,
          reconciliationStatus: reconStatus,
          reconciliationExceptions: reconExceptions,
        );
        if (mounted) ThqNotify.success(context, 'Excel report exported');
      } else if (format == 'pdf') {
        await _exportService.savePdf(
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationLabel: locLabel,
          summary: enrichedSummary,
          expenses: expenses,
          categoryAnalysis: catAnalysis,
          paymentBreakdown: paymentBreakdown,
          reconciliationStatus: reconStatus,
        );
        if (mounted) ThqNotify.success(context, 'PDF report exported');
      } else if (format == 'print') {
        await _exportService.printPdf(
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          from: _from,
          to: _to,
          locationLabel: locLabel,
          summary: enrichedSummary,
          expenses: expenses,
          categoryAnalysis: catAnalysis,
          paymentBreakdown: paymentBreakdown,
          reconciliationStatus: reconStatus,
        );
      }
    } catch (e) {
      if (mounted) ThqNotify.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showExpenseDetail(Map<String, dynamic> expense) async {
    final expId = expense['expense_id']?.toString() ?? '';
    try {
      final detail = await _service.getExpenseDetail(
        tenantId: widget.session.business.id,
        expenseId: expId,
      );
      if (!mounted) return;
      final origin = detail['origin'] is Map ? Map<String, dynamic>.from(detail['origin'] as Map) : {};
      final journals = detail['journals'] is List ? (detail['journals'] as List) : [];
      final history = detail['history'] is List ? (detail['history'] as List) : [];

      await showThqDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 20),
              const SizedBox(width: 8),
              Text('Expense • ${expense['expense_number']}'),
            ],
          ),
          content: SizedBox(
            width: 700,
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense['category_name']?.toString() ?? 'Category',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '${expense['expense_date']} • Payee: ${expense['payee'] ?? '—'}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Text(
                      _m(expense['total_amount'] as num? ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Description: ${expense['description'] ?? '—'}'),
                      const SizedBox(height: 4),
                      Text('Payment: ${expense['payment_method']?.toString().toUpperCase()} • Reference: ${expense['reference_number'] ?? '—'}'),
                      const SizedBox(height: 4),
                      Text('Store: ${origin['location_name'] ?? expense['location_name'] ?? '—'} • Device: ${origin['device_name'] ?? expense['device_name'] ?? '—'}'),
                      if (expense['notes'] != null && expense['notes'].toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Notes: ${expense['notes']}'),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 24),
                const Text('Authoritative Accounting Journal Evidence', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (journals.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: const Text('No posted journal found for this expense.', style: TextStyle(color: Colors.brown)),
                  )
                else
                  ...journals.map((j) {
                    final jMap = Map<String, dynamic>.from(j as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.menu_book_outlined, color: Colors.indigo),
                      title: Text('${jMap['entry_number']} • Status: ${jMap['status']}'),
                      subtitle: Text('${jMap['entry_date']} • ${jMap['description']}'),
                    );
                  }),
                const Divider(height: 24),
                const Text('Audit & Modification History', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (history.isEmpty)
                  const Text('No prior revisions recorded.')
                else
                  ...history.map((h) {
                    final hMap = Map<String, dynamic>.from(h as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, size: 18),
                      title: Text('${hMap['action']} on ${hMap['changed_at']}'),
                      subtitle: Text('Reason: ${hMap['reason'] ?? 'None'}'),
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ThqNotify.error(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expenses = _filteredExpenses();
    final (reconStatus, reconExceptions) = _checkReconciliation(expenses);

    final totalAmount = expenses.fold<double>(
      0.0,
      (acc, e) => acc + (e['total_amount'] as num? ?? 0).toDouble(),
    );
    final totalNet = expenses.fold<double>(
      0.0,
      (acc, e) => acc + (e['amount'] as num? ?? 0).toDouble(),
    );
    final totalTax = expenses.fold<double>(
      0.0,
      (acc, e) => acc + (e['tax_amount'] as num? ?? 0).toDouble(),
    );
    final totalRound = expenses.fold<double>(
      0.0,
      (acc, e) => acc + (e['round_off'] as num? ?? 0).toDouble(),
    );
    final avgExpense = expenses.isNotEmpty ? totalAmount / expenses.length : 0.0;
    final largestExpense = expenses.isNotEmpty
        ? expenses.map((e) => (e['total_amount'] as num? ?? 0).toDouble()).reduce((a, b) => a > b ? a : b)
        : 0.0;

    final cashPaid = expenses
        .where((e) => (e['payment_method']?.toString().toLowerCase() ?? '') == 'cash')
        .fold<double>(0.0, (acc, e) => acc + (e['total_amount'] as num? ?? 0).toDouble());
    final bankPaid = expenses
        .where((e) => (e['payment_method']?.toString().toLowerCase() ?? '') == 'bank')
        .fold<double>(0.0, (acc, e) => acc + (e['total_amount'] as num? ?? 0).toDouble());
    final otherPaid = totalAmount - cashPaid - bankPaid;

    final prevTotal = (_prevSummary['total'] as num? ?? 0).toDouble();
    final variancePct = prevTotal > 0 ? ((totalAmount - prevTotal) / prevTotal) * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Advanced Expense Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${_dateFormat.format(_from)} to ${_dateFormat.format(_to)} • Reconciled: $reconStatus',
              style: TextStyle(
                fontSize: 11,
                color: reconStatus == 'Passed' ? Colors.green.shade700 : Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _exporting ? null : () => _export('xlsx'),
            icon: const Icon(Icons.table_view_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Export PDF',
            onPressed: _exporting ? null : () => _export('pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Print',
            onPressed: _exporting ? null : () => _export('print'),
            icon: const Icon(Icons.print_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Expense Register'),
            const Tab(text: 'Category Analysis'),
            const Tab(text: 'Daily Trends'),
            Tab(
              text: _dataset['yard_module_enabled'] == true
                  ? 'Material Yard Costs'
                  : 'Reconciliation',
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40, color: Colors.red),
                      const SizedBox(height: 8),
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadData, child: const Text('Retry')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Date Presets & Filter Row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                      ),
                      child: Row(
                        children: [
                          // Preset Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _presetChip('Today', 'today'),
                                _presetChip('Yesterday', 'yesterday'),
                                _presetChip('This Week', 'this_week'),
                                _presetChip('This Month', 'this_month'),
                                _presetChip('Last Month', 'last_month'),
                                _presetChip('YTD', 'ytd'),
                                const SizedBox(width: 4),
                                ActionChip(
                                  avatar: const Icon(Icons.calendar_today, size: 14),
                                  label: Text(
                                    _preset == 'custom'
                                        ? '${_dateFormat.format(_from)} - ${_dateFormat.format(_to)}'
                                        : 'Custom',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onPressed: _customDateRange,
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Search Box
                          SizedBox(
                            width: 220,
                            height: 34,
                            child: TextField(
                              controller: _searchCtrl,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: 'Search number, payee, notes...',
                                prefixIcon: const Icon(Icons.search, size: 16),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Category Filter Dropdown
                          DropdownButton<String?>(
                            value: _selectedCategory,
                            hint: const Text('All Categories', style: TextStyle(fontSize: 12)),
                            underline: const SizedBox(),
                            style: TextStyle(fontSize: 12, color: scheme.onSurface),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Categories')),
                              ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                            ],
                            onChanged: (v) => setState(() => _selectedCategory = v),
                          ),
                          const SizedBox(width: 8),
                          // Payment Method Filter
                          DropdownButton<String?>(
                            value: _selectedPaymentMethod,
                            hint: const Text('All Payments', style: TextStyle(fontSize: 12)),
                            underline: const SizedBox(),
                            style: TextStyle(fontSize: 12, color: scheme.onSurface),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('All Payments')),
                              DropdownMenuItem(value: 'cash', child: Text('Cash')),
                              DropdownMenuItem(value: 'bank', child: Text('Bank')),
                              DropdownMenuItem(value: 'upi', child: Text('UPI')),
                              DropdownMenuItem(value: 'card', child: Text('Card')),
                              DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                            ],
                            onChanged: (v) => setState(() => _selectedPaymentMethod = v),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String?>(
                            value: _selectedStatus,
                            hint: const Text('All Statuses', style: TextStyle(fontSize: 12)),
                            underline: const SizedBox(),
                            style: TextStyle(fontSize: 12, color: scheme.onSurface),
                            items: const [
                              DropdownMenuItem(value: null, child: Text('All Statuses')),
                              DropdownMenuItem(value: 'posted', child: Text('Posted')),
                              DropdownMenuItem(value: 'draft', child: Text('Draft')),
                              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                            ],
                            onChanged: (v) => setState(() => _selectedStatus = v),
                          ),
                        ],
                      ),
                    ),

                    // Top KPI Metric Cards (C3)
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      color: scheme.surfaceContainerHighest.withValues(alpha: .25),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _kpiCard('TOTAL POSTED', _m(totalAmount), Icons.account_balance_wallet_outlined, Colors.indigo),
                                _kpiCard('BEFORE TAX', _m(totalNet), Icons.receipt_outlined, Colors.blueGrey),
                                _kpiCard('EXPENSE TAX', _m(totalTax), Icons.account_balance_outlined, Colors.teal),
                                _kpiCard('ROUND OFF', _m(totalRound), Icons.toll_outlined, Colors.grey),
                                _kpiCard('COUNT', '${expenses.length}', Icons.format_list_numbered_rounded, Colors.deepPurple),
                                _kpiCard('AVERAGE', _m(avgExpense), Icons.analytics_outlined, Colors.blue),
                                _kpiCard('LARGEST', _m(largestExpense), Icons.arrow_upward_rounded, Colors.purple),
                                _kpiCard('CASH PAID', _m(cashPaid), Icons.payments_outlined, Colors.green),
                                _kpiCard('BANK PAID', _m(bankPaid), Icons.account_balance_outlined, Colors.cyan),
                                _kpiCard('OTHER PAID', _m(otherPaid), Icons.credit_card_outlined, Colors.orange),
                                _kpiCard(
                                  'VS PRIOR PERIOD',
                                  prevTotal > 0
                                      ? '${variancePct >= 0 ? '+' : ''}${variancePct.toStringAsFixed(1)}%'
                                      : 'N/A',
                                  Icons.compare_arrows_rounded,
                                  variancePct > 0 ? Colors.red : Colors.green,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Tab View
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Tab 1: Expense Register Table (C4)
                          _buildRegisterView(expenses, scheme),

                          // Tab 2: Category Analysis (C6)
                          _buildCategoryAnalysisView(expenses, scheme),

                          // Tab 3: Daily Trends (C7)
                          _buildDailyTrendsView(expenses, scheme),

                          // Tab 4: Material Yard or Reconciliation (C8 / C10)
                          _dataset['yard_module_enabled'] == true
                              ? _buildMaterialYardView(scheme)
                              : _buildReconciliationView(reconStatus, reconExceptions, scheme),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _presetChip(String label, String key) {
    final selected = _preset == key;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => _applyPreset(key),
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterView(
    List<Map<String, dynamic>> expenses,
    ColorScheme scheme,
  ) {
    if (expenses.isEmpty) {
      return const Center(child: Text('No expenses matching current filters.'));
    }

    return Column(
      children: [
        // Table Header
        Container(
          height: 36,
          color: scheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _headerCell('Date', 'date', 2),
              _headerCell('Expense No.', 'number', 2),
              _headerCell('Category', 'category', 3),
              _headerCell('Payee / Desc', 'payee', 4),
              _headerCell('Payment', 'payment', 2),
              _headerCell('Amount', 'amount', 2, align: TextAlign.right),
              _headerCell('Tax', 'tax', 2, align: TextAlign.right),
              _headerCell('Total', 'total', 2, align: TextAlign.right),
              _headerCell('Status', 'status', 2, align: TextAlign.center),
              const SizedBox(width: 40),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.builder(
            itemCount: expenses.length,
            itemBuilder: (context, idx) {
              final e = expenses[idx];
              final isEven = idx % 2 == 0;
              return InkWell(
                onTap: () => _showExpenseDetail(e),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: isEven ? Colors.transparent : scheme.surfaceContainerHighest.withValues(alpha: .2),
                  child: Row(
                    children: [
                      _rowCell(e['expense_date']?.toString() ?? '', 2),
                      _rowCell(e['expense_number']?.toString() ?? '', 2, isBold: true),
                      _rowCell(e['category_name']?.toString() ?? '', 3),
                      _rowCell(
                        e['payee']?.toString().isNotEmpty == true
                            ? '${e['payee']} • ${e['description']}'
                            : (e['description']?.toString() ?? ''),
                        4,
                      ),
                      _rowCell(e['payment_method']?.toString().toUpperCase() ?? '', 2),
                      _rowCell(_m(e['amount'] as num? ?? 0), 2, align: TextAlign.right),
                      _rowCell(_m(e['tax_amount'] as num? ?? 0), 2, align: TextAlign.right),
                      _rowCell(_m(e['total_amount'] as num? ?? 0), 2, isBold: true, align: TextAlign.right),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: e['status'] == 'posted'
                                  ? Colors.green.shade50
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              e['status']?.toString().toUpperCase() ?? '',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: e['status'] == 'posted'
                                    ? Colors.green.shade800
                                    : Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(Icons.info_outline, size: 16),
                          onPressed: () => _showExpenseDetail(e),
                          tooltip: 'Tracking & Journals',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String label, String col, int flex, {TextAlign align = TextAlign.left}) {
    final isSelected = _sortColumn == col;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_sortColumn == col) {
              _sortAsc = !_sortAsc;
            } else {
              _sortColumn = col;
              _sortAsc = false;
            }
          });
        },
        child: Row(
          mainAxisAlignment: align == TextAlign.right
              ? MainAxisAlignment.end
              : align == TextAlign.center
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            if (isSelected)
              Icon(
                _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
              ),
          ],
        ),
      ),
    );
  }

  Widget _rowCell(String text, int flex, {bool isBold = false, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildCategoryAnalysisView(
    List<Map<String, dynamic>> expenses,
    ColorScheme scheme,
  ) {
    final catAnalysis = _buildCategoryAnalysis(expenses);
    if (catAnalysis.isEmpty) {
      return const Center(child: Text('No categories recorded in this period.'));
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Category Breakdown & Expenditure Analysis',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Text(
                'Tap category to filter expense register',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: catAnalysis.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final c = catAnalysis[idx];
                final pct = (c['percentage'] as num? ?? 0).toDouble();
                return ListTile(
                  dense: true,
                  onTap: () {
                    setState(() {
                      _selectedCategory = c['category_id']?.toString();
                      _tabController.animateTo(0);
                    });
                  },
                  title: Row(
                    children: [
                      Text(
                        c['category_name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${c['expense_count']} txns',
                          style: TextStyle(fontSize: 10, color: scheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _m(c['total'] as num? ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        '${pct.toStringAsFixed(1)}% of total • Avg ${_m(c['average'] as num? ?? 0)}',
                        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTrendsView(
    List<Map<String, dynamic>> expenses,
    ColorScheme scheme,
  ) {
    final daily = _buildDailyTrends(expenses);
    if (daily.isEmpty) {
      return const Center(child: Text('No daily activity to graph.'));
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Expenditure Timeline',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: daily.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final d = daily[idx];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.event, size: 20),
                  title: Text(
                    d['date']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${d['count']} transactions • Tax: ${_m(d['tax'] as num? ?? 0)}',
                  ),
                  trailing: Text(
                    _m(d['total'] as num? ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialYardView(ColorScheme scheme) {
    if (_yardCosts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No load-level yard costs (diesel, wages, rent, freight) recorded in this period.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.brown, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Material Yard Operating Costs: Direct load costs (Diesel, Driver wages, Freight, Loading) '
                    'are distinguished from inventory purchases and invoice line charges to prevent double-counting.',
                    style: TextStyle(fontSize: 11.5, color: Colors.brown.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: _yardCosts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final y = _yardCosts[idx];
                return ListTile(
                  dense: true,
                  title: Row(
                    children: [
                      Text(
                        'Load ${y['load_number']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          y['cost_kind']?.toString().replaceAll('_', ' ').toUpperCase() ?? '',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${y['load_date']} • Truck: ${y['truck_number'] ?? '—'} • Driver: ${y['driver_name'] ?? '—'} • Payee: ${y['payee']}',
                  ),
                  trailing: Text(
                    _m(y['amount'] as num? ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReconciliationView(
    String status,
    List<Map<String, dynamic>> exceptions,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == 'Passed' ? Icons.check_circle : Icons.warning_amber_rounded,
                color: status == 'Passed' ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reconciliation Status: $status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: status == 'Passed' ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                  Text(
                    status == 'Passed'
                        ? 'Every posted expense in this period has a matching, balanced financial journal.'
                        : '${exceptions.length} discrepancy(ies) detected between source expenses and journals.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (exceptions.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified, color: Colors.green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'All source transactions, tax accounts, and payment credits reconcile 100% with the general ledger.',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const Text(
              'Discrepancy Exceptions',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: exceptions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final ex = exceptions[idx];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(
                      'Expense ${ex['expense_number']} • ${ex['expense_date']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(ex['note']?.toString() ?? ''),
                    trailing: Text(
                      _m(ex['amount'] as num? ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
