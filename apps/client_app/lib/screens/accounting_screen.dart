import 'package:flutter/material.dart';

import '../models/accounting_summary.dart';
import '../models/client_session.dart';
import '../services/accounting_service.dart';
import '../services/location_scope_service.dart';

class AccountingScreen extends StatefulWidget {
  final ClientSession session;
  const AccountingScreen({super.key, required this.session});

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  final AccountingService _service = AccountingService();
  final TextEditingController _search = TextEditingController();
  late DateTime _from;
  late DateTime _to;
  String _section = 'overview';
  bool _loading = true;
  String? _error;
  AccountingSummary? _summary;
  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _mappings = const [];
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic> _gst = const {};
  Map<String, dynamic> _statement = const {};

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('accounting.manage');

  bool get _canJournal =>
      _canManage || widget.session.hasPermission('accounting.journal');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _money(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return widget.session.currencyCode == 'INR'
        ? '₹${number.toStringAsFixed(2)}'
        : '${widget.session.currencyCode} ${number.toStringAsFixed(2)}';
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_section == 'overview') {
        final values = await Future.wait([
          _service.summary(
            tenantId: widget.session.business.id,
            from: _from,
            to: _to,
          ),
          _service.gstSummary(
            tenantId: widget.session.business.id,
            from: _from,
            to: _to,
          ),
        ]);
        _summary = values[0] as AccountingSummary;
        _gst = values[1] as Map<String, dynamic>;
      } else if (_section == 'accounts') {
        final values = await Future.wait([
          _service.accounts(tenantId: widget.session.business.id),
          _service.mappings(tenantId: widget.session.business.id),
        ]);
        _accounts = values[0];
        _mappings = values[1];
      } else if (const {
        'trial_balance',
        'profit_loss',
        'balance_sheet',
        'cash_flow',
      }.contains(_section)) {
        _statement = await _service.statement(
          tenantId: widget.session.business.id,
          statement: _section,
          from: _from,
          to: _to,
        );
      } else {
        _rows = await _service.register(
          tenantId: widget.session.business.id,
          register: _section,
          from: _from,
          to: _to,
          query: _search.text,
        );
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final current = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
    _load();
  }

