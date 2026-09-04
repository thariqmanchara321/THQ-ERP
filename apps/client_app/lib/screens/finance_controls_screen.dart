import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import 'opening_balances_v500_screen.dart';
import 'bank_reconciliation_v500_screen.dart';

class FinanceControlsScreen extends StatefulWidget {
  final ClientSession session;
  const FinanceControlsScreen({super.key, required this.session});

  @override
  State<FinanceControlsScreen> createState() => _FinanceControlsScreenState();
}

class _FinanceControlsScreenState extends State<FinanceControlsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _years = const [];
  List<Map<String, dynamic>> _banks = const [];
  List<Map<String, dynamic>> _recurring = const [];
  List<Map<String, dynamic>> _journals = const [];

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('accounting.manage') ||
      widget.session.hasPermission('accounting.journal');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const <Map<String, dynamic>>[];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;
      final values = await Future.wait([
        db.rpc(
          'finance_controls_summary_v500',
          params: {'p_tenant_id': widget.session.business.id},
        ),
        db.rpc(
          'financial_years_list_v500',
          params: {'p_tenant_id': widget.session.business.id},
        ),
        db.rpc(
          'bank_accounts_list_v500',
          params: {'p_tenant_id': widget.session.business.id},
        ),
        db.rpc(
          'recurring_expenses_list_v500',
          params: {'p_tenant_id': widget.session.business.id},
        ),
        db.rpc(
          'journal_center_list_v500',
          params: {'p_tenant_id': widget.session.business.id, 'p_limit': 250},
        ),
      ]);
      _summary = values[0] is Map
          ? Map<String, dynamic>.from(values[0] as Map)
          : <String, dynamic>{};
      _years = _rows(values[1]);
      _banks = _rows(values[2]);
      _recurring = _rows(values[3]);
      _journals = _rows(values[4]);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _processRecurring() async {
    try {
      final result = await Supabase.instance.client.rpc(
        'recurring_expenses_process_v500',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_through_date': DateTime.now().toIso8601String().substring(0, 10),
        },
      );
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('Recurring expense processing complete: $result'),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _openJournal(Map<String, dynamic> journal) async {
    final id = (journal['journal_id'] ?? journal['id'])?.toString();
    if (id == null || id.isEmpty) return;
    try {
      final raw = await Supabase.instance.client.rpc(
        'journal_center_detail_v500',
        params: {'p_tenant_id': widget.session.business.id, 'p_journal_id': id},
      );
      if (!mounted) return;
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      final lines = data['lines'] is List
          ? (data['lines'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(journal['entry_number']?.toString() ?? 'Journal'),
          content: SizedBox(
            width: 760,
            height: 430,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(journal['description']?.toString() ?? ''),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final l = lines[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${l['account_code'] ?? ''} • ${l['account_name'] ?? ''}',
                        ),
                        subtitle: Text(l['description']?.toString() ?? ''),
                        trailing: Text(
                          'Dr ${l['debit'] ?? 0}   Cr ${l['credit'] ?? 0}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (_canManage &&
                (journal['status']?.toString() ?? 'posted') == 'posted')
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _reverseJournal(journal);
                },
                child: const Text('Reverse'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _closeYear(Map<String, dynamic> year) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close financial year?'),
        content: Text(
          'This creates the closing journal and locks ${year['name'] ?? 'the year'} through ${year['end_date'] ?? ''}. Posted operational transactions must be reversed from their source.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close year'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.rpc(
        'financial_year_close_v500',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_year_id': year['id'],
        },
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _reverseJournal(Map<String, dynamic> journal) async {
    final id = (journal['journal_id'] ?? journal['id'])?.toString();
    if (id == null) return;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reverse journal'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason *'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true || text.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'journal_reverse_v500',
        params: {
          'p_tenant_id': widget.session.business.id,
          'p_journal_id': id,
          'p_reason': text,
        },
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Controls'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Journal Center'),
            Tab(text: 'Financial Years'),
            Tab(text: 'Bank Accounts'),
            Tab(text: 'Recurring Expenses'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _overview(),
                _journalList(),
                _financialYearsList(),
                _bankAccountsList(),
                _recurringList(),
              ],
            ),
    );
  }

  Widget _overview() {
    final recon = _asMap(_summary['reconciliation']);
    final integrity = _asMap(recon['integrity']);
    final ready = recon['ready'] == true;
    final checkedAt = _checkedAt(recon['checked_at']);
    const sections = <(String, String, IconData)>[
      (
        'accounts_receivable',
        'Accounts Receivable',
        Icons.receipt_long_outlined,
      ),
      ('accounts_payable', 'Accounts Payable', Icons.request_quote_outlined),
      ('inventory', 'Inventory', Icons.inventory_2_outlined),
      ('cogs', 'COGS', Icons.inventory_outlined),
      ('output_gst', 'Output GST', Icons.upload_outlined),
      ('input_gst', 'Input GST', Icons.download_outlined),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric(
                'Open Financial Years',
                '${_summary['open_financial_years'] ?? 0}',
                Icons.calendar_month_outlined,
              ),
              _metric(
                'Active Bank Accounts',
                '${_summary['active_bank_accounts'] ?? 0}',
                Icons.account_balance_outlined,
              ),
              _metric(
                'Unmatched Bank Lines',
                '${_summary['unmatched_bank_lines'] ?? 0}',
                Icons.rule_outlined,
              ),
              _metric(
                'Due Recurring Expenses',
                '${_summary['due_recurring_expenses'] ?? 0}',
                Icons.event_repeat_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: ready
                        ? Colors.green.withValues(alpha: .12)
                        : Colors.orange.withValues(alpha: .12),
                    child: Icon(
                      ready
                          ? Icons.verified_outlined
                          : Icons.warning_amber_rounded,
                      color: ready
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ready
                              ? 'Finance reconciliation is healthy'
                              : 'Finance reconciliation needs attention',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          checkedAt.isEmpty
                              ? 'Operational balances are compared with the General Ledger.'
                              : 'Last checked $checkedAt • Operational balances are compared with the General Ledger.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    avatar: Icon(
                      ready ? Icons.check_circle_outline : Icons.error_outline,
                      size: 17,
                    ),
                    label: Text(ready ? 'RECONCILED' : 'REVIEW'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: sections.map((entry) {
              final data = _asMap(recon[entry.$1]);
              return _reconciliationCard(entry.$2, entry.$3, data);
            }).toList(),
          ),
          const SizedBox(height: 10),
          _integrityCard(integrity),
        ],
      ),
    );
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  double _asAmount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  String _amount(dynamic value) => _asAmount(value).toStringAsFixed(2);

  String _checkedAt(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return '';
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _reconciliationCard(
    String label,
    IconData icon,
    Map<String, dynamic> data,
  ) {
    final operational = data['operational'] ?? data['operational_value'] ?? 0;
    final ledger = data['general_ledger'] ?? 0;
    final difference = _asAmount(data['difference']);
    final ok = difference.abs() <= .05 && data['reconciled'] != false;
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(
                    ok ? Icons.check_circle : Icons.error_outline,
                    size: 18,
                    color: ok ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _reconLine('Operational', _amount(operational)),
              _reconLine('General Ledger', _amount(ledger)),
              const Divider(height: 14),
              _reconLine(
                'Difference',
                _amount(difference),
                bold: true,
                warning: !ok,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reconLine(
    String label,
    String value, {
    bool bold = false,
    bool warning = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: warning ? Colors.orange.shade900 : null,
          ),
        ),
      ],
    ),
  );

  Widget _integrityCard(Map<String, dynamic> integrity) {
    const checks = <(String, String)>[
      ('missing_source_journals', 'Missing source journals'),
      ('zero_value_posted_lines', 'Zero-value posted lines'),
      ('duplicate_source_journals', 'Duplicate source journals'),
      ('unbalanced_posted_journals', 'Unbalanced posted journals'),
    ];
    final healthy = checks.every(
      (entry) => _asAmount(integrity[entry.$1]) == 0,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  healthy ? Icons.shield_outlined : Icons.warning_amber_rounded,
                  color: healthy
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Journal integrity',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: checks.map((entry) {
                final count = _asAmount(integrity[entry.$1]).round();
                return Chip(
                  avatar: Icon(
                    count == 0 ? Icons.check : Icons.warning_amber_rounded,
                    size: 16,
                  ),
                  label: Text('${entry.$2}: $count'),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12)),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
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
  );

  Widget _journalList() => ListView.separated(
    padding: const EdgeInsets.all(12),
    itemCount: _journals.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, i) {
      final j = _journals[i];
      return ListTile(
        dense: true,
        onTap: () => _openJournal(j),
        title: Text('${j['entry_number'] ?? ''} • ${j['description'] ?? ''}'),
        subtitle: Text(
          '${j['entry_date'] ?? ''} • ${j['source_type'] ?? 'manual'} • ${j['source_reference'] ?? ''}',
        ),
        trailing: Text(
          'Dr ${j['total_debit'] ?? 0}\nCr ${j['total_credit'] ?? 0}',
          textAlign: TextAlign.right,
        ),
      );
    },
  );

  Widget _simpleList(List<Map<String, dynamic>> rows, String empty) =>
      rows.isEmpty
      ? Center(child: Text(empty))
      : ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = rows[i];
            final title =
                r['name'] ??
                r['account_name'] ??
                r['title'] ??
                r['voucher_number'] ??
                'Record';
            return ListTile(
              dense: true,
              title: Text('$title'),
              subtitle: Text(
                r.entries
                    .where(
                      (e) => !const {
                        'id',
                        'tenant_id',
                        'name',
                        'account_name',
                        'title',
                      }.contains(e.key),
                    )
                    .take(5)
                    .map((e) => '${e.key}: ${e.value ?? ''}')
                    .join(' • '),
              ),
            );
          },
        );

  Widget _financialYearsList() => Column(
    children: [
      if (_canManage)
        Padding(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) =>
                          OpeningBalancesV500Screen(session: widget.session),
                    ),
                  )
                  .then((_) => _load()),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Opening Balances'),
            ),
          ),
        ),
      Expanded(
        child: _years.isEmpty
            ? const Center(child: Text('No financial years configured.'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _years.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final y = _years[i];
                  return ListTile(
                    title: Text(y['name']?.toString() ?? 'Financial year'),
                    subtitle: Text(
                      '${y['start_date']} → ${y['end_date']} • ${y['status']}${y['locked_through'] != null ? ' • locked through ${y['locked_through']}' : ''}',
                    ),
                    trailing: _canManage && y['status'] == 'open'
                        ? FilledButton.tonal(
                            onPressed: () => _closeYear(y),
                            child: const Text('Close'),
                          )
                        : null,
                  );
                },
              ),
      ),
    ],
  );

  Widget _bankAccountsList() => _banks.isEmpty
      ? const Center(child: Text('No bank accounts configured.'))
      : ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _banks.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final b = _banks[i];
            return ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(
                b['account_name']?.toString() ??
                    b['name']?.toString() ??
                    'Bank account',
              ),
              subtitle: Text(
                '${b['bank_name'] ?? ''} • ${b['account_number'] ?? ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => BankReconciliationV500Screen(
                        session: widget.session,
                        bank: b,
                      ),
                    ),
                  )
                  .then((_) => _load()),
            );
          },
        );

  Widget _recurringList() => Column(
    children: [
      if (_canManage)
        Padding(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _processRecurring,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Process Due Expenses'),
            ),
          ),
        ),
      Expanded(
        child: _simpleList(_recurring, 'No recurring expenses configured.'),
      ),
    ],
  );
}
