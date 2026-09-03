import 'package:flutter/material.dart';

import '../models/accounting_summary.dart';
import '../models/client_session.dart';
import '../services/accounting_service.dart';

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

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('accounting.manage');

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    const sectionItems = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: 'overview', child: Text('Overview')),
      DropdownMenuItem(value: 'accounts', child: Text('Chart of Accounts')),
      DropdownMenuItem(value: 'sales', child: Text('Sales Register')),
      DropdownMenuItem(value: 'purchases', child: Text('Purchase Register')),
      DropdownMenuItem(value: 'cash', child: Text('Cash Book')),
      DropdownMenuItem(value: 'bank', child: Text('Bank / UPI / Card')),
      DropdownMenuItem(value: 'gst', child: Text('GST Register')),
      DropdownMenuItem(value: 'all', child: Text('General Ledger')),
    ];

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
                const SizedBox(
                  width: 135,
                  child: Text(
                    'Accounting',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: _section,
                    isExpanded: true,
                    items: sectionItems,
                    decoration: const InputDecoration(labelText: 'Workspace'),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _section = value);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(from: true),
                  icon: const Icon(Icons.calendar_today_outlined, size: 14),
                  label: Text(_date(_from)),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(from: false),
                  icon: const Icon(Icons.event_outlined, size: 14),
                  label: Text(_date(_to)),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
          ),
          if (_section != 'overview' && _section != 'accounts') ...[
            const SizedBox(height: 5),
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: TextField(
                controller: _search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: 'Search invoice, party, account or reference...',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    visualDensity: VisualDensity.compact,
                    onPressed: _load,
                    icon: const Icon(Icons.arrow_forward, size: 15),
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ],
          const SizedBox(height: 5),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: _body(),
            ),
          ),
        ],
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
                      Text(
                        _money(a['balance']),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (_canManage) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _editAccount(a),
                          icon: const Icon(Icons.edit_outlined),
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
    if (_rows.isEmpty) {
      return const Center(child: Text('No matching accounting entries.'));
    }
    return Card(
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
