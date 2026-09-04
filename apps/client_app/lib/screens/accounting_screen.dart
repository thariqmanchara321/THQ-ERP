import 'package:flutter/material.dart';

import '../models/accounting_summary.dart';
import '../models/client_session.dart';
import '../services/accounting_service.dart';
import '../services/accounting_export_service.dart';
import '../services/location_scope_service.dart';
import '../widgets/searchable_select.dart';
import 'finance_controls_screen.dart';

class _AccountingLoadCacheEntry {
  const _AccountingLoadCacheEntry({
    required this.loadedAt,
    required this.primary,
    this.secondary,
  });

  final DateTime loadedAt;
  final Object primary;
  final Object? secondary;
}

class AccountingScreen extends StatefulWidget {
  final ClientSession session;
  const AccountingScreen({super.key, required this.session});

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  final AccountingService _service = AccountingService();
  final AccountingExportService _exportService = AccountingExportService();
  bool _exporting = false;
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

  static const Duration _loadCacheTtl = Duration(seconds: 45);
  final Map<String, _AccountingLoadCacheEntry> _loadCache =
      <String, _AccountingLoadCacheEntry>{};
  int _loadGeneration = 0;

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

  String _loadCacheKey({
    required String section,
    required DateTime from,
    required DateTime to,
    required String query,
  }) {
    if (section == 'accounts') return 'accounts';
    String dateKey(DateTime value) =>
        '${value.year}-${value.month}-${value.day}';
    return '$section|${dateKey(from)}|${dateKey(to)}|$query';
  }

  void _applyLoadEntry(String section, _AccountingLoadCacheEntry entry) {
    if (section == 'overview') {
      _summary = entry.primary as AccountingSummary;
      _gst = entry.secondary as Map<String, dynamic>;
    } else if (section == 'accounts') {
      _accounts = entry.primary as List<Map<String, dynamic>>;
      _mappings = entry.secondary as List<Map<String, dynamic>>;
    } else if (const {
      'trial_balance',
      'profit_loss',
      'balance_sheet',
      'cash_flow',
    }.contains(section)) {
      _statement = entry.primary as Map<String, dynamic>;
    } else {
      _rows = entry.primary as List<Map<String, dynamic>>;
    }
  }

  void _invalidateLoadCache() {
    _loadCache.clear();
  }