  Future<void> _editAccount([Map<String, dynamic>? account]) async {
    final code = TextEditingController(
      text: account?['code']?.toString() ?? '',
    );
    final name = TextEditingController(
      text: account?['name']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: account?['description']?.toString() ?? '',
    );
    var type = account?['account_type']?.toString() ?? 'asset';
    var active = account?['active'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(account == null ? 'Add Account' : 'Edit Account'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: code,
                        decoration: const InputDecoration(
                          labelText: 'Account code',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Account name',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Account type'),
                  items: const [
                    DropdownMenuItem(value: 'asset', child: Text('Asset')),
                    DropdownMenuItem(
                      value: 'liability',
                      child: Text('Liability'),
                    ),
                    DropdownMenuItem(value: 'equity', child: Text('Equity')),
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                    DropdownMenuItem(
                      value: 'cogs',
                      child: Text('Cost of Goods Sold'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                  title: const Text('Active'),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _service.saveAccount(
        tenantId: widget.session.business.id,
        accountId: account?['id']?.toString(),
        code: code.text,
        name: name.text,
        type: type,
        description: description.text,
        active: active,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Account saved.')));
        _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _editMappings() async {
    if (_accounts.isEmpty) return;
    const keys = <(String, String)>[
      ('payment.cash', 'Cash transactions'),
      ('payment.bank', 'Bank transactions'),
      ('payment.upi', 'UPI transactions'),
      ('payment.card', 'Card transactions'),
      ('accounts_receivable', 'Customer credit / Accounts Receivable'),
      ('accounts_payable', 'Supplier credit / Accounts Payable'),
      ('customer_credits', 'Customer refunds / credits'),
      ('supplier_credits', 'Supplier credits / refunds due'),
      ('inventory_asset', 'Inventory asset'),
      ('input_gst', 'Input GST'),
      ('output_gst', 'Output GST'),
      ('sales_revenue', 'Sales revenue'),
      ('cogs', 'Cost of Goods Sold'),
      ('operating_expense', 'Operating expenses'),
      ('purchase_expense', 'Direct purchase expense'),
      ('rounding', 'Rounding / variance'),
    ];
    final selected = <String, String>{};
    for (final key in keys) {
      final row = _mappings
          .where((m) => m['mapping_key']?.toString() == key.$1)
          .firstOrNull;
      selected[key.$1] =
          row?['account_id']?.toString() ?? _accounts.first['id'].toString();
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Accounting Mappings'),
          content: SizedBox(
            width: 680,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: keys.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final entry = keys[index];
                  return DropdownButtonFormField<String>(
                    initialValue: selected[entry.$1],
                    isExpanded: true,
                    decoration: InputDecoration(labelText: entry.$2),
                    items: _accounts
                        .where((account) => account['active'] != false)
                        .map(
                          (account) => DropdownMenuItem(
                            value: account['id'].toString(),
                            child: Text(
                              '${account['code']} • ${account['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selected[entry.$1] = value);
                      }
                    },
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save Mappings'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      for (final entry in selected.entries) {
        await _service.setMapping(
          tenantId: widget.session.business.id,
          mappingKey: entry.key,
          accountId: entry.value,
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Accounting mappings saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _archiveAccount(Map<String, dynamic> account) async {
    if (account['is_system'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System accounts cannot be archived.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive Account'),
        content: Text(
          'Archive ${account['code']} • ${account['name']}? Historical journal entries remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.saveAccount(
        tenantId: widget.session.business.id,
        accountId: account['id']?.toString(),
        code: account['code']?.toString() ?? '',
        name: account['name']?.toString() ?? '',
        type: account['account_type']?.toString() ?? 'asset',
        parentId: account['parent_id']?.toString(),
        description: account['description']?.toString() ?? '',
        active: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account archived.')));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _postJournal() async {
    final locationId = LocationScopeService.selectedLocationId.value;
    if (locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a specific store before posting a manual journal.',
          ),
        ),
      );
      return;
    }
    try {
      final accounts = await _service.accounts(
        tenantId: widget.session.business.id,
      );
      if (!mounted) return;
      final activeAccounts = accounts
          .where((a) => a['active'] != false)
          .toList();
      if (activeAccounts.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('At least two active accounts are required.'),
          ),
        );
        return;
      }
      final draft = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _ManualJournalDialog(accounts: activeAccounts, initialDate: _to),
      );
      if (draft == null || !mounted) return;
      await _service.postManualJournal(
        tenantId: widget.session.business.id,
        locationId: locationId,
        date: draft['date'] as DateTime,
        description: draft['description']?.toString() ?? '',
        lines: (draft['lines'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Manual journal posted.')));
      setState(() => _section = 'journal');
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  static const _sections = <(String, String, IconData)>[
    ('overview', 'Overview', Icons.dashboard_outlined),
    ('accounts', 'Chart of Accounts', Icons.account_tree_outlined),
    ('sales', 'Sales Register', Icons.receipt_long_outlined),
    ('purchases', 'Purchase Register', Icons.shopping_cart_outlined),
    ('cash', 'Cash Book', Icons.payments_outlined),
    ('bank', 'Bank / UPI / Card', Icons.account_balance_outlined),
    ('receivables', 'Customer Ledger', Icons.person_outline),
    ('payables', 'Supplier Ledger', Icons.local_shipping_outlined),
    ('gst', 'GST Register', Icons.percent_outlined),
    ('journal', 'Journal', Icons.edit_note_outlined),
    ('all', 'General Ledger', Icons.menu_book_outlined),
    ('trial_balance', 'Trial Balance', Icons.balance_outlined),
    ('profit_loss', 'Profit & Loss', Icons.show_chart_outlined),
    ('balance_sheet', 'Balance Sheet', Icons.account_balance_wallet_outlined),
    ('cash_flow', 'Cash Flow', Icons.swap_vert_circle_outlined),
  ];

  String _sectionLabel(String key) => _sections
      .firstWhere((item) => item.$1 == key, orElse: () => _sections.first)
      .$2;

  Widget _sectionNavigation({required bool compact}) {
    if (compact) {
      return DropdownButtonFormField<String>(
        initialValue: _section,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Accounting section',
          prefixIcon: Icon(Icons.account_balance_outlined),
        ),
        items: _sections
            .map(
              (item) => DropdownMenuItem(
                value: item.$1,
                child: Row(
                  children: [
                    Icon(item.$3, size: 18),
                    const SizedBox(width: 10),
                    Text(item.$2),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null || value == _section) return;
          setState(() => _section = value);
          _load();
        },
      );
    }

    return Container(
      width: 214,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: _sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 3),
        itemBuilder: (context, index) {
          final item = _sections[index];
          final selected = item.$1 == _section;
          return Material(
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (selected) return;
                setState(() => _section = item.$1);
                _load();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Icon(
                      item.$3,
                      size: 19,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1040;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? constraints.maxWidth : 310,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Accounting',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _sectionLabel(_section),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(from: true),
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text('From ${_date(_from)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(from: false),
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text('To ${_date(_to)}'),
                  ),
                  IconButton(
                    onPressed: _load,
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (compact) ...[
                const SizedBox(height: 10),
                _sectionNavigation(compact: true),
              ],
              if (!const {
                'overview',
                'accounts',
                'trial_balance',
                'profit_loss',
                'balance_sheet',
                'cash_flow',
              }.contains(_section)) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText:
                        'Search invoice, product/SKU, party, account or reference…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Expanded(child: _body()),
            ],
          );

          if (compact) return content;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionNavigation(compact: false),
              const SizedBox(width: 14),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_section == 'overview') return _overview();
    if (_section == 'accounts') return _accountsView();
    if (const {
      'trial_balance',
      'profit_loss',
      'balance_sheet',
      'cash_flow',
    }.contains(_section)) {
      return _statementView();
    }
    return _registerView();
  }

  Widget _overview() {
    final s = _summary;
    if (s == null) return const Center(child: Text('No accounting summary.'));
    final cards = <(String, String, IconData)>[
      ('Revenue', _money(s.revenue), Icons.trending_up),
      ('COGS', _money(s.costOfGoodsSold), Icons.inventory_2_outlined),
      ('Gross Profit', _money(s.grossProfit), Icons.show_chart),
      ('Expenses', _money(s.operatingExpenses), Icons.payments_outlined),
      (
        'Net Profit',
        _money(s.netOperatingProfit),
        Icons.account_balance_wallet_outlined,
      ),
      ('Receivables', _money(s.receivables), Icons.call_received),
      ('Payables', _money(s.payables), Icons.call_made),
      ('Inventory', _money(s.inventoryValue), Icons.warehouse_outlined),
    ];
    return ListView(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (item) =>
                    _MetricCard(label: item.$1, value: item.$2, icon: item.$3),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 36,
              runSpacing: 14,
              children: [
                _MiniMetric('Taxable Sales', _money(_gst['taxable_sales'])),
                _MiniMetric('Output GST', _money(_gst['output_gst'])),
                _MiniMetric('Input GST', _money(_gst['input_gst'])),
                _MiniMetric('Net GST Payable', _money(_gst['net_gst_payable'])),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _accountsView() {
    if (_accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No accounts found.'),
            if (_canManage) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _editAccount(),
                icon: const Icon(Icons.add),
                label: const Text('Add Account'),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_canManage)
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _editMappings,
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('Account Mappings'),
                ),
                FilledButton.icon(
                  onPressed: () => _editAccount(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Account'),
                ),
              ],
            ),
          ),
        if (_canManage) const SizedBox(height: 12),
        Expanded(
          child: Card(
            child: ListView.separated(
              itemCount: _accounts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final a = _accounts[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(a['code']?.toString().substring(0, 1) ?? 'A'),
                  ),
                  title: Text(
                    '${a['code']}  •  ${a['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${a['account_type']} ${a['is_system'] == true ? '• System account' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (a['active'] == false)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Chip(label: Text('Archived')),
                        ),
                      Text(
                        _money(a['balance']),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (_canManage) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Edit account',
                          onPressed: () => _editAccount(a),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        if (a['is_system'] != true && a['active'] != false)
                          IconButton(
                            tooltip: 'Archive account',
                            onPressed: () => _archiveAccount(a),
                            icon: const Icon(Icons.archive_outlined),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _registerView() {
    final list = _rows.isEmpty
        ? const Expanded(
            child: Center(child: Text('No matching accounting entries.')),
          )
        : Expanded(
            child: Card(
              child: ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(
                      '${row['reference'] ?? '-'}  •  ${row['description'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${row['entry_date'] ?? ''}  •  ${row['party'] ?? ''}  •  ${row['location_code'] ?? ''}  •  ${row['user_name'] ?? ''}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if ((row['debit'] as num?)?.toDouble() != 0)
                          Text(
                            'DR ${_money(row['debit'])}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        if ((row['credit'] as num?)?.toDouble() != 0)
                          Text(
                            'CR ${_money(row['credit'])}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
    return Column(
      children: [
        if (_section == 'journal' && _canJournal) ...[
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _postJournal,
              icon: const Icon(Icons.add),
              label: const Text('Post Manual Journal'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        list,
      ],
    );
  }

  Widget _statementView() {
    final rows = (_statement['rows'] as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final summary = _statement['summary'] is Map
        ? Map<String, dynamic>.from(_statement['summary'] as Map)
        : <String, dynamic>{};

    final metrics = <(String, String)>[];
    switch (_section) {
      case 'trial_balance':
        metrics.addAll([
          ('Total Debit', _money(summary['total_debit'])),
          ('Total Credit', _money(summary['total_credit'])),
          ('Difference', _money(summary['difference'])),
        ]);
        break;
      case 'profit_loss':
        metrics.addAll([
          ('Revenue', _money(summary['revenue'])),
          ('COGS', _money(summary['cogs'])),
          ('Expenses', _money(summary['expenses'])),
          ('Net Profit', _money(summary['net_profit'])),
        ]);
        break;
      case 'balance_sheet':
        metrics.addAll([
          ('Assets', _money(summary['assets'])),
          ('Liabilities', _money(summary['liabilities'])),
          ('Equity', _money(summary['equity'])),
          ('Current Earnings', _money(summary['current_earnings'])),
        ]);
        break;
      case 'cash_flow':
        metrics.addAll([
          ('Cash Inflow', _money(summary['inflow'])),
          ('Cash Outflow', _money(summary['outflow'])),
          ('Net Change', _money(summary['net_change'])),
        ]);
        break;
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics.map((m) => _StatementMetric(m.$1, m.$2)).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            child: rows.isEmpty
                ? const Center(
                    child: Text('No accounting balances for this period.'),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final codeName =
                          '${row['code'] ?? ''} • ${row['name'] ?? ''}';
                      String trailing;
                      String subtitle =
                          row['account_type']?.toString().toUpperCase() ?? '';
                      if (_section == 'trial_balance') {
                        trailing =
                            'DR ${_money(row['debit'])}   CR ${_money(row['credit'])}';
                      } else if (_section == 'cash_flow') {
                        trailing = _money(row['net_change']);
                        subtitle =
                            'In ${_money(row['inflow'])} • Out ${_money(row['outflow'])}';
                      } else {
                        trailing = _money(row['amount']);
                      }
                      return ListTile(
                        dense: true,
                        title: Text(
                          codeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(subtitle),
                        trailing: Text(
                          trailing,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  const _MiniMetric(this.label, this.value);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ],
    ),
  );
}

class _StatementMetric extends StatelessWidget {
  final String label;
  final String value;
  const _StatementMetric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _ManualJournalDialog extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final DateTime initialDate;
  const _ManualJournalDialog({
    required this.accounts,
    required this.initialDate,
  });

  @override
  State<_ManualJournalDialog> createState() => _ManualJournalDialogState();
}

class _ManualJournalDialogState extends State<_ManualJournalDialog> {
  late DateTime _date;
  final _description = TextEditingController();
  final List<_JournalLineDraft> _lines = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _lines.addAll([_JournalLineDraft(), _JournalLineDraft()]);
  }

  @override
  void dispose() {
    _description.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _submit() {
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Description is required.');
      return;
    }
    final rows = <Map<String, dynamic>>[];
    var debit = 0.0;
    var credit = 0.0;
    for (final line in _lines) {
      final dr = double.tryParse(line.debit.text.trim()) ?? 0;
      final cr = double.tryParse(line.credit.text.trim()) ?? 0;
      if (line.accountId == null && dr == 0 && cr == 0) continue;
      if (line.accountId == null) {
        setState(() => _error = 'Choose an account for every amount.');
        return;
      }
      if (dr < 0 || cr < 0 || (dr > 0 && cr > 0) || (dr == 0 && cr == 0)) {
        setState(
          () => _error =
              'Each journal line must contain either a debit or a credit amount.',
        );
        return;
      }
      debit += dr;
      credit += cr;
      rows.add({
        'account_id': line.accountId,
        'debit': dr,
        'credit': cr,
        'description': description,
      });
    }
    if (rows.length < 2 || debit <= 0 || (debit - credit).abs() > 0.01) {
      setState(
        () => _error =
            'Journal must have at least two lines and total Debit must equal total Credit.',
      );
      return;
    }
    Navigator.pop(context, {
      'date': _date,
      'description': description,
      'lines': rows,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Post Manual Journal'),
      content: SizedBox(
        width: 760,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _description,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      '${_date.day.toString().padLeft(2, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.year}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final line = _lines[index];
                    return Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: DropdownButtonFormField<String>(
                            initialValue: line.accountId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Account ${index + 1}',
                            ),
                            items: widget.accounts
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a['id'].toString(),
                                    child: Text(
                                      '${a['code']} • ${a['name']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => line.accountId = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: line.debit,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Debit',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: line.credit,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Credit',
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Remove line',
                          onPressed: _lines.length <= 2
                              ? null
                              : () => setState(() {
                                  final removed = _lines.removeAt(index);
                                  removed.dispose();
                                }),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _lines.add(_JournalLineDraft())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Line'),
                ),
              ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.post_add),
          label: const Text('Post Journal'),
        ),
      ],
    );
  }
}

class _JournalLineDraft {
  String? accountId;
  final debit = TextEditingController();
  final credit = TextEditingController();
  void dispose() {
    debit.dispose();
    credit.dispose();
  }
}
