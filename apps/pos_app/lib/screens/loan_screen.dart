import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/supplier.dart';
import '../services/customer_service.dart';
import '../services/loan_service.dart';
import '../services/location_scope_service.dart';
import '../services/supplier_service.dart';

class LoanScreen extends StatefulWidget {
  final ClientSession session;
  final String? initialLoanId;

  const LoanScreen({super.key, required this.session, this.initialLoanId});

  @override
  State<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends State<LoanScreen> {
  final LoanService _service = LoanService();
  final CustomerService _customersService = CustomerService();
  final SupplierService _suppliersService = SupplierService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  String? _warning;
  String _status = 'all';
  String _direction = 'all';
  Map<String, dynamic> _dashboard = const {};
  List<Map<String, dynamic>> _loans = const [];
  List<Map<String, dynamic>> _warnings = const [];
  List<Customer> _customers = const [];
  List<Supplier> _suppliers = const [];
  bool _loanAccountingEnabled = true;
  bool _openedInitialLoan = false;

  bool get _owner => widget.session.hasRole('owner');
  bool get _canCreate => _owner || widget.session.hasPermission('loans.create');
  bool get _canApprove =>
      _owner || widget.session.hasPermission('loans.approve');
  bool get _canDisburse =>
      _owner || widget.session.hasPermission('loans.disburse');
  bool get _canCollect =>
      _owner || widget.session.hasPermission('loans.collect');
  bool get _canRate =>
      _owner || widget.session.hasPermission('loans.rate_manage');
  bool get _canManage => _owner || widget.session.hasPermission('loans.manage');
  String get _currency => widget.session.currencyCode;

  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_locationChanged);
    _load();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_locationChanged);
    _search.dispose();
    super.dispose();
  }

  void _locationChanged() {
    if (mounted) _load();
  }

  double _n(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _money(dynamic value) => '$_currency ${_n(value).toStringAsFixed(2)}';

  String _date(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.day.toString().padLeft(2, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.year}';
  }

  String _dateValue(DateTime value) => value.toIso8601String().split('T').first;

  String _label(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((e) => e.isNotEmpty)
      .map((e) => '${e[0].toUpperCase()}${e.substring(1)}')
      .join(' ');

  Future<T> _safe<T>(
    Future<T> future,
    T fallback,
    List<String> warnings,
    String label,
  ) async {
    try {
      return await future;
    } catch (error) {
      warnings.add('$label temporarily unavailable');
      return fallback;
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _warning = null;
      });
    }
    final issues = <String>[];
    try {
      final results = await Future.wait<dynamic>([
        _safe<Map<String, dynamic>>(
          _service.dashboard(widget.session),
          <String, dynamic>{},
          issues,
          'Dashboard',
        ),
        _safe<List<Map<String, dynamic>>>(
          _service.list(
            widget.session,
            status: _status == 'all' ? null : _status,
            direction: _direction == 'all' ? null : _direction,
            query: _search.text.trim(),
          ),
          <Map<String, dynamic>>[],
          issues,
          'Loans',
        ),
        _safe<List<Map<String, dynamic>>>(
          _service.warnings(widget.session),
          <Map<String, dynamic>>[],
          issues,
          'Warnings',
        ),
        _safe<List<Customer>>(
          _customersService.getCustomers(tenantId: widget.session.business.id),
          <Customer>[],
          issues,
          'Clients',
        ),
        _safe<List<Supplier>>(
          _suppliersService.getSuppliers(tenantId: widget.session.business.id),
          <Supplier>[],
          issues,
          'Suppliers',
        ),
        _safe<Map<String, dynamic>>(
          _service.settings(widget.session),
          <String, dynamic>{'reflect_in_accounting': true},
          issues,
          'Loan settings',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = Map<String, dynamic>.from(results[0] as Map);
        _loans = List<Map<String, dynamic>>.from(results[1] as List);
        _warnings = List<Map<String, dynamic>>.from(results[2] as List);
        _customers = List<Customer>.from(results[3] as List)
          ..removeWhere((c) => !c.isActive || c.isWalkIn)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _suppliers = List<Supplier>.from(results[4] as List)
          ..removeWhere((x) => !x.isActive)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _loanAccountingEnabled =
            (results[5] as Map)['reflect_in_accounting'] != false;
        _warning = issues.isEmpty
            ? null
            : 'Some loan information is temporarily unavailable. ${issues.join(' • ')}. Refresh after the backend update.';
        _loading = false;
      });
      final initialLoanId = widget.initialLoanId;
      if (!_openedInitialLoan &&
          initialLoanId != null &&
          initialLoanId.isNotEmpty) {
        _openedInitialLoan = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showDetail(initialLoanId);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _run(String success, Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Color _statusColor(String status) => switch (status) {
    'active' => Colors.green,
    'approved' => Colors.teal,
    'submitted' => Colors.blue,
    'defaulted' => Colors.red,
    'closed' => Colors.grey,
    'cancelled' || 'rejected' => Colors.deepOrange,
    _ => Colors.amber.shade800,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 32),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
                        'Loans & Credit',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Given & taken | schedules | repayments',
                        style: TextStyle(
                          fontSize: 8.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _loanAccountingEnabled
                      ? 'Loan accounting enabled'
                      : 'Loan accounting disabled',
                  visualDensity: VisualDensity.compact,
                  onPressed: _canManage ? _loanSettings : null,
                  icon: Icon(
                    _loanAccountingEnabled
                        ? Icons.account_balance_outlined
                        : Icons.money_off_outlined,
                    size: 17,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
                if (_canCreate) ...[
                  const SizedBox(width: 3),
                  FilledButton.icon(
                    onPressed: () => _editLoan(),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('New Loan'),
                  ),
                ],
              ],
            ),
          ),
          if (_warning != null) ...[
            const SizedBox(height: 5),
            _banner(_warning!, Colors.orange, Icons.warning_amber_outlined),
          ],
          const SizedBox(height: 5),
          _metrics(),
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 116),
              child: _warningPanel(),
            ),
          ],
          const SizedBox(height: 5),
          _filters(),
          const SizedBox(height: 5),
          Expanded(
            child: _loans.isEmpty
                ? const Center(child: Text('No loans found for this scope.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: _loans.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 5),
                      itemBuilder: (_, index) => _loanCard(_loans[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Row(
    children: [
      const Icon(Icons.account_balance_outlined, size: 22),
      const SizedBox(width: 10),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Loans & Credit',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              'Given & taken loans • schedules • repayments',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Loan settings',
        onPressed: _canManage ? _loanSettings : null,
        icon: Icon(
          _loanAccountingEnabled
              ? Icons.account_balance_outlined
              : Icons.money_off_outlined,
        ),
      ),
      IconButton(
        tooltip: 'Refresh',
        onPressed: _load,
        icon: const Icon(Icons.refresh),
      ),
      if (_canCreate) ...[
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => _editLoan(),
          icon: const Icon(Icons.add),
          label: const Text('New Loan'),
        ),
      ],
    ],
  );

  Widget _metrics() {
    final items = <(String, String, IconData)>[
      (
        'Given Principal',
        _money(_dashboard['given_active_principal']),
        Icons.arrow_outward,
      ),
      (
        'Taken Principal',
        _money(_dashboard['taken_active_principal']),
        Icons.arrow_downward,
      ),
      ('To Receive', _money(_dashboard['receivable']), Icons.call_received),
      ('To Pay', _money(_dashboard['payable']), Icons.call_made),
      (
        'Active / Defaulted',
        '${_dashboard['active'] ?? 0} / ${_dashboard['defaulted'] ?? 0}',
        Icons.fact_check_outlined,
      ),
      (
        'Accounts',
        _loanAccountingEnabled ? 'ON' : 'OFF',
        _loanAccountingEnabled ? Icons.account_balance : Icons.money_off,
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (item) => SizedBox(
              width: 178,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(item.$3),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.$2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _warningPanel() => Card(
    margin: EdgeInsets.zero,
    child: ExpansionTile(
      initiallyExpanded: _warnings.any((w) => w['severity'] == 'danger'),
      leading: const Icon(Icons.notifications_active_outlined),
      title: Text(
        'Loan Warnings (${_warnings.length})',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${_dashboard['overdue_loans'] ?? 0} overdue loan(s) • ${_dashboard['maturing_next_30_days'] ?? 0} maturing within 30 days',
      ),
      children: _warnings.take(12).map((warning) {
        final severity = warning['severity']?.toString() ?? 'info';
        final color = severity == 'danger'
            ? Colors.red
            : severity == 'warning'
            ? Colors.orange
            : Colors.blue;
        return ListTile(
          dense: true,
          leading: Icon(Icons.circle, size: 12, color: color),
          title: Text(
            '${warning['loan_number'] ?? ''} • ${warning['client_name'] ?? ''}',
          ),
          subtitle: Text(
            warning['message']?.toString() ??
                _label(warning['warning_type']?.toString() ?? 'warning'),
          ),
          trailing: warning['amount'] == null
              ? Text(_date(warning['event_date']))
              : Text(_money(warning['amount'])),
          onTap: () {
            final id = warning['loan_id']?.toString();
            if (id != null && id.isNotEmpty) _showDetail(id);
          },
        );
      }).toList(),
    ),
  );

  Widget _filters() => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Search loan ID, client, reference or purpose',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search),
              onPressed: _load,
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) => _load(),
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 150,
        child: DropdownButtonFormField<String>(
          initialValue: _direction,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Direction',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Loans')),
            DropdownMenuItem(value: 'given', child: Text('Given')),
            DropdownMenuItem(value: 'taken', child: Text('Taken')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _direction = value);
            _load();
          },
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 160,
        child: DropdownButtonFormField<String>(
          initialValue: _status,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Status',
            border: OutlineInputBorder(),
          ),
          items:
              const [
                    'all',
                    'draft',
                    'submitted',
                    'approved',
                    'active',
                    'defaulted',
                    'closed',
                    'rejected',
                    'cancelled',
                  ]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        value == 'all'
                            ? 'All Statuses'
                            : value.replaceAll('_', ' ').toUpperCase(),
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _status = value);
            _load();
          },
        ),
      ),
    ],
  );

  Widget _loanCard(Map<String, dynamic> loan) {
    final status = loan['status']?.toString() ?? 'draft';
    final warning = loan['warning_message']?.toString();
    final warningLevel = loan['warning_level']?.toString() ?? 'normal';
    final variable = loan['rate_type']?.toString() == 'variable';
    final direction = loan['direction']?.toString() ?? 'given';
    final given = direction == 'given';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${loan['loan_number'] ?? 'Loan'} • ${loan['client_name'] ?? 'Party'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _statusColor(status).withValues(alpha: .35),
                    ),
                  ),
                  child: Text(
                    _label(status),
                    style: TextStyle(
                      color: _statusColor(status),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${given ? 'Given to' : 'Taken from'} • ${loan['client_name'] ?? 'Party'} • ${loan['client_public_id'] ?? '—'}',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 22,
              runSpacing: 8,
              children: [
                _fact('Principal', _money(loan['principal_amount'])),
                _fact('Outstanding', _money(loan['total_outstanding'])),
                _fact(
                  'Rate',
                  '${_n(loan['interest_rate']).toStringAsFixed(2)}% • ${_label(loan['rate_type']?.toString() ?? 'fixed')}',
                ),
                _fact(
                  'Repayment',
                  '${loan['repayment_term_count'] ?? 0} × ${_label(loan['repayment_frequency']?.toString() ?? 'monthly')}',
                ),
                _fact(
                  'Next Due',
                  '${_date(loan['next_due_date'])} • ${_money(loan['next_due_amount'])}',
                ),
                _fact('Maturity', _date(loan['maturity_date'])),
              ],
            ),
            if (warning != null && warning.isNotEmpty) ...[
              const SizedBox(height: 10),
              _banner(
                warning,
                warningLevel == 'danger'
                    ? Colors.red
                    : warningLevel == 'warning'
                    ? Colors.orange
                    : Colors.blue,
                warningLevel == 'danger'
                    ? Icons.error_outline
                    : Icons.warning_amber_outlined,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showDetail(loan['loan_id'].toString()),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('View'),
                ),
                if (_canCreate && (status == 'draft' || status == 'rejected'))
                  OutlinedButton.icon(
                    onPressed: () => _editLoan(loan),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                if (_canCreate && status == 'draft')
                  FilledButton.tonalIcon(
                    onPressed: () => _submit(loan),
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Submit'),
                  ),
                if (_canApprove && status == 'submitted') ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _decide(loan, true),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _decide(loan, false),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Reject'),
                  ),
                ],
                if (_canDisburse && status == 'approved')
                  FilledButton.icon(
                    onPressed: () => _disburse(loan),
                    icon: const Icon(Icons.outbound_outlined),
                    label: Text(
                      (loan['direction']?.toString() ?? 'given') == 'given'
                          ? 'Give Funds'
                          : 'Receive Funds',
                    ),
                  ),
                if (_canCollect &&
                    (status == 'active' || status == 'defaulted'))
                  FilledButton.icon(
                    onPressed: () => _collect(loan),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(given ? 'Collect' : 'Repay'),
                  ),
                if (_canRate &&
                    variable &&
                    const ['approved', 'active', 'defaulted'].contains(status))
                  OutlinedButton.icon(
                    onPressed: () => _changeRate(loan),
                    icon: const Icon(Icons.percent_outlined),
                    label: const Text('Rate'),
                  ),
                if (_canManage &&
                    !const ['closed', 'cancelled'].contains(status))
                  OutlinedButton.icon(
                    onPressed: () => _addCollateral(loan),
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('Collateral'),
                  ),
                if (_canManage &&
                    !const ['closed', 'cancelled'].contains(status))
                  OutlinedButton.icon(
                    onPressed: () => _addGuarantor(loan),
                    icon: const Icon(Icons.handshake_outlined),
                    label: const Text('Guarantor'),
                  ),
                if (_canManage && status == 'active')
                  OutlinedButton.icon(
                    onPressed: () => _changeStatus(loan, 'defaulted'),
                    icon: const Icon(Icons.report_problem_outlined),
                    label: const Text('Mark Default'),
                  ),
                if (_canManage && status == 'defaulted')
                  OutlinedButton.icon(
                    onPressed: () => _changeStatus(loan, 'active'),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reactivate'),
                  ),
                if (_canManage &&
                    const [
                      'draft',
                      'submitted',
                      'approved',
                      'rejected',
                    ].contains(status))
                  TextButton(
                    onPressed: () => _changeStatus(loan, 'cancelled'),
                    child: const Text('Cancel Loan'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(String title, String value) => SizedBox(
    width: 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _banner(String text, Color color, IconData icon) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );

  DateTime _suggestMaturity(DateTime first, String frequency, int terms) {
    final offset = terms > 0 ? terms - 1 : 0;
    return switch (frequency) {
      'weekly' => first.add(Duration(days: 7 * offset)),
      'biweekly' => first.add(Duration(days: 14 * offset)),
      'quarterly' => DateTime(
        first.year,
        first.month + (3 * offset),
        first.day,
      ),
      'half_yearly' => DateTime(
        first.year,
        first.month + (6 * offset),
        first.day,
      ),
      'yearly' => DateTime(first.year + offset, first.month, first.day),
      _ => DateTime(first.year, first.month + offset, first.day),
    };
  }

  Future<void> _loanSettings() async {
    var enabled = _loanAccountingEnabled;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Loan Module Settings'),
          content: SizedBox(
            width: 520,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reflect loans in business accounting'),
              subtitle: const Text(
                'ON posts loan funding, repayments, interest and penalties to Accounts. OFF keeps new loans operational only. Active loans keep their original accounting mode for audit consistency.',
              ),
              value: enabled,
              onChanged: (value) => setLocal(() => enabled = value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await _run(
        'Loan accounting setting updated.',
        () => _service.setAccountingEnabled(widget.session, enabled),
      );
    }
  }

  Future<void> _editLoan([Map<String, dynamic>? row]) async {
    Map<String, dynamic>? existing;
    if (row != null) {
      try {
        final detail = await _service.detail(
          widget.session,
          row['loan_id'].toString(),
        );
        if (detail['loan'] is Map) {
          existing = Map<String, dynamic>.from(detail['loan'] as Map);
        }
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        return;
      }
    }
    if (!mounted) return;
    final payload = await _loanEditor(existing);
    if (payload == null) return;
    await _run(row == null ? 'Loan created.' : 'Loan updated.', () async {
      if (row == null) {
        await _service.create(widget.session, payload);
      } else {
        await _service.update(
          widget.session,
          row['loan_id'].toString(),
          payload,
        );
      }
    });
  }

  Future<Map<String, dynamic>?> _loanEditor(Map<String, dynamic>? loan) async {
    String direction = loan?['direction']?.toString() ?? 'given';
    String counterpartyType =
        loan?['counterparty_type']?.toString() ??
        (direction == 'given' ? 'customer' : 'supplier');
    String? customerId = loan?['client_id']?.toString();
    String? supplierId = loan?['supplier_id']?.toString();
    if (customerId == null && _customers.isNotEmpty) {
      customerId = _customers.first.id;
    }
    if (supplierId == null && _suppliers.isNotEmpty) {
      supplierId = _suppliers.first.id;
    }
    final otherParty = TextEditingController(
      text: loan?['counterparty_name']?.toString() ?? '',
    );
    final partyReference = TextEditingController(
      text: loan?['counterparty_reference']?.toString() ?? '',
    );
    String rateType = loan?['rate_type']?.toString() ?? 'fixed';
    String amortization =
        loan?['amortization_method']?.toString() ?? 'reducing_balance';
    String frequency = loan?['repayment_frequency']?.toString() ?? 'monthly';
    String resetFrequency =
        loan?['rate_reset_frequency']?.toString() ?? 'quarterly';
    DateTime first =
        DateTime.tryParse(loan?['first_payment_date']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 30));
    final initialTerms =
        int.tryParse('${loan?['repayment_term_count'] ?? 12}') ?? 12;
    DateTime maturity =
        DateTime.tryParse(loan?['maturity_date']?.toString() ?? '') ??
        _suggestMaturity(first, frequency, initialTerms);
    DateTime? nextReview = DateTime.tryParse(
      loan?['next_rate_review_date']?.toString() ?? '',
    );

    final principal = TextEditingController(
      text: loan?['principal_amount']?.toString() ?? '',
    );
    final rate = TextEditingController(
      text: loan?['interest_rate']?.toString() ?? '0',
    );
    final rateIndex = TextEditingController(
      text: loan?['rate_index']?.toString() ?? '',
    );
    final rateMargin = TextEditingController(
      text: loan?['rate_margin']?.toString() ?? '0',
    );
    final terms = TextEditingController(text: '$initialTerms');
    final repaymentTerms = TextEditingController(
      text: loan?['repayment_terms']?.toString() ?? '',
    );
    final paymentWarning = TextEditingController(
      text: loan?['payment_warning_days']?.toString() ?? '5',
    );
    final maturityWarning = TextEditingController(
      text: loan?['maturity_warning_days']?.toString() ?? '30',
    );
    final grace = TextEditingController(
      text: loan?['grace_days']?.toString() ?? '0',
    );
    final penalty = TextEditingController(
      text: loan?['penalty_rate']?.toString() ?? '0',
    );
    final externalRef = TextEditingController(
      text: loan?['external_client_reference']?.toString() ?? '',
    );
    final purpose = TextEditingController(
      text: loan?['purpose']?.toString() ?? '',
    );
    final collateral = TextEditingController(
      text: loan?['collateral_summary']?.toString() ?? '',
    );
    final notes = TextEditingController(text: loan?['notes']?.toString() ?? '');

    Future<DateTime?> pick(DateTime current) => showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(
            loan == null ? 'New Loan' : 'Edit ${loan['loan_number'] ?? 'Loan'}',
          ),
          content: SizedBox(
            width: 900,
            height: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _formRow([
                    DropdownButtonFormField<String>(
                      initialValue: direction,
                      decoration: const InputDecoration(
                        labelText: 'Loan Direction *',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'given',
                          child: Text('Loan Given • Business lends'),
                        ),
                        DropdownMenuItem(
                          value: 'taken',
                          child: Text('Loan Taken • Business borrows'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setLocal(() {
                          direction = value;
                          counterpartyType = value == 'given'
                              ? 'customer'
                              : 'supplier';
                        });
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: counterpartyType,
                      decoration: const InputDecoration(
                        labelText: 'Counterparty Type *',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'customer',
                          child: Text('Customer / Client'),
                        ),
                        DropdownMenuItem(
                          value: 'supplier',
                          child: Text('Supplier / Lender'),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text('Other Party'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setLocal(() => counterpartyType = value);
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (counterpartyType == 'customer')
                    DropdownButtonFormField<String>(
                      initialValue: customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Customer / Client *',
                        border: OutlineInputBorder(),
                      ),
                      items: _customers
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.name} • ${c.publicId}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => customerId = value),
                    )
                  else if (counterpartyType == 'supplier')
                    DropdownButtonFormField<String>(
                      initialValue: supplierId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Supplier / Lender *',
                        border: OutlineInputBorder(),
                      ),
                      items: _suppliers
                          .map(
                            (x) => DropdownMenuItem(
                              value: x.id,
                              child: Text('${x.name} • ${x.publicId}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => supplierId = value),
                    )
                  else
                    _formRow([
                      TextField(
                        controller: otherParty,
                        decoration: const InputDecoration(
                          labelText: 'Party / Lender Name *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      TextField(
                        controller: partyReference,
                        decoration: const InputDecoration(
                          labelText: 'Party Reference',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ]),
                  const SizedBox(height: 10),
                  _formRow([
                    TextField(
                      controller: principal,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Principal Amount *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: rateType,
                      decoration: const InputDecoration(
                        labelText: 'Interest Type *',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
                        DropdownMenuItem(
                          value: 'variable',
                          child: Text('Variable'),
                        ),
                      ],
                      onChanged: (value) => value == null
                          ? null
                          : setLocal(() => rateType = value),
                    ),
                    TextField(
                      controller: rate,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Interest Rate % *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ]),
                  if (rateType == 'variable') ...[
                    const SizedBox(height: 12),
                    _formRow([
                      TextField(
                        controller: rateIndex,
                        decoration: const InputDecoration(
                          labelText: 'Rate Index * (e.g. Repo/MCLR)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      TextField(
                        controller: rateMargin,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Margin %',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: resetFrequency,
                        decoration: const InputDecoration(
                          labelText: 'Reset Frequency',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            const [
                                  'monthly',
                                  'quarterly',
                                  'half_yearly',
                                  'yearly',
                                ]
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(_label(e)),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) => value == null
                            ? null
                            : setLocal(() => resetFrequency = value),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await pick(
                          nextReview ??
                              DateTime.now().add(const Duration(days: 90)),
                        );
                        if (picked != null) setLocal(() => nextReview = picked);
                      },
                      icon: const Icon(Icons.event),
                      label: Text(
                        'Next Rate Review: ${nextReview == null ? 'Not set' : _date(nextReview)}',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _formRow([
                    DropdownButtonFormField<String>(
                      initialValue: amortization,
                      decoration: const InputDecoration(
                        labelText: 'Amortization',
                        border: OutlineInputBorder(),
                      ),
                      items: const ['reducing_balance', 'flat']
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(_label(e)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => value == null
                          ? null
                          : setLocal(() => amortization = value),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: frequency,
                      decoration: const InputDecoration(
                        labelText: 'Repayment Frequency *',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          const [
                                'weekly',
                                'biweekly',
                                'monthly',
                                'quarterly',
                                'half_yearly',
                                'yearly',
                              ]
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(_label(e)),
                                ),
                              )
                              .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setLocal(() {
                          frequency = value;
                          maturity = _suggestMaturity(
                            first,
                            frequency,
                            int.tryParse(terms.text) ?? 1,
                          );
                        });
                      },
                    ),
                    TextField(
                      controller: terms,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Repayment Term Count *',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setLocal(
                        () => maturity = _suggestMaturity(
                          first,
                          frequency,
                          int.tryParse(terms.text) ?? 1,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _formRow([
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await pick(first);
                        if (picked != null) {
                          setLocal(() {
                            first = picked;
                            maturity = _suggestMaturity(
                              first,
                              frequency,
                              int.tryParse(terms.text) ?? 1,
                            );
                          });
                        }
                      },
                      icon: const Icon(Icons.event),
                      label: Text('First Payment: ${_date(first)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await pick(maturity);
                        if (picked != null) setLocal(() => maturity = picked);
                      },
                      icon: const Icon(Icons.event_available),
                      label: Text('Maturity: ${_date(maturity)}'),
                    ),
                    TextButton.icon(
                      onPressed: () => setLocal(
                        () => maturity = _suggestMaturity(
                          first,
                          frequency,
                          int.tryParse(terms.text) ?? 1,
                        ),
                      ),
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Recalculate Maturity'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: repaymentTerms,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Repayment Terms / Conditions',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _formRow([
                    TextField(
                      controller: paymentWarning,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Payment Warning Days',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: maturityWarning,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Maturity Warning Days',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: grace,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Grace Days',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: penalty,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Late Penalty % p.a.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _formRow([
                    TextField(
                      controller: externalRef,
                      decoration: const InputDecoration(
                        labelText: 'External Client / Loan Reference',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: purpose,
                      decoration: const InputDecoration(
                        labelText: 'Loan Purpose',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: collateral,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Collateral Summary',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Internal Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final p = double.tryParse(principal.text.trim()) ?? 0;
                final r = double.tryParse(rate.text.trim()) ?? -1;
                final t = int.tryParse(terms.text.trim()) ?? 0;
                final partyOk = counterpartyType == 'customer'
                    ? customerId != null
                    : counterpartyType == 'supplier'
                    ? supplierId != null
                    : otherParty.text.trim().isNotEmpty;
                if (!partyOk ||
                    p <= 0 ||
                    r < 0 ||
                    t <= 0 ||
                    maturity.isBefore(first) ||
                    (rateType == 'variable' && rateIndex.text.trim().isEmpty)) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Check principal, rate, term count, dates and variable-rate index.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, <String, dynamic>{
                  'direction': direction,
                  'counterparty_type': counterpartyType,
                  'client_id': counterpartyType == 'customer'
                      ? customerId
                      : null,
                  'supplier_id': counterpartyType == 'supplier'
                      ? supplierId
                      : null,
                  'counterparty_name': counterpartyType == 'other'
                      ? otherParty.text.trim()
                      : null,
                  'counterparty_reference': partyReference.text.trim(),
                  'principal_amount': p,
                  'interest_rate': r,
                  'rate_type': rateType,
                  'rate_index': rateType == 'variable'
                      ? rateIndex.text.trim()
                      : null,
                  'rate_margin': double.tryParse(rateMargin.text.trim()) ?? 0,
                  'rate_reset_frequency': rateType == 'variable'
                      ? resetFrequency
                      : null,
                  'next_rate_review_date':
                      rateType == 'variable' && nextReview != null
                      ? _dateValue(nextReview!)
                      : null,
                  'amortization_method': amortization,
                  'repayment_frequency': frequency,
                  'repayment_term_count': t,
                  'repayment_terms': repaymentTerms.text.trim(),
                  'first_payment_date': _dateValue(first),
                  'maturity_date': _dateValue(maturity),
                  'payment_warning_days':
                      int.tryParse(paymentWarning.text.trim()) ?? 5,
                  'maturity_warning_days':
                      int.tryParse(maturityWarning.text.trim()) ?? 30,
                  'grace_days': int.tryParse(grace.text.trim()) ?? 0,
                  'penalty_rate': double.tryParse(penalty.text.trim()) ?? 0,
                  'external_client_reference': externalRef.text.trim(),
                  'purpose': purpose.text.trim(),
                  'collateral_summary': collateral.text.trim(),
                  'notes': notes.text.trim(),
                });
              },
              child: Text(loan == null ? 'Create Loan' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );

    for (final controller in [
      otherParty,
      partyReference,
      principal,
      rate,
      rateIndex,
      rateMargin,
      terms,
      repaymentTerms,
      paymentWarning,
      maturityWarning,
      grace,
      penalty,
      externalRef,
      purpose,
      collateral,
      notes,
    ]) {
      controller.dispose();
    }
    return result;
  }

  Widget _formRow(List<Widget> fields) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < fields.length; i++) ...[
        Expanded(child: fields[i]),
        if (i < fields.length - 1) const SizedBox(width: 10),
      ],
    ],
  );

  Future<String?> _prompt({
    required String title,
    required String label,
    String initial = '',
    bool required = false,
    int maxLines = 2,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (required && text.isEmpty) return;
              Navigator.pop(dialogContext, text);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _submit(Map<String, dynamic> loan) async {
    final ok = await _confirm(
      'Submit loan?',
      '${loan['loan_number']} will be sent for approval.',
    );
    if (!ok) return;
    await _run(
      'Loan submitted for approval.',
      () => _service.submit(widget.session, loan['loan_id'].toString()),
    );
  }

  Future<void> _decide(Map<String, dynamic> loan, bool approve) async {
    final note = await _prompt(
      title: approve ? 'Approve Loan' : 'Reject Loan',
      label: approve ? 'Approval note (optional)' : 'Rejection reason *',
      required: !approve,
    );
    if (note == null) return;
    await _run(
      approve ? 'Loan approved.' : 'Loan rejected.',
      () => _service.decide(
        widget.session,
        loan['loan_id'].toString(),
        approve: approve,
        note: note,
      ),
    );
  }

  Future<void> _disburse(Map<String, dynamic> loan) async {
    final given = (loan['direction']?.toString() ?? 'given') == 'given';
    DateTime date = DateTime.now();
    String method = 'bank';
    final reference = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(
            '${given ? 'Give Funds' : 'Receive Borrowed Funds'} • ${loan['loan_number']}',
          ),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Principal: ${_money(loan['principal_amount'])}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: InputDecoration(
                    labelText: given ? 'Funding Method' : 'Receiving Method',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['bank', 'cash', 'upi', 'card']
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e, child: Text(_label(e))),
                      )
                      .toList(),
                  onChanged: (v) =>
                      v == null ? null : setLocal(() => method = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference Number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2200),
                    );
                    if (picked != null) setLocal(() => date = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(
                    '${given ? 'Funding' : 'Receipt'} Date: ${_date(date)}',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _loanAccountingEnabled
                      ? (given
                            ? 'Creates the repayment schedule and posts Loan Receivable.'
                            : 'Creates the repayment schedule and posts Loan Payable.')
                      : 'Creates the repayment schedule. Loan accounting is OFF for new loans.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                (loan['direction']?.toString() ?? 'given') == 'given'
                    ? 'Give Funds'
                    : 'Receive Funds',
              ),
            ),
          ],
        ),
      ),
    );
    final ref = reference.text.trim();
    reference.dispose();
    if (proceed != true) return;
    await _run(
      given
          ? 'Loan funds given and schedule created.'
          : 'Borrowed funds received and schedule created.',
      () => _service.disburse(
        widget.session,
        loan['loan_id'].toString(),
        date: date,
        paymentMethod: method,
        referenceNumber: ref,
      ),
    );
  }

  Future<void> _collect(
    Map<String, dynamic> loan, {
    double? suggestedAmount,
  }) async {
    final given = (loan['direction']?.toString() ?? 'given') == 'given';
    final maxOutstanding = _n(loan['total_outstanding']);
    final dueSuggested = suggestedAmount ?? _n(loan['next_due_amount']);
    final amount = TextEditingController(
      text: dueSuggested > 0 && dueSuggested <= maxOutstanding
          ? dueSuggested.toStringAsFixed(2)
          : '',
    );
    final reference = TextEditingController();
    final notes = TextEditingController();
    DateTime date = DateTime.now();
    String method = 'cash';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(
            '${given ? 'Collect Loan Payment' : 'Repay Loan'} • ${loan['loan_number']}',
          ),
          content: SizedBox(
            width: 470,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Outstanding: ${_money(maxOutstanding)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (dueSuggested > 0 && dueSuggested <= maxOutstanding)
                      ActionChip(
                        avatar: const Icon(
                          Icons.event_available_outlined,
                          size: 18,
                        ),
                        label: Text('Pay due ${_money(dueSuggested)}'),
                        labelStyle: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.onSurface,
                        ),
                        onPressed: () => setLocal(
                          () => amount.text = dueSuggested.toStringAsFixed(2),
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.done_all_outlined, size: 18),
                      label: Text('Pay full ${_money(maxOutstanding)}'),
                      labelStyle: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.onSurface,
                      ),
                      onPressed: () => setLocal(
                        () => amount.text = maxOutstanding.toStringAsFixed(2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Payment Amount *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['cash', 'upi', 'card', 'bank']
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e, child: Text(_label(e))),
                      )
                      .toList(),
                  onChanged: (v) =>
                      v == null ? null : setLocal(() => method = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference Number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2200),
                    );
                    if (picked != null) setLocal(() => date = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: Text('Payment Date: ${_date(date)}'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text.trim()) ?? 0;
                if (value <= 0 || value > maxOutstanding + .01) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter an amount greater than zero and not above the outstanding balance.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(given ? 'Post Collection' : 'Post Repayment'),
            ),
          ],
        ),
      ),
    );
    final value = double.tryParse(amount.text.trim()) ?? 0;
    final ref = reference.text.trim();
    final note = notes.text.trim();
    amount.dispose();
    reference.dispose();
    notes.dispose();
    if (proceed != true) return;
    await _run(
      given ? 'Loan collection posted.' : 'Loan repayment posted.',
      () async {
        await _service.collect(
          widget.session,
          loan['loan_id'].toString(),
          amount: value,
          date: date,
          paymentMethod: method,
          referenceNumber: ref,
          notes: note,
        );
      },
    );
  }

  Future<void> _changeRate(Map<String, dynamic> loan) async {
    final rate = TextEditingController(
      text: loan['interest_rate']?.toString() ?? '',
    );
    final index = TextEditingController(
      text: loan['rate_index']?.toString() ?? '',
    );
    final margin = TextEditingController(
      text: loan['rate_margin']?.toString() ?? '0',
    );
    final reason = TextEditingController();
    DateTime effective = DateTime.now();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('Change Variable Rate • ${loan['loan_number']}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: rate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'New Effective Rate % *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: index,
                  decoration: const InputDecoration(
                    labelText: 'Rate Index',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: margin,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Margin %',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason / Revision Note',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: effective,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2200),
                    );
                    if (picked != null) setLocal(() => effective = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: Text('Effective: ${_date(effective)}'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if ((double.tryParse(rate.text.trim()) ?? -1) < 0) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Apply Rate'),
            ),
          ],
        ),
      ),
    );
    final newRate = double.tryParse(rate.text.trim()) ?? 0;
    final rateIndex = index.text.trim();
    final rateMargin = double.tryParse(margin.text.trim());
    final why = reason.text.trim();
    rate.dispose();
    index.dispose();
    margin.dispose();
    reason.dispose();
    if (proceed != true) return;
    await _run(
      'Variable interest rate updated.',
      () => _service.changeRate(
        widget.session,
        loan['loan_id'].toString(),
        newRate: newRate,
        effectiveDate: effective,
        rateIndex: rateIndex,
        rateMargin: rateMargin,
        reason: why,
      ),
    );
  }

  Future<void> _changeStatus(Map<String, dynamic> loan, String status) async {
    final reason = await _prompt(
      title: '${_label(status)} Loan',
      label: 'Reason / note',
      required: status == 'defaulted' || status == 'cancelled',
    );
    if (reason == null) return;
    final ok = await _confirm(
      '${_label(status)} loan?',
      '${loan['loan_number']} will change from ${_label(loan['status']?.toString() ?? '')} to ${_label(status)}.',
    );
    if (!ok) return;
    await _run(
      'Loan status changed to ${_label(status)}.',
      () => _service.setStatus(
        widget.session,
        loan['loan_id'].toString(),
        status,
        reason: reason,
      ),
    );
  }

  Future<void> _addCollateral(Map<String, dynamic> loan) async {
    final type = TextEditingController();
    final description = TextEditingController();
    final reference = TextEditingController();
    final value = TextEditingController();
    final notes = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add Collateral • ${loan['loan_number']}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: type,
                  decoration: const InputDecoration(
                    labelText: 'Collateral Type *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference / Document Number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: value,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Estimated Value',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (type.text.trim().isEmpty || description.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final typeText = type.text.trim();
    final desc = description.text.trim();
    final ref = reference.text.trim();
    final estimated = double.tryParse(value.text.trim()) ?? 0;
    final note = notes.text.trim();
    for (final c in [type, description, reference, value, notes]) {
      c.dispose();
    }
    if (proceed != true) return;
    await _run('Collateral added.', () async {
      await _service.saveCollateral(
        widget.session,
        loan['loan_id'].toString(),
        type: typeText,
        description: desc,
        referenceNumber: ref,
        estimatedValue: estimated,
        notes: note,
      );
    });
  }

  Future<void> _addGuarantor(Map<String, dynamic> loan) async {
    String linkedCustomerId = '';
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final amount = TextEditingController();
    final notes = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('Add Guarantor • ${loan['loan_number']}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: linkedCustomerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Link Existing Client (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Manual guarantor'),
                      ),
                      ..._customers.map(
                        (c) => DropdownMenuItem<String>(
                          value: c.id,
                          child: Text('${c.name} • ${c.publicId}'),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setLocal(() {
                        linkedCustomerId = value;
                        if (value.isNotEmpty) {
                          final customer = _customers.firstWhere(
                            (c) => c.id == value,
                          );
                          name.text = customer.name;
                          phone.text = customer.phone ?? '';
                          email.text = customer.email ?? '';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Guarantor Name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _formRow([
                    TextField(
                      controller: phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextField(
                      controller: email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Guarantee Amount',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final linked = linkedCustomerId.isEmpty ? null : linkedCustomerId;
    final guarantorName = name.text.trim();
    final guarantorPhone = phone.text.trim();
    final guarantorEmail = email.text.trim();
    final guaranteeAmount = double.tryParse(amount.text.trim());
    final note = notes.text.trim();
    for (final c in [name, phone, email, amount, notes]) {
      c.dispose();
    }
    if (proceed != true) return;
    await _run('Guarantor added.', () async {
      await _service.saveGuarantor(
        widget.session,
        loan['loan_id'].toString(),
        customerId: linked,
        name: guarantorName,
        phone: guarantorPhone,
        email: guarantorEmail,
        guaranteeAmount: guaranteeAmount,
        notes: note,
      );
    });
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showDetail(String loanId) async {
    Map<String, dynamic> detail;
    try {
      detail = await _service.detail(widget.session, loanId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (!mounted) return;
    final loan = detail['loan'] is Map
        ? Map<String, dynamic>.from(detail['loan'] as Map)
        : <String, dynamic>{};
    final schedule = (detail['schedule'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final payments = (detail['payments'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final rateHistory = (detail['rate_history'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final collateral = (detail['collateral'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final guarantors = (detail['guarantors'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final events = (detail['events'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final status = loan['status']?.toString() ?? '';
    final openSchedule = schedule
        .where((row) {
          final due =
              _n(row['principal_due']) +
              _n(row['interest_due']) +
              _n(row['penalty_due']);
          final paid =
              _n(row['principal_paid']) +
              _n(row['interest_paid']) +
              _n(row['penalty_paid']);
          return row['status']?.toString() != 'waived' && due - paid > 0.005;
        })
        .toList(growable: false);
    final nextOpen = openSchedule.isEmpty ? null : openSchedule.first;
    final nextDueAmount = nextOpen == null
        ? 0.0
        : (_n(nextOpen['principal_due']) +
              _n(nextOpen['interest_due']) +
              _n(nextOpen['penalty_due']) -
              _n(nextOpen['principal_paid']) -
              _n(nextOpen['interest_paid']) -
              _n(nextOpen['penalty_paid']));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${loan['loan_number'] ?? 'Loan'} • ${loan['client_name'] ?? ''}',
        ),
        content: SizedBox(
          width: 1050,
          height: 650,
          child: DefaultTabController(
            length: 6,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Schedule'),
                    Tab(text: 'Payments'),
                    Tab(text: 'Rates'),
                    Tab(text: 'Security'),
                    Tab(text: 'Events'),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      _overviewTab(loan),
                      _scheduleTab(schedule),
                      _paymentsTab(payments),
                      _ratesTab(rateHistory),
                      _securityTab(collateral, guarantors),
                      _eventsTab(events),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (_canManage && const ['draft', 'rejected'].contains(status))
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _editLoan(loan);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          if (_canManage && status == 'draft')
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _submit(loan);
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Submit'),
            ),
          if (_canApprove && status == 'submitted')
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _decide(loan, true);
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Approve'),
            ),
          if (_canDisburse && status == 'approved')
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _disburse(loan);
              },
              icon: const Icon(Icons.outbound_outlined),
              label: Text(
                (loan['direction']?.toString() ?? 'given') == 'given'
                    ? 'Give Funds'
                    : 'Receive Funds',
              ),
            ),
          if (_canCollect && const ['active', 'defaulted'].contains(status))
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _collect({
                  ...loan,
                  'next_due_amount': nextDueAmount,
                }, suggestedAmount: nextDueAmount > 0 ? nextDueAmount : null);
              },
              icon: const Icon(Icons.payments_outlined),
              label: Text(
                (loan['direction']?.toString() ?? 'given') == 'given'
                    ? (nextDueAmount > 0
                          ? 'Collect ${_money(nextDueAmount)}'
                          : 'Collect')
                    : (nextDueAmount > 0
                          ? 'Repay ${_money(nextDueAmount)}'
                          : 'Repay'),
              ),
            ),
          if (_canManage &&
              const ['approved', 'active', 'defaulted'].contains(status))
            PopupMenuButton<String>(
              tooltip: 'More loan actions',
              onSelected: (value) {
                Navigator.pop(dialogContext);
                if (value == 'collateral') _addCollateral(loan);
                if (value == 'guarantor') _addGuarantor(loan);
                if (value == 'rate') _changeRate(loan);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'collateral',
                  child: Text('Add Collateral'),
                ),
                const PopupMenuItem(
                  value: 'guarantor',
                  child: Text('Add Guarantor'),
                ),
                if (_canRate && loan['rate_type']?.toString() == 'variable')
                  const PopupMenuItem(
                    value: 'rate',
                    child: Text('Change Variable Rate'),
                  ),
              ],
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _overviewTab(Map<String, dynamic> loan) => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      Wrap(
        spacing: 28,
        runSpacing: 14,
        children: [
          _fact('Status', _label(loan['status']?.toString() ?? '')),
          _fact('Direction', _label(loan['direction']?.toString() ?? 'given')),
          _fact(
            'Counterparty',
            loan['counterparty_name']?.toString() ??
                loan['client_name']?.toString() ??
                '—',
          ),
          _fact(
            'Party ID',
            loan['client_public_id']?.toString() ??
                loan['counterparty_reference']?.toString() ??
                '—',
          ),
          _fact(
            'Accounting',
            loan['accounting_enabled'] == false
                ? 'Operational only'
                : 'Posted to accounts',
          ),
          _fact('Principal', _money(loan['principal_amount'])),
          _fact('Principal Outstanding', _money(loan['principal_outstanding'])),
          _fact('Interest Outstanding', _money(loan['interest_outstanding'])),
          _fact('Penalty Outstanding', _money(loan['penalty_outstanding'])),
          _fact('Total Outstanding', _money(loan['total_outstanding'])),
          _fact('Total Paid', _money(loan['total_paid'])),
          _fact(
            'Rate',
            '${_n(loan['interest_rate']).toStringAsFixed(2)}% ${_label(loan['rate_type']?.toString() ?? 'fixed')}',
          ),
          _fact('Rate Index', loan['rate_index']?.toString() ?? '—'),
          _fact(
            'Amortization',
            _label(loan['amortization_method']?.toString() ?? ''),
          ),
          _fact(
            'Frequency',
            _label(loan['repayment_frequency']?.toString() ?? ''),
          ),
          _fact('Terms', '${loan['repayment_term_count'] ?? 0}'),
          _fact('First Payment', _date(loan['first_payment_date'])),
          _fact('Maturity', _date(loan['maturity_date'])),
          _fact('Disbursed', _date(loan['disbursement_date'])),
          _fact('Grace Days', '${loan['grace_days'] ?? 0}'),
          _fact(
            'Penalty Rate',
            '${_n(loan['penalty_rate']).toStringAsFixed(2)}%',
          ),
        ],
      ),
      const Divider(height: 28),
      _textSection('Purpose', loan['purpose']),
      _textSection('Repayment Terms', loan['repayment_terms']),
      _textSection('Collateral Summary', loan['collateral_summary']),
      _textSection('Notes', loan['notes']),
      if ((loan['rejection_reason']?.toString() ?? '').isNotEmpty)
        _textSection('Rejection Reason', loan['rejection_reason']),
    ],
  );

  Widget _textSection(String title, dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(text),
        ],
      ),
    );
  }

  Widget _scheduleTab(List<Map<String, dynamic>> rows) => rows.isEmpty
      ? const Center(
          child: Text(
            'Schedule is created when the approved loan is disbursed.',
          ),
        )
      : ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = rows[i];
            final due =
                _n(r['principal_due']) +
                _n(r['interest_due']) +
                _n(r['penalty_due']);
            final paid =
                _n(r['principal_paid']) +
                _n(r['interest_paid']) +
                _n(r['penalty_paid']);
            return ListTile(
              leading: CircleAvatar(
                child: Text('${r['installment_no'] ?? i + 1}'),
              ),
              title: Text('${_date(r['due_date'])} • ${_money(due)}'),
              subtitle: Text(
                'Principal ${_money(r['principal_due'])} • Interest ${_money(r['interest_due'])} • Penalty ${_money(r['penalty_due'])}\nPaid ${_money(paid)}',
              ),
              isThreeLine: true,
              trailing: Text(_label(r['status']?.toString() ?? 'pending')),
            );
          },
        );

  Widget _paymentsTab(List<Map<String, dynamic>> rows) => rows.isEmpty
      ? const Center(child: Text('No loan payments posted yet.'))
      : ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final p = rows[i];
            return ListTile(
              title: Text(
                '${p['payment_number'] ?? 'Payment'} • ${_money(p['amount'])}',
              ),
              subtitle: Text(
                '${_date(p['payment_date'])} • ${_label(p['payment_method']?.toString() ?? '')}\nPrincipal ${_money(p['principal_amount'])} • Interest ${_money(p['interest_amount'])} • Penalty ${_money(p['penalty_amount'])}',
              ),
              isThreeLine: true,
              trailing: _canManage && p['status']?.toString() == 'posted'
                  ? IconButton(
                      tooltip: 'Reverse payment',
                      icon: const Icon(Icons.undo),
                      onPressed: () => _reversePayment(p),
                    )
                  : Text(_label(p['status']?.toString() ?? 'posted')),
            );
          },
        );

  Future<void> _reversePayment(Map<String, dynamic> payment) async {
    final reason = await _prompt(
      title: 'Reverse Loan Payment',
      label: 'Reversal reason *',
      required: true,
    );
    if (reason == null || reason.isEmpty) return;
    final ok = await _confirm(
      'Reverse payment?',
      '${payment['payment_number'] ?? 'Payment'} for ${_money(payment['amount'])} will be reversed.',
    );
    if (!ok) return;
    await _run(
      'Loan payment reversed.',
      () => _service.reversePayment(
        widget.session,
        payment['id'].toString(),
        reason,
      ),
    );
  }

  Widget _ratesTab(List<Map<String, dynamic>> rows) => rows.isEmpty
      ? const Center(child: Text('No rate history yet.'))
      : ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = rows[i];
            return ListTile(
              leading: const Icon(Icons.percent_outlined),
              title: Text(
                '${_n(r['new_rate']).toStringAsFixed(2)}% effective ${_date(r['effective_date'])}',
              ),
              subtitle: Text(
                '${r['rate_index'] ?? ''}${r['rate_margin'] == null ? '' : ' • Margin ${r['rate_margin']}%'}${(r['reason']?.toString() ?? '').isEmpty ? '' : '\n${r['reason']}'}',
              ),
            );
          },
        );

  Widget _securityTab(
    List<Map<String, dynamic>> collateral,
    List<Map<String, dynamic>> guarantors,
  ) => ListView(
    children: [
      const ListTile(
        title: Text(
          'Collateral',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      if (collateral.isEmpty)
        const ListTile(title: Text('No collateral records.')),
      ...collateral.map(
        (c) => ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: Text(
            '${c['collateral_type'] ?? ''} • ${c['description'] ?? ''}',
          ),
          subtitle: Text(
            'Reference: ${c['reference_number'] ?? '—'} • Estimated: ${_money(c['estimated_value'])}',
          ),
          trailing: Text(_label(c['status']?.toString() ?? 'active')),
        ),
      ),
      const Divider(),
      const ListTile(
        title: Text(
          'Guarantors',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      if (guarantors.isEmpty)
        const ListTile(title: Text('No guarantor records.')),
      ...guarantors.map(
        (g) => ListTile(
          leading: const Icon(Icons.handshake_outlined),
          title: Text(g['name']?.toString() ?? 'Guarantor'),
          subtitle: Text('${g['phone'] ?? ''} ${g['email'] ?? ''}'),
          trailing: g['guarantee_amount'] == null
              ? null
              : Text(_money(g['guarantee_amount'])),
        ),
      ),
    ],
  );

  Widget _eventsTab(List<Map<String, dynamic>> rows) => rows.isEmpty
      ? const Center(child: Text('No loan events.'))
      : ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final e = rows[i];
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(_label(e['event_type']?.toString() ?? 'event')),
              subtitle: Text(e['message']?.toString() ?? ''),
              trailing: Text(_date(e['event_date'])),
            );
          },
        );
}
