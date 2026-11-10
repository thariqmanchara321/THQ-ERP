import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import '../../widgets/mobile_workspace_widgets.dart';

class MobileExpenseReportPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileExpenseReportPage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileExpenseReportPage> createState() =>
      _MobileExpenseReportPageState();
}

class _MobileExpenseReportPageState extends State<MobileExpenseReportPage> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'This Month';
  late Future<Map<String, dynamic>> _reportFuture;

  final _searchCtrl = TextEditingController();
  String? _selectedCategory;
  String? _selectedPaymentMethod;
  double? _minAmount;
  double? _maxAmount;
  int _activeTabIndex = 0; // 0: Register, 1: Categories, 2: Trends

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _load() {
    _reportFuture = widget.service.advancedExpenseReport(
      widget.session,
      from: _from,
      to: _to,
      locationId: widget.locationId,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _reportFuture;
  }

  void _setPreset(String preset) {
    final now = DateTime.now();
    DateTime f;
    DateTime t = now;

    switch (preset) {
      case 'Today':
        f = DateTime(now.year, now.month, now.day);
        t = now;
        break;
      case 'Yesterday':
        f = DateTime(now.year, now.month, now.day - 1);
        t = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
        break;
      case 'This Week':
        f = now.subtract(Duration(days: now.weekday - 1));
        f = DateTime(f.year, f.month, f.day);
        t = now;
        break;
      case 'This Month':
        f = DateTime(now.year, now.month, 1);
        t = now;
        break;
      case 'Last Month':
        f = DateTime(now.year, now.month - 1, 1);
        t = DateTime(now.year, now.month, 0, 23, 59, 59);
        break;
      case 'Year to Date':
        f = DateTime(now.year, 1, 1);
        t = now;
        break;
      default:
        return;
    }

    setState(() {
      _datePreset = preset;
      _from = f;
      _to = t;
      _load();
    });
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _datePreset = 'Custom';
        _from = picked.start;
        _to = picked.end;
        _load();
      });
    }
  }

  String _m(num? v) => workspaceMoney(widget.session, v ?? 0);
  String _d(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  void _openFilterSheet(List<Map<String, dynamic>> categories) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filter Expenses',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedCategory = null;
                        _selectedPaymentMethod = null;
                        _minAmount = null;
                        _maxAmount = null;
                        _searchCtrl.clear();
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Reset All'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Categories')),
                  ...categories.map(
                    (c) => DropdownMenuItem(
                      value: c['name']?.toString(),
                      child: Text(c['name']?.toString() ?? ''),
                    ),
                  ),
                ],
                onChanged: (v) => setSheetState(() => _selectedCategory = v),
              ),
              const SizedBox(height: 12),
              const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _selectedPaymentMethod,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All Payment Methods')),
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setSheetState(() => _selectedPaymentMethod = v),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text('Apply Filters'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareReportSummary(Map<String, dynamic> summary, Map<String, dynamic> reconciliation) {
    final buf = StringBuffer();
    buf.writeln('📊 THQ ERP • Advanced Expense Report');
    buf.writeln('Store: ${widget.session.businessName}');
    buf.writeln('Period: ${_d(_from)} to ${_d(_to)}');
    buf.writeln('----------------------------------');
    buf.writeln('Total Expenses: ${_m(summary['total'] as num?)}');
    buf.writeln('Net Before Tax: ${_m(summary['net_before_tax'] as num?)}');
    buf.writeln('Tax: ${_m(summary['tax'] as num?)}');
    buf.writeln('Count: ${summary['expense_count'] ?? 0} entries');
    buf.writeln('Cash Paid: ${_m(summary['cash_total'] as num?)}');
    buf.writeln('Bank Paid: ${_m(summary['bank_total'] as num?)}');
    buf.writeln('Other Paid: ${_m(summary['other_total'] as num?)}');
    buf.writeln('----------------------------------');
    buf.writeln('Reconciliation: ${reconciliation['status'] ?? 'Passed'}');
    buf.writeln('Generated: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}');

    Clipboard.setData(ClipboardData(text: buf.toString()));
    ThqNotify.success(context, 'Report summary copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Analysis'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const WorkspaceLoadingList();
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load expense report',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: scheme.error,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data ?? <String, dynamic>{};
          final summary = data['summary'] is Map
              ? Map<String, dynamic>.from(data['summary'] as Map)
              : <String, dynamic>{};
          final allExpenses = (data['expenses'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          final categoryAnalysis = (data['category_analysis'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          final dailyTrends = (data['daily_trends'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          final reconciliation = data['reconciliation'] is Map
              ? Map<String, dynamic>.from(data['reconciliation'] as Map)
              : {'status': 'Passed'};

          // Filter expenses client side
          final filteredExpenses = allExpenses.where((row) {
            final cat = (row['category_name'] ?? '').toString();
            final method = (row['payment_method'] ?? '').toString().toLowerCase();
            final payee = (row['payee'] ?? '').toString().toLowerCase();
            final desc = (row['description'] ?? '').toString().toLowerCase();
            final expNum = (row['expense_number'] ?? row['number'] ?? '').toString().toLowerCase();
            final amount = (row['total_amount'] as num?)?.toDouble() ?? 0.0;

            if (_selectedCategory != null && cat != _selectedCategory) {
              return false;
            }
            if (_selectedPaymentMethod != null && method != _selectedPaymentMethod) {
              return false;
            }
            if (_minAmount != null && amount < _minAmount!) {
              return false;
            }
            if (_maxAmount != null && amount > _maxAmount!) {
              return false;
            }
            final q = _searchCtrl.text.trim().toLowerCase();
            if (q.isNotEmpty) {
              final match = cat.toLowerCase().contains(q) ||
                  payee.contains(q) ||
                  desc.contains(q) ||
                  expNum.contains(q);
              if (!match) return false;
            }
            return true;
          }).toList();

          return Column(
            children: [
              // Date Preset selector
              Container(
                color: scheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...['Today', 'Yesterday', 'This Week', 'This Month', 'Last Month', 'Year to Date'].map(
                        (preset) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            selected: _datePreset == preset,
                            label: Text(preset, style: const TextStyle(fontSize: 12)),
                            onSelected: (_) => _setPreset(preset),
                          ),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.date_range, size: 16),
                        label: Text(
                          _datePreset == 'Custom'
                              ? '${_d(_from)} - ${_d(_to)}'
                              : 'Custom Range',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: _pickCustomRange,
                      ),
                    ],
                  ),
                ),
              ),

              // KPI Header Cards
              Container(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL EXPENSES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _m(summary['total'] as num?),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: reconciliation['status'] == 'Passed'
                                    ? Colors.green.withAlpha(40)
                                    : Colors.orange.withAlpha(40),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: reconciliation['status'] == 'Passed'
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    reconciliation['status'] == 'Passed'
                                        ? Icons.check_circle_outline
                                        : Icons.warning_amber_rounded,
                                    size: 14,
                                    color: reconciliation['status'] == 'Passed'
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    reconciliation['status']?.toString() ?? 'Passed',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: reconciliation['status'] == 'Passed'
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Share summary',
                              icon: const Icon(Icons.share_outlined, size: 20),
                              onPressed: () => _shareReportSummary(summary, reconciliation),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _metricItem('Before Tax', _m(summary['net_before_tax'] as num?)),
                        _metricItem('Tax', _m(summary['tax'] as num?)),
                        _metricItem('Entries', '${summary['expense_count'] ?? 0}'),
                        _metricItem('Cash', _m(summary['cash_total'] as num?)),
                        _metricItem('Bank', _m(summary['bank_total'] as num?)),
                      ],
                    ),
                  ],
                ),
              ),

              // Search & Filter Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search payee, category, number...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Badge(
                      isLabelVisible: _selectedCategory != null || _selectedPaymentMethod != null,
                      child: IconButton.outlined(
                        tooltip: 'Filter',
                        icon: const Icon(Icons.filter_list_rounded),
                        onPressed: () => _openFilterSheet(categoryAnalysis),
                      ),
                    ),
                  ],
                ),
              ),

              // Tabs
              TabBar(
                tabs: [
                  Tab(text: 'Register (${filteredExpenses.length})'),
                  Tab(text: 'Categories (${categoryAnalysis.length})'),
                  Tab(text: 'Daily Trends (${dailyTrends.length})'),
                ],
                onTap: (i) => setState(() => _activeTabIndex = i),
              ),

              // Tab Body
              Expanded(
                child: _activeTabIndex == 0
                    ? _buildExpensesList(filteredExpenses, scheme)
                    : _activeTabIndex == 1
                        ? _buildCategoryList(categoryAnalysis, summary['total'] as num?, scheme)
                        : _buildTrendsList(dailyTrends, scheme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metricItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildExpensesList(List<Map<String, dynamic>> items, ColorScheme scheme) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined, size: 40, color: scheme.outline),
              const SizedBox(height: 8),
              const Text('No expenses match the selected criteria.'),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = items[index];
        final expNum = (row['expense_number'] ?? row['number'] ?? 'EXP').toString();
        final cat = (row['category_name'] ?? 'Uncategorized').toString();
        final payee = (row['payee'] ?? '').toString();
        final desc = (row['description'] ?? '').toString();
        final method = (row['payment_method'] ?? 'cash').toString().toUpperCase();
        final amount = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
        final tax = (row['tax_amount'] as num?)?.toDouble() ?? 0.0;
        final dateStr = row['expense_date']?.toString() ?? '';
        final origin = row['origin'] is Map ? row['origin'] as Map : null;
        final store = origin?['location_name'] ?? row['location_name'] ?? '—';
        final journals = row['journals'] is List ? row['journals'] as List : const [];

        return ExpansionTile(
          dense: true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: scheme.surfaceContainerHighest,
            child: Icon(
              method.contains('BANK') || method.contains('CARD')
                  ? Icons.account_balance
                  : method.contains('UPI')
                      ? Icons.qr_code
                      : Icons.payments_outlined,
              size: 18,
              color: scheme.primary,
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  cat,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _m(amount),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          subtitle: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  payee.isNotEmpty ? payee : desc,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                dateStr,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Number', expNum),
                  _detailRow('Description', desc.isEmpty ? '—' : desc),
                  _detailRow('Payee', payee.isEmpty ? '—' : payee),
                  _detailRow('Payment', method),
                  _detailRow('Tax', _m(tax)),
                  _detailRow('Store', store.toString()),
                  if (journals.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Journal Entries (${journals.length})',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    ...journals.map((j) {
                      final jm = Map<String, dynamic>.from(j as Map);
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '• ${jm['entry_number'] ?? 'JRN'} - ${jm['description'] ?? ''}',
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildCategoryList(List<Map<String, dynamic>> items, num? totalExpenses, ColorScheme scheme) {
    if (items.isEmpty) {
      return const Center(child: Text('No category breakdown available.'));
    }

    final total = totalExpenses?.toDouble() ?? 1.0;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final c = items[index];
        final name = (c['name'] ?? 'Category').toString();
        final count = (c['expense_count'] as num?)?.toInt() ?? 0;
        final amount = (c['total_amount'] as num?)?.toDouble() ?? 0.0;
        final pct = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;

        return Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      _m(amount),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$count transactions',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                    Text(
                      '${(pct * 100).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrendsList(List<Map<String, dynamic>> items, ColorScheme scheme) {
    if (items.isEmpty) {
      return const Center(child: Text('No daily trend data available for this range.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final t = items[index];
        final date = (t['expense_date'] ?? '').toString();
        final count = (t['expense_count'] as num?)?.toInt() ?? 0;
        final amount = (t['total_amount'] as num?)?.toDouble() ?? 0.0;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          title: Text(date, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          subtitle: Text('$count expenses', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          trailing: Text(
            _m(amount),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        );
      },
    );
  }
}
