import 'dart:async';

import 'package:flutter/material.dart';

import 'thq_accounting_models.dart';

const thqAccountingSections = <String, String>{
  'overview': 'Overview',
  'sales': 'Sales Register',
  'purchases': 'Purchase Register',
  'cash': 'Cash Book',
  'bank': 'Bank / UPI / Card',
  'customers': 'Customer Ledger',
  'suppliers': 'Supplier Ledger',
  'journal': 'Journal',
  'general_ledger': 'General Ledger',
  'trial_balance': 'Trial Balance',
  'profit_loss': 'Profit & Loss',
  'balance_sheet': 'Balance Sheet',
  'cash_flow': 'Cash Flow',
  'gst': 'GST Register',
};

typedef ThqAccountingLoader =
    Future<ThqAccountingResult> Function(ThqAccountingQuery);
typedef ThqAccountingExporter =
    Future<void> Function(ThqAccountingQuery, String);

/// Shared read-only accounting workspace. All financial writes remain in the apps.
class ThqAccountingWorkspace extends StatefulWidget {
  final String businessId;
  final String scopeKey;
  final String scopeLabel;
  final String currency;
  final ThqAccountingLoader load;
  final ThqAccountingExporter export;
  final Future<void> Function(Map<String, dynamic>) openSource;
  final Future<void> Function(Map<String, dynamic>)? openHistory;
  final VoidCallback? openControls;
  const ThqAccountingWorkspace({
    super.key,
    required this.businessId,
    required this.scopeKey,
    required this.scopeLabel,
    required this.currency,
    required this.load,
    required this.export,
    required this.openSource,
    this.openHistory,
    this.openControls,
  });
  @override
  State<ThqAccountingWorkspace> createState() => _ThqAccountingWorkspaceState();
}