  Future<void> _load({bool force = false}) async {
    final section = _section;
    final from = _from;
    final to = _to;
    final query = _search.text.trim();
    final cacheKey = _loadCacheKey(
      section: section,
      from: from,
      to: to,
      query: query,
    );
    final request = ++_loadGeneration;

    if (!force) {
      final cached = _loadCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.loadedAt) < _loadCacheTtl) {
        if (!mounted || request != _loadGeneration) return;
        setState(() {
          _applyLoadEntry(section, cached);
          _loading = false;
          _error = null;
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      late Object primary;
      Object? secondary;

      if (section == 'overview') {
        final values = await Future.wait<dynamic>([
          _service.summary(
            tenantId: widget.session.business.id,
            from: from,
            to: to,
          ),
          _service.gstSummary(
            tenantId: widget.session.business.id,
            from: from,
            to: to,
          ),
        ]);
        primary = values[0] as AccountingSummary;
        secondary = values[1] as Map<String, dynamic>;
      } else if (section == 'accounts') {
        final values = await Future.wait<dynamic>([
          _service.accounts(tenantId: widget.session.business.id),
          _service.mappings(tenantId: widget.session.business.id),
        ]);
        primary = values[0] as List<Map<String, dynamic>>;
        secondary = values[1] as List<Map<String, dynamic>>;
      } else if (const {
        'trial_balance',
        'profit_loss',
        'balance_sheet',
        'cash_flow',
      }.contains(section)) {
        primary = await _service.statement(
          tenantId: widget.session.business.id,
          statement: section,
          from: from,
          to: to,
        );
      } else {
        primary = await _service.register(
          tenantId: widget.session.business.id,
          register: section,
          from: from,
          to: to,
          query: query,
        );
      }

      final entry = _AccountingLoadCacheEntry(
        loadedAt: DateTime.now(),
        primary: primary,
        secondary: secondary,
      );
      _loadCache[cacheKey] = entry;

      if (!mounted || request != _loadGeneration) return;
      setState(() {
        _applyLoadEntry(section, entry);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _loadGeneration) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _export(String format) async {
    if (_exporting || _loading) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _exportService.buildPdf(
        businessName: widget.session.business.name,
        currencyCode: widget.session.currencyCode,
        section: _section,
        sectionLabel: _sectionLabel(_section),
        from: _from,
        to: _to,
        summary: _summary,
        gst: _gst,
        accounts: _accounts,
        rows: _rows,
        statement: _statement,
      );
      if (format == 'print') {
        await _exportService.printReport(
          bytes: bytes,
          name: '${widget.session.business.name} - ${_sectionLabel(_section)}',
        );
      } else if (format == 'xlsx') {
        await _exportService.saveExcel(
          businessName: widget.session.business.name,
          currencyCode: widget.session.currencyCode,
          section: _section,
          sectionLabel: _sectionLabel(_section),
          from: _from,
          to: _to,
          summary: _summary,
          gst: _gst,
          accounts: _accounts,
          rows: _rows,
          statement: _statement,
        );
      } else {
        await _exportService.savePdf(
          bytes: bytes,
          businessName: widget.session.business.name,
          section: _section,
          from: _from,
          to: _to,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              format == 'print'
                  ? 'Print dialog opened.'
                  : '${format.toUpperCase()} created.',
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
        _invalidateLoadCache();
        _load(force: true);
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
    final mappingByKey = <String, Map<String, dynamic>>{
      for (final mapping in _mappings)
        if ((mapping['mapping_key']?.toString() ?? '').isNotEmpty)
          mapping['mapping_key'].toString(): mapping,
    };
    final activeAccountOptions = _accounts
        .where((account) => account['active'] != false)
        .map(
          (account) => SearchableSelectOption<String>(
            value: account['id'].toString(),
            label: '${account['code']} \u2022 ${account['name']}',
            subtitle: account['account_type']?.toString(),
            searchText:
                '${account['code']} ${account['name']} ${account['account_type'] ?? ''}',
          ),
        )
        .toList(growable: false);
    final selected = <String, String>{};
    for (final key in keys) {
      final row = mappingByKey[key.$1];
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
                  return SearchableSelect<String>(
                    value: selected[entry.$1],
                    labelText: entry.$2,
                    isRequired: true,
                    hintText: 'Search account code, name or type',
                    prefixIcon: Icons.account_balance_outlined,
                    options: activeAccountOptions,
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
      _invalidateLoadCache();
      await _load(force: true);
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
      _invalidateLoadCache();
      await _load(force: true);
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
      _invalidateLoadCache();
      await _load(force: true);
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
    final scheme = Theme.of(context).colorScheme;

    if (compact) {
      return SizedBox(
        height: 40,
        child: DropdownButtonFormField<String>(
          initialValue: _section,
          isExpanded: true,
          isDense: true,
          decoration: const InputDecoration(
            labelText: 'Accounting section',
            prefixIcon: Icon(Icons.account_balance_outlined, size: 18),
          ),
          items: _sections
              .map(
                (item) => DropdownMenuItem(
                  value: item.$1,
                  child: Row(
                    children: [
                      Icon(item.$3, size: 16),
                      const SizedBox(width: 8),
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
        ),
      );
    }

    return Container(
      width: 190,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(11),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: scheme.surfaceContainerHighest.withValues(alpha: .55),
            child: const Row(
              children: [
                Icon(Icons.account_balance_outlined, size: 16),
                SizedBox(width: 7),
                Text(
                  'ACCOUNTING',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
              itemCount: _sections.length,
              itemBuilder: (context, index) {
                final item = _sections[index];
                final selected = item.$1 == _section;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: selected
                        ? scheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(7),
                      onTap: () {
                        if (selected) return;
                        setState(() => _section = item.$1);
                        _load();
                      },
                      child: SizedBox(
                        height: 32,
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 20,
                              decoration: BoxDecoration(
                                color: selected
                                    ? scheme.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Icon(
                              item.$3,
                              size: 15,
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                item.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: selected
                                      ? scheme.onPrimaryContainer
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;

          final workspace = Column(
            children: [
              _accountingTopBar(),
              const SizedBox(height: 6),
              if (compact) ...[
                _sectionNavigation(compact: true),
                const SizedBox(height: 6),
              ],
              if (_showRegisterSearch) ...[
                _accountingSearchBar(),
                const SizedBox(height: 6),
              ],
              Expanded(child: _body()),
            ],
          );

          if (compact) return workspace;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionNavigation(compact: false),
              const SizedBox(width: 8),
              Expanded(child: workspace),
            ],
          );
        },
      ),
    );
  }

  bool get _showRegisterSearch => !const {
    'overview',
    'accounts',
    'trial_balance',
    'profit_loss',
    'balance_sheet',
    'cash_flow',
  }.contains(_section);

  Widget _accountingTopBar() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 27,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 205,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Accounting',
                  maxLines: 1,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
                ),
                Text(
                  _sectionLabel(_section),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _accountingDateButton(
                  label: 'From',
                  value: _date(_from),
                  icon: Icons.calendar_today_outlined,
                  onPressed: () => _pickDate(from: true),
                ),
                const SizedBox(width: 5),
                _accountingDateButton(
                  label: 'To',
                  value: _date(_to),
                  icon: Icons.event_outlined,
                  onPressed: () => _pickDate(from: false),
                ),
                const SizedBox(width: 5),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _load(force: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
                const SizedBox(width: 2),
                Tooltip(
                  message: 'Finance Controls',
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            FinanceControlsScreen(session: widget.session),
                      ),
                    ),
                    icon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 18,
                    ),
                  ),
                ),
                if (_section == 'journal' && _canJournal) ...[
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _loading ? null : _postJournal,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Journal'),
                  ),
                ],
                const SizedBox(width: 5),
                PopupMenuButton<String>(
                  tooltip: 'Print / Export',
                  enabled: !_exporting && !_loading,
                  onSelected: _export,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'print',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.print_outlined, size: 18),
                        title: Text('Print'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'pdf',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.picture_as_pdf_outlined, size: 18),
                        title: Text('Save PDF'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'xlsx',
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.table_view_outlined, size: 18),
                        title: Text('Save Excel'),
                      ),
                    ),
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
                          const Icon(Icons.ios_share_outlined, size: 16),
                        const SizedBox(width: 5),
                        const Text(
                          'Export',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountingDateButton({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 8)),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountingSearchBar() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: TextField(
        controller: _search,
        onSubmitted: (_) => _load(force: true),
        decoration: InputDecoration(
          hintText:
              'Search invoice, product/SKU, party, account or reference...',
          prefixIcon: const Icon(Icons.search, size: 17),
          suffixIcon: IconButton(
            tooltip: 'Search',
            visualDensity: VisualDensity.compact,
            onPressed: () => _load(force: true),
            icon: const Icon(Icons.arrow_forward, size: 17),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
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
            OutlinedButton(
              onPressed: () => _load(force: true),
              child: const Text('Retry'),
            ),
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
    final summary = _summary;
    if (summary == null) {
      return const Center(child: Text('No accounting summary.'));
    }

    final cards = <(String, String, IconData)>[
      ('Revenue', _money(summary.revenue), Icons.trending_up),
      ('COGS', _money(summary.costOfGoodsSold), Icons.inventory_2_outlined),
      ('Gross Profit', _money(summary.grossProfit), Icons.show_chart),
      ('Expenses', _money(summary.operatingExpenses), Icons.payments_outlined),
      (
        'Net Profit',
        _money(summary.netOperatingProfit),
        Icons.account_balance_wallet_outlined,
      ),
      ('Receivables', _money(summary.receivables), Icons.call_received),
      ('Payables', _money(summary.payables), Icons.call_made),
      ('Inventory', _money(summary.inventoryValue), Icons.warehouse_outlined),
    ];

    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 4
            : constraints.maxWidth >= 680
            ? 3
            : 2;
        const gap = 6.0;
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: cards
                      .map(
                        (item) => SizedBox(
                          width: itemWidth,
                          child: _MetricCard(
                            label: item.$1,
                            value: item.$2,
                            icon: item.$3,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: LayoutBuilder(
                builder: (context, strip) {
                  final gstItems = <(String, String)>[
                    ('Taxable Sales', _money(_gst['taxable_sales'])),
                    ('Output GST', _money(_gst['output_gst'])),
                    ('Input GST', _money(_gst['input_gst'])),
                    ('Net GST Payable', _money(_gst['net_gst_payable'])),
                  ];

                  if (strip.maxWidth < 600) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: gstItems
                            .map(
                              (item) => SizedBox(
                                width: 150,
                                child: _MiniMetric(item.$1, item.$2),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  }

                  return Row(
                    children: [
                      for (var i = 0; i < gstItems.length; i++) ...[
                        if (i > 0)
                          Container(
                            width: 1,
                            height: 30,
                            color: scheme.outlineVariant,
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            child: _MiniMetric(gstItems[i].$1, gstItems[i].$2),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
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
              const SizedBox(height: 10),
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

    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (_canManage) ...[
          SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _editMappings,
                  icon: const Icon(Icons.hub_outlined, size: 16),
                  label: const Text('Mappings'),
                ),
                const SizedBox(width: 5),
                FilledButton.icon(
                  onPressed: () => _editAccount(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Account'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;

              return Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (!compact)
                      Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        color: scheme.surfaceContainerHighest,
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Code',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Text(
                                'Account',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Type',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Balance',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            SizedBox(width: 84),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _accounts.length,
                        itemBuilder: (context, index) {
                          final account = _accounts[index];
                          return _accountRow(account, compact: compact);
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _accountRow(Map<String, dynamic> account, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final archived = account['active'] == false;
    final system = account['is_system'] == true;

    if (compact) {
      return Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Container(
              width: 29,
              height: 29,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                (account['code']?.toString().isNotEmpty == true)
                    ? account['code'].toString().substring(0, 1)
                    : 'A',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${account['code'] ?? ''} | ${account['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${account['account_type'] ?? ''}'
                    '${system ? ' | System' : ''}'
                    '${archived ? ' | Archived' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _money(account['balance']),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
            if (_canManage)
              IconButton(
                tooltip: 'Edit account',
                visualDensity: VisualDensity.compact,
                onPressed: () => _editAccount(account),
                icon: const Icon(Icons.edit_outlined, size: 16),
              ),
          ],
        ),
      );
    }

    Widget cell(
      Widget child,
      int flex, {
      Alignment alignment = Alignment.centerLeft,
    }) => Expanded(
      flex: flex,
      child: Align(alignment: alignment, child: child),
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          cell(
            Text(
              account['code']?.toString() ?? '',
              maxLines: 1,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            2,
          ),
          cell(
            Row(
              children: [
                Expanded(
                  child: Text(
                    account['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (system)
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Text(
                      'SYSTEM',
                      style: TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            5,
          ),
          cell(
            Text(
              account['account_type']?.toString().toUpperCase() ?? '',
              maxLines: 1,
              style: const TextStyle(fontSize: 8.5),
            ),
            2,
          ),
          cell(
            Text(
              _money(account['balance']),
              maxLines: 1,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: archived ? scheme.onSurfaceVariant : scheme.onSurface,
              ),
            ),
            2,
            alignment: Alignment.centerRight,
          ),
          SizedBox(
            width: 84,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (archived)
                  Tooltip(
                    message: 'Archived',
                    child: Icon(
                      Icons.archive_outlined,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (_canManage) ...[
                  IconButton(
                    tooltip: 'Edit account',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _editAccount(account),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                  ),
                  if (!system && !archived)
                    IconButton(
                      tooltip: 'Archive account',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _archiveAccount(account),
                      icon: const Icon(Icons.archive_outlined, size: 15),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerView() {
    if (_rows.isEmpty) {
      return const Center(child: Text('No matching accounting entries.'));
    }

    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final veryCompact = constraints.maxWidth < 620;

        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (!veryCompact)
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  color: scheme.surfaceContainerHighest,
                  child: _registerHeader(compact: compact),
                ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: _rows.length,
                  itemBuilder: (context, index) => _registerRow(
                    _rows[index],
                    compact: compact,
                    veryCompact: veryCompact,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _registerHeader({required bool compact}) {
    Widget cell(String label, int flex, {TextAlign align = TextAlign.left}) =>
        Expanded(
          flex: flex,
          child: Text(
            label,
            textAlign: align,
            maxLines: 1,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
          ),
        );

    return Row(
      children: [
        cell('Date', 2),
        cell('Reference', 3),
        cell('Description / Party', 5),
        if (!compact) cell('Location / User', 3),
        cell('Debit', 2, align: TextAlign.right),
        cell('Credit', 2, align: TextAlign.right),
      ],
    );
  }

  Widget _registerRow(
    Map<String, dynamic> row, {
    required bool compact,
    required bool veryCompact,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final debit = (row['debit'] as num?)?.toDouble() ?? 0;
    final credit = (row['credit'] as num?)?.toDouble() ?? 0;

    if (veryCompact) {
      return Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 16),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${row['reference'] ?? '-'} | ${row['description'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${row['entry_date'] ?? ''} | ${row['party'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (debit.abs() > .0001)
                  Text(
                    'DR ${_money(debit)}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                if (credit.abs() > .0001)
                  Text(
                    'CR ${_money(credit)}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    Widget cell(
      Widget child,
      int flex, {
      Alignment alignment = Alignment.centerLeft,
    }) => Expanded(
      flex: flex,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: child,
        ),
      ),
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 43),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          cell(
            Text(
              row['entry_date']?.toString() ?? '',
              maxLines: 1,
              style: const TextStyle(fontSize: 9),
            ),
            2,
          ),
          cell(
            Text(
              row['reference']?.toString() ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            3,
          ),
          cell(
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['description']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9.5),
                ),
                Text(
                  row['party']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            5,
          ),
          if (!compact)
            cell(
              Text(
                '${row['location_code'] ?? ''}'
                '${row['user_name']?.toString().isNotEmpty == true ? ' | ${row['user_name']}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8.5),
              ),
              3,
            ),
          cell(
            debit.abs() > .0001
                ? Text(
                    _money(debit),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : const SizedBox.shrink(),
            2,
            alignment: Alignment.centerRight,
          ),
          cell(
            credit.abs() > .0001
                ? Text(
                    _money(credit),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : const SizedBox.shrink(),
            2,
            alignment: Alignment.centerRight,
          ),
        ],
      ),
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

    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          height: 56,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 620) {
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: metrics.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 5),
                  itemBuilder: (context, index) => SizedBox(
                    width: 155,
                    child: _StatementMetric(
                      metrics[index].$1,
                      metrics[index].$2,
                    ),
                  ),
                );
              }

              return Row(
                children: [
                  for (var i = 0; i < metrics.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      child: _StatementMetric(metrics[i].$1, metrics[i].$2),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: rows.isEmpty
                ? const Center(
                    child: Text('No accounting balances for this period.'),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 680;

                      return Column(
                        children: [
                          if (!compact)
                            Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              color: scheme.surfaceContainerHighest,
                              child: Row(
                                children: [
                                  const Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Code',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const Expanded(
                                    flex: 5,
                                    child: Text(
                                      'Account',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Type',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      _section == 'trial_balance'
                                          ? 'Debit / Credit'
                                          : _section == 'cash_flow'
                                          ? 'In / Out / Net'
                                          : 'Amount',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: rows.length,
                              itemBuilder: (context, index) =>
                                  _statementRow(rows[index], compact: compact),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _statementRow(Map<String, dynamic> row, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final code = row['code']?.toString() ?? '';
    final name = row['name']?.toString() ?? '';
    final type = row['account_type']?.toString().toUpperCase() ?? '';

    String value;
    String secondary = '';
    if (_section == 'trial_balance') {
      value = 'DR ${_money(row['debit'])} | CR ${_money(row['credit'])}';
    } else if (_section == 'cash_flow') {
      value = _money(row['net_change']);
      secondary = 'In ${_money(row['inflow'])} | Out ${_money(row['outflow'])}';
    } else {
      value = _money(row['amount']);
    }

    if (compact) {
      return Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$code | $name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    secondary.isEmpty ? type : '$type | $secondary',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.2,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              code,
              maxLines: 1,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              type,
              maxLines: 1,
              style: TextStyle(fontSize: 8.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (secondary.isNotEmpty)
                  Text(
                    secondary,
                    maxLines: 1,
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 70,
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
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
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

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;

  const _MiniMetric(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 8.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _StatementMetric extends StatelessWidget {
  final String label;
  final String value;

  const _StatementMetric(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 8.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
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
                          child: SearchableSelect<String>(
                            value: line.accountId,
                            labelText: 'Account ${index + 1}',
                            isRequired: true,
                            hintText: 'Search account code, name or type',
                            prefixIcon: Icons.account_balance_outlined,
                            options: widget.accounts
                                .map(
                                  (a) => SearchableSelectOption<String>(
                                    value: a['id'].toString(),
                                    label: '${a['code']} • ${a['name']}',
                                    subtitle: a['account_type']?.toString(),
                                    searchText:
                                        '${a['code']} ${a['name']} ${a['account_type'] ?? ''}',
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