class _ThqAccountingWorkspaceState extends State<ThqAccountingWorkspace> {
  late ThqAccountingQuery _query;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, ThqAccountingQuery> _saved = {};
  final List<ThqAccountingQuery> _trail = [];
  ThqAccountingResult? _result;
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false, _exporting = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _query = ThqAccountingQuery(
      report: 'overview',
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month, now.day),
    );
    _reload();
  }

  @override
  void didUpdateWidget(covariant ThqAccountingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.businessId != widget.businessId ||
        oldWidget.scopeKey != widget.scopeKey) {
      _debounce?.cancel();
      _saved.clear();
      _trail.clear();
      _query = _query.copyWith(filters: {}, offset: 0);
      _result = null;
      _reload();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final captured = _query;
    final request = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.load(captured);
      if (!mounted || request != _generation) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _generation) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _change(ThqAccountingQuery query) {
    _debounce?.cancel();
    setState(() {
      _query = query;
      _search.text = query.search;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _reload();
  }

  void _section(
    String report, {
    Map<String, String>? filters,
    bool drill = false,
    DateTime? from,
  }) {
    _saved[_query.report] = _query;
    if (drill) _trail.add(_query);
    final saved = _saved[report];
    _change(
      ThqAccountingQuery(
        report: report,
        from: from ?? _query.from,
        to: _query.to,
        search: drill ? '' : saved?.search ?? '',
        filters: filters ?? saved?.filters ?? {},
        sortKey: drill ? null : saved?.sortKey,
        descending: saved?.descending ?? false,
      ),
    );
  }

  void _filter(String key, String? value) {
    final filters = Map<String, String>.from(_query.filters);
    if (value == null || value.isEmpty) {
      filters.remove(key);
    } else {
      filters[key] = value;
    }
    _change(_query.copyWith(filters: filters, offset: 0));
  }

  Future<void> _date(bool first) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: first ? _query.from : _query.to,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    _change(
      _query.copyWith(
        from: first
            ? picked
            : (_query.from.isAfter(picked) ? picked : _query.from),
        to: first ? (_query.to.isBefore(picked) ? picked : _query.to) : picked,
        offset: 0,
      ),
    );
  }

  String _money(dynamic x) {
    if (x == null) return '—';
    final n = x is num ? x : num.tryParse(x.toString());
    if (n == null) return '—';
    return '${widget.currency == 'INR' ? '₹' : '${widget.currency} '}${n.toStringAsFixed(2)}';
  }

  String _day(dynamic x) {
    final d = x is DateTime ? x : DateTime.tryParse(x?.toString() ?? '');
    return d == null
        ? '—'
        : '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  String _cell(dynamic x, ThqAccountingColumn c) => c.numeric
      ? _money(x)
      : c.type == 'date'
      ? _day(x)
      : x?.toString() ?? '—';
  Future<void> _export(String format) async {
    if (_exporting || _loading) return;
    final snapshot = _query;
    setState(() => _exporting = true);
    try {
      await widget.export(snapshot, format);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _filters() async {
    final filters = Map<String, String>.from(_query.filters);
    final min = TextEditingController(text: filters['amount_min'] ?? '');
    final max = TextEditingController(text: filters['amount_max'] ?? '');

    final group = TextEditingController(text: filters['account_group'] ?? '');
    final rate = TextEditingController(text: filters['gst_rate'] ?? '');
    var sort = _query.sortKey;
    var desc = _query.descending;
    String? validation;
    void setFilter(String key, String? value) {
      if (value == null || value.isEmpty) {
        filters.remove(key);
      } else {
        filters[key] = value;
      }
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          Widget select(String label, String key, List<String> values) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<String>(
                  initialValue: values.contains(filters[key])
                      ? filters[key]
                      : '',
                  isExpanded: true,
                  decoration: InputDecoration(labelText: label),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All')),
                    ...values.map(
                      (x) => DropdownMenuItem(
                        value: x,
                        child: Text(x.replaceAll('_', ' ')),
                      ),
                    ),
                  ],
                  onChanged: (v) => update(() => setFilter(key, v)),
                ),
              );
          return AlertDialog(
            title: const Text('Filter / Sort'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_query.report == 'journal')
                      select('Posting status', 'status', [
                        'posted',
                        'reversed',
                      ]),
                    if (_query.report == 'journal')
                      select('Journal balance', 'balance_status', [
                        'Balanced',
                        'Unbalanced',
                      ]),
                    if (['sales', 'purchases'].contains(_query.report))
                      select('Payment status', 'payment_status', [
                        'Paid',
                        'Partial',
                        'Unpaid',
                      ]),
                    if (['customers', 'suppliers'].contains(_query.report))
                      select('Balance status', 'payment_status', [
                        'Outstanding',
                        'Settled',
                        'Advance / credit',
                      ]),
                    if (['sales', 'purchases'].contains(_query.report))
                      select('Overdue', 'overdue', ['true', 'false']),
                    if (['journal', 'cash', 'bank'].contains(_query.report))
                      select('Payment method', 'payment_method', [
                        'cash',
                        'bank',
                        'upi',
                        'card',
                      ]),
                    if ([
                      'journal',
                      'cash',
                      'bank',
                      'general_ledger',
                    ].contains(_query.report))
                      select(
                        'Source / module',
                        'source_type',
                        (_result?.options['sources'] as List? ?? [])
                            .map((x) => x.toString())
                            .toList(),
                      ),
                    if ([
                      'trial_balance',
                      'profit_loss',
                      'balance_sheet',
                    ].contains(_query.report))
                      TextField(
                        controller: group,
                        decoration: const InputDecoration(
                          labelText: 'Account group',
                        ),
                      ),
                    if (_query.report == 'gst') ...[
                      select('Sales / purchases', 'direction', [
                        'outward',
                        'inward',
                      ]),
                      select('Party registration', 'registration_status', [
                        'Registered',
                        'Unregistered',
                      ]),
                      select('Interstate', 'interstate', ['true', 'false']),
                      TextField(
                        controller: rate,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'GST rate',
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: min,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Minimum amount',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: max,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Maximum amount',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: sort ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sort by'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Accounting order'),
                        ),
                        ...(_result?.columns ?? []).map(
                          (c) => DropdownMenuItem(
                            value: c.key,
                            child: Text(c.label),
                          ),
                        ),
                      ],
                      onChanged: (v) => update(() => sort = v == '' ? null : v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Descending'),
                      value: desc,
                      onChanged: (v) => update(() => desc = v),
                    ),
                    if (validation != null)
                      Text(
                        validation!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  filters.clear();
                  sort = null;
                  desc = false;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Clear'),
              ),
              FilledButton(
                onPressed: () {
                  final lo = num.tryParse(min.text.trim()),
                      hi = num.tryParse(max.text.trim());
                  if ((min.text.isNotEmpty && lo == null) ||
                      (max.text.isNotEmpty && hi == null) ||
                      (lo != null && hi != null && lo > hi) ||
                      (rate.text.isNotEmpty &&
                          num.tryParse(rate.text) == null)) {
                    update(
                      () => validation =
                          'Enter valid amounts/rate and a minimum no greater than maximum.',
                    );
                    return;
                  }
                  setFilter('amount_min', min.text.trim());
                  setFilter('amount_max', max.text.trim());
                  if ([
                    'journal',
                    'cash',
                    'bank',
                    'general_ledger',
                  ].contains(_query.report))
                    if ([
                      'trial_balance',
                      'profit_loss',
                      'balance_sheet',
                    ].contains(_query.report))
                      setFilter('account_group', group.text.trim());
                  if (_query.report == 'gst')
                    setFilter('gst_rate', rate.text.trim());
                  Navigator.pop(ctx, true);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    min.dispose();
    max.dispose();

    group.dispose();
    rate.dispose();
    if (accepted == true && mounted)
      _change(
        _query.copyWith(
          filters: filters,
          sortKey: sort,
          clearSort: sort == null,
          descending: desc,
          offset: 0,
        ),
      );
  }

  Widget _selector(String key, List<Map<String, dynamic>> items, String label) {
    final selected = _query.filters[key];
    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$key:${selected ?? ''}:$label'),
        initialValue: items.any((x) => x['id'] == selected) ? selected : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          const DropdownMenuItem(value: '', child: Text('Choose / All')),
          ...items.map(
            (x) => DropdownMenuItem(
              value: x['id'].toString(),
              child: Text(
                '${x['code'] == null ? '' : '${x['code']} · '}${x['name']}${x['active'] == false ? ' (archived)' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: (v) => _filter(key, v),
      ),
    );
  }

  Widget _toolbar() {
    final options = _result?.options ?? {};
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => _date(true),
          icon: const Icon(Icons.date_range, size: 16),
          label: Text('From ${_day(_query.from)}'),
        ),
        OutlinedButton(
          onPressed: () => _date(false),
          child: Text('To ${_day(_query.to)}'),
        ),
        SizedBox(
          width: 270,
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search reference, party, account, amount…',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _generation++;
              setState(() {
                _query = _query.copyWith(search: v, offset: 0);
                _loading = true;
              });
              _debounce = Timer(const Duration(milliseconds: 300), _reload);
            },
            onSubmitted: (_) => _reload(),
          ),
        ),
        if (['customers', 'suppliers'].contains(_query.report))
          _selector(
            'party_id',
            accountingMaps(options[_query.report]),
            _query.report == 'customers' ? 'Customer' : 'Supplier',
          ),
        if ([
          'general_ledger',
          'cash',
          'bank',
          'journal',
        ].contains(_query.report))
          _selector(
            'account_id',
            accountingMaps(options['accounts'])
                .where(
                  (x) =>
                      ['general_ledger', 'journal'].contains(_query.report) ||
                      (_query.report == 'cash'
                          ? x['method'] == 'cash'
                          : ['bank', 'upi', 'card'].contains(x['method'])),
                )
                .toList(),
            'Account',
          ),
        if (_query.report == 'journal')
          _selector('party_id', accountingMaps(options['parties']), 'Party'),
        OutlinedButton.icon(
          onPressed: _filters,
          icon: const Icon(Icons.tune, size: 16),
          label: Text(
            'Filter / Sort${_query.filters.isEmpty ? '' : ' (${_query.filters.length})'}',
          ),
        ),
        IconButton(
          onPressed: _loading ? null : _reload,
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
        PopupMenuButton<String>(
          enabled: !_loading && !_exporting,
          tooltip: 'Export all matching records',
          onSelected: _export,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'xlsx', child: Text('Excel · all matching')),
            PopupMenuItem(value: 'pdf', child: Text('PDF · all matching')),
            PopupMenuItem(value: 'print', child: Text('Print · all matching')),
          ],
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_trail.isNotEmpty)
                IconButton(
                  tooltip: 'Back to previous report',
                  onPressed: () => _change(_trail.removeLast()),
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Text(
                  'Accounting · ${widget.scopeLabel}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (widget.openControls != null)
                TextButton.icon(
                  onPressed: widget.openControls,
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Accounts / Controls'),
                ),
            ],
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: thqAccountingSections.entries
                  .map(
                    (x) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(x.value),
                        selected: _query.report == x.key,
                        onSelected: (_) => _section(x.key),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          _toolbar(),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              backgroundColor: colors.errorContainer,
              actions: [
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          if (!_loading && _error == null && _result != null) ...[
            if (_result!.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: _result!.summary
                      .map(
                        (x) => Text(
                          '${x['label']}: ${_money(x['value'])}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color:
                                (x['label'].toString().toLowerCase().contains(
                                      'difference',
                                    ) &&
                                    (x['value'] as num).abs() > .005)
                                ? colors.error
                                : colors.onSurface,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (_query.report == 'trial_balance' &&
                _result!.summary.length >= 4)
              Text(
                'Total Debit ${_money(_result!.summary[0]['value'])} ${(_result!.summary[2]['value'] as num).abs() <= .005 ? '=' : '≠'} Total Credit ${_money(_result!.summary[1]['value'])} ${(_result!.summary[2]['value'] as num).abs() <= .005 && (_result!.summary[3]['value'] as num).abs() <= .005 ? '✓' : '— ACCOUNTING WARNING: balances differ'}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:
                      (_result!.summary[2]['value'] as num).abs() > .005 ||
                          (_result!.summary[3]['value'] as num).abs() > .005
                      ? colors.error
                      : colors.onSurface,
                ),
              ),
            if (_query.report == 'general_ledger')
              const Text(
                'Debit balances are positive; credit balances are negative.',
                style: TextStyle(fontSize: 11),
              ),
            if ([
              'customers',
              'suppliers',
              'general_ledger',
              'cash',
              'bank',
            ].contains(_query.report))
              Text(
                'Opening and closing are for the selected party/account. Balances remain in accounting order when searching or sorting.',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            if (_query.report == 'gst' &&
                _result!.data['tax_mode'] != 'gst_registered')
              Text(
                _result!.rows.isEmpty
                    ? 'GST is not enabled for this business/period. Ordinary invoices continue normally.'
                    : 'GST is not currently enabled. Historical GST evidence is shown below.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            if (_query.report == 'cash_flow')
              Text(
                _result!.context['cash_flow_basis'].toString(),
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            const SizedBox(height: 5),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? const SizedBox.shrink()
                : _body(),
          ),
          if (_result != null && !_loading && _query.report != 'overview')
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_result!.total} matching records · ${_query.offset + (_result!.rows.isEmpty ? 0 : 1)}–${_query.offset + _result!.rows.length}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: _query.offset == 0
                      ? null
                      : () => _change(
                          _query.copyWith(
                            offset: (_query.offset - _query.limit).clamp(
                              0,
                              _result!.total,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: _query.offset + _query.limit >= _result!.total
                      ? null
                      : () => _change(
                          _query.copyWith(offset: _query.offset + _query.limit),
                        ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    if (_query.report == 'overview') return _overview(result);
    if (['general_ledger', 'customers', 'suppliers'].contains(_query.report) &&
        _query.filters[_query.report == 'general_ledger'
                ? 'account_id'
                : 'party_id'] ==
            null)
      return const Center(
        child: Text(
          'Choose an account or party above to see its full history.',
        ),
      );
    if (result.rows.isEmpty)
      return const Center(child: Text('No matching records.'));
    if (_query.report == 'journal')
      return ListView.builder(
        controller: _scroll,
        itemCount: result.rows.length,
        itemBuilder: (ctx, i) => _journal(result.rows[i]),
      );
    if (['profit_loss', 'balance_sheet', 'cash_flow'].contains(_query.report))
      return _statement(result);
    return _table(result.rows, result.columns);
  }

  Widget _overview(ThqAccountingResult result) => LayoutBuilder(
    builder: (ctx, box) => SingleChildScrollView(
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: result.rows
                .map(
                  (r) => SizedBox(
                    width:
                        ((box.maxWidth - 16) /
                                (box.maxWidth > 900
                                    ? 5
                                    : box.maxWidth > 580
                                    ? 3
                                    : 2))
                            .clamp(130, 280),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        onTap: () =>
                            _section(r['target'].toString(), drill: true),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['label'].toString(),
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _money(r['amount']),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                r['basis'].toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          ...result.alerts.map(
            (r) => Card(
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.info_outline,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(r['label'].toString()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _section(
                  r['target'].toString(),
                  filters: accountingMap(
                    r['filters'],
                  ).map((k, v) => MapEntry(k, v.toString())),
                  drill: true,
                  from: DateTime.tryParse(r['from']?.toString() ?? ''),
                ),
              ),
            ),
          ),
          if (result.alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                'No alerts from the checks available for this scope and period.',
              ),
            ),
        ],
      ),
    ),
  );
  Widget _journal(Map<String, dynamic> r) {
    final lines = accountingMaps(r['lines']);
    final balanced = r['balance_status'] == 'Balanced';
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ExpansionTile(
        key: ValueKey(r['journal_id']),
        maintainState: true,
        title: Text(
          '${r['reference']} · ${r['type']} · ${r['party']}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_day(r['date'])} · ${r['entry_number']} · ${r['status']} · ${r['balance_status']}',
          style: TextStyle(
            fontSize: 11,
            color: balanced
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.error,
          ),
        ),
        trailing: Text(
          _money(r['amount']),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Account')),
                    const SizedBox(
                      width: 100,
                      child: Text('Debit', textAlign: TextAlign.right),
                    ),
                    const SizedBox(
                      width: 100,
                      child: Text('Credit', textAlign: TextAlign.right),
                    ),
                  ],
                ),
                ...lines.map(
                  (l) => InkWell(
                    onTap: () => _section(
                      'general_ledger',
                      filters: {'account_id': l['account_id'].toString()},
                      drill: true,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l['account_code']} · ${l['account_name']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              _money(l['debit']),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              _money(l['credit']),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text(
                        _money(r['debit']),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text(
                        _money(r['credit']),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  children: [
                    if (r['document_id'] != null)
                      TextButton(
                        onPressed: () => _openOriginal(r),
                        child: const Text('Original document'),
                      ),
                    TextButton(
                      onPressed: () => _details(r),
                      child: const Text('Details / reversal links'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOriginal(Map<String, dynamic> row) async {
    try {
      await widget.openSource(row);
      if (mounted) await _reload();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open source: $error')),
        );
    }
  }

  Widget _statement(ThqAccountingResult result) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in result.rows) {
      groups
          .putIfAbsent(row['group']?.toString() ?? 'Other', () => [])
          .add(row);
    }
    Widget account(Map<String, dynamic> r) => ListTile(
      dense: true,
      title: Text(
        r['account_name']?.toString() ?? r['reference']?.toString() ?? '',
      ),
      subtitle: Text(r['description']?.toString() ?? ''),
      trailing: Text(_money(r['amount'])),
      onTap: () => r['account_id'] != null && _query.report != 'cash_flow'
          ? _section(
              'general_ledger',
              filters: {'account_id': r['account_id'].toString()},
              drill: true,
              from: _query.report == 'balance_sheet' ? DateTime(1900) : null,
            )
          : _details(r),
    );
    List<Widget> children(String group, List<Map<String, dynamic>> rows) {
      if (_query.report != 'balance_sheet') return rows.map(account).toList();
      final subs = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        subs
            .putIfAbsent(row['subgroup']?.toString() ?? group, () => [])
            .add(row);
      }
      return subs.entries
          .map(
            (e) => ExpansionTile(
              title: Text(e.key),
              subtitle: Text(
                _money(
                  accountingMap(
                        result.data['subgroup_totals'],
                      )['$group:${e.key}'] ??
                      e.value.fold<num>(
                        0,
                        (n, r) => n + (r['amount'] as num? ?? 0),
                      ),
                ),
              ),
              children: e.value.map(account).toList(),
            ),
          )
          .toList();
    }

    return ListView(
      controller: _scroll,
      children: groups.entries
          .map(
            (e) => Card(
              child: ExpansionTile(
                title: Text(e.key),
                subtitle: Text(
                  _money(
                    accountingMap(result.data['group_totals'])[e.key] ?? 0,
                  ),
                ),
                children: children(e.key, e.value),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _table(
    List<Map<String, dynamic>> rows,
    List<ThqAccountingColumn> cols,
  ) => LayoutBuilder(
    builder: (ctx, box) {
      final compact = box.maxWidth < 760;
      if (compact)
        return ListView.builder(
          controller: _scroll,
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final r = rows[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 5),
              child: InkWell(
                onTap: () => _details(r),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 5,
                    children: cols
                        .map(
                          (c) => Text(
                            '${c.label}: ${_cell(r[c.key], c)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  [
                                    'reference',
                                    'balance',
                                    'due',
                                  ].contains(c.key)
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            );
          },
        );
      int flex(ThqAccountingColumn c) =>
          ['party', 'description', 'account_name'].contains(c.key) ? 3 : 2;
      Widget row(Map<String, dynamic> r, {bool header = false}) => Container(
        height: header ? 36 : 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: header
              ? Theme.of(ctx).colorScheme.surfaceContainerHighest
              : null,
          border: Border(
            bottom: BorderSide(color: Theme.of(ctx).colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: cols
              .map(
                (c) => Expanded(
                  flex: flex(c),
                  child: InkWell(
                    onTap: header
                        ? () => _change(
                            _query.copyWith(
                              sortKey: c.key,
                              descending: _query.sortKey == c.key
                                  ? !_query.descending
                                  : false,
                              offset: 0,
                            ),
                          )
                        : null,
                    child: Tooltip(
                      message: header ? c.label : _cell(r[c.key], c),
                      child: Text(
                        header
                            ? '${c.label}${_query.sortKey == c.key ? (_query.descending ? ' ↓' : ' ↑') : ''}'
                            : _cell(r[c.key], c),
                        textAlign: c.numeric ? TextAlign.right : TextAlign.left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              header ||
                                  [
                                    'reference',
                                    'balance',
                                    'due',
                                    'payment_status',
                                  ].contains(c.key)
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );
      return Column(
        children: [
          row({}, header: true),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: rows.length,
              itemBuilder: (ctx, i) =>
                  InkWell(onTap: () => _details(rows[i]), child: row(rows[i])),
            ),
          ),
        ],
      );
    },
  );
  Future<void> _details(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          row['reference']?.toString() ??
              row['account_name']?.toString() ??
              'Accounting details',
        ),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...(_result?.columns ?? []).map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${c.label}: ${_cell(row[c.key], c)}'),
                  ),
                ),
                if (row['description'] != null)
                  SelectableText(row['description'].toString()),
                if (row['adjustment'] != null)
                  Text('Noncash adjustment: ${_money(row['adjustment'])}'),
                ...accountingMap(row['source_details']).entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${e.key.replaceAll('_', ' ')}: ${e.value}'),
                  ),
                ),
                if (row['payment_reference'] != null)
                  Text('Payment reference: ${row['payment_reference']}'),
                ...accountingMaps(row['saved_items']).map(
                  (item) => ListTile(
                    dense: true,
                    title: Text(
                      '${item['product_name'] ?? 'Item'} · ${item['sku'] ?? ''}',
                    ),
                    subtitle: Text(
                      'Quantity ${item['quantity'] ?? ''} · Total ${_money(item['line_total'])}',
                    ),
                  ),
                ),
                if (row['accounting_status'] != null)
                  Text('Accounting: ${row['accounting_status']}'),
                if (row['reversal_of'] != null)
                  const Text(
                    'This journal reverses an earlier journal. Use the link below.',
                  ),
                ...accountingMaps(row['reversals']).map(
                  (r) => TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _section(
                        'journal',
                        filters: {'journal_id': r['journal_id'].toString()},
                        drill: true,
                        from: DateTime(1900),
                      );
                    },
                    child: Text('Reversal ${r['reference']} · ${r['status']}'),
                  ),
                ),
                if (row['snapshot'] != null) ...[
                  Text('Verification: ${row['verification']}'),
                  Text(
                    'UTGST ${_money(row['utgst'])} · Cess ${_money(row['cess'])}',
                  ),
                  Text('Tax mode: ${row['tax_mode'] ?? 'Historical / legacy'}'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (widget.openHistory != null &&
              (row['journal_id'] != null || row['source_id'] != null))
            TextButton.icon(
              onPressed: () async {
                try {
                  await widget.openHistory!(row);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Could not load audit history: $e'),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Audit history'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (row['document_id'] != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openOriginal(row);
              },
              child: const Text('Original document'),
            ),
          if (row['reversal_of'] != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _section(
                  'journal',
                  filters: {'journal_id': row['reversal_of'].toString()},
                  drill: true,
                  from: DateTime(1900),
                );
              },
              child: const Text('Original journal'),
            ),
          if (row['journal_id'] != null || row['document_id'] != null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _section(
                  'journal',
                  filters: row['document_id'] != null
                      ? {'document_id': row['document_id'].toString()}
                      : {'journal_id': row['journal_id'].toString()},
                  drill: true,
                  from: DateTime(1900),
                );
              },
              child: const Text('View Journal Entries'),
            ),
        ],
      ),
    );
  }
}
