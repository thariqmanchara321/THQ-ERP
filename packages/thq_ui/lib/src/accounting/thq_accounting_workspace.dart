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
  final _reportSearch = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, ThqAccountingQuery> _saved = {};
  final List<ThqAccountingQuery> _trail = [];
  final Set<String> _expandedJournals = {};
  final Set<String> _collapsedStatementSections = {};
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
    _reportSearch.text = thqAccountingSections[_query.report]!;
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
    _reportSearch.dispose();
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
      _reportSearch.text = thqAccountingSections[query.report]!;
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
    if (!drill && report == _query.report) return;
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
                        'draft',
                      ]),
                    if (_query.report == 'journal')
                      select('Journal balance', 'balance_status', [
                        'Balanced',
                        'Unbalanced',
                      ]),
                    if (['sales', 'purchases'].contains(_query.report))
                      select('Payment status', 'payment_status', [
                        'Paid',
                        'Partially Paid',
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

  IconData _reportIcon(String report) => switch (report) {
    'overview' => Icons.space_dashboard_outlined,
    'sales' => Icons.receipt_long_outlined,
    'purchases' => Icons.shopping_bag_outlined,
    'cash' => Icons.payments_outlined,
    'bank' => Icons.account_balance_outlined,
    'customers' => Icons.person_outline,
    'suppliers' => Icons.local_shipping_outlined,
    'journal' => Icons.menu_book_outlined,
    'general_ledger' => Icons.account_tree_outlined,
    'trial_balance' => Icons.balance_outlined,
    'profit_loss' => Icons.insights_outlined,
    'balance_sheet' => Icons.assessment_outlined,
    'cash_flow' => Icons.swap_vert,
    _ => Icons.percent,
  };

  Widget _navigation() => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 640;
      final picker = Tooltip(
        message: 'Choose a report · type to search',
        child: Focus(
          onFocusChange: (focused) {
            if (focused) {
              _reportSearch.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _reportSearch.text.length,
              );
            } else {
              _reportSearch.text = thqAccountingSections[_query.report]!;
            }
          },
          child: DropdownMenu<String>(
            key: ValueKey('accounting-report-${_query.report}'),
            controller: _reportSearch,
            initialSelection: _query.report,
            width: wide ? 270 : null,
            expandedInsets: wide ? null : EdgeInsets.zero,
            menuHeight: 420,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            hintText: 'Find a report…',
            leadingIcon: Icon(_reportIcon(_query.report), size: 18),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              isDense: true,
              filled: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
            dropdownMenuEntries: [
              for (final section in thqAccountingSections.entries)
                DropdownMenuEntry(
                  value: section.key,
                  label: section.value,
                  leadingIcon: Icon(_reportIcon(section.key), size: 18),
                  trailingIcon: section.key == _query.report
                      ? const Icon(Icons.check, size: 16)
                      : null,
                ),
            ],
            onSelected: (report) {
              if (report != null) _section(report);
            },
          ),
        ),
      );
      return Row(
        children: [
          if (_trail.isNotEmpty)
            IconButton(
              tooltip: 'Back to previous report',
              onPressed: () => _change(_trail.removeLast()),
              icon: const Icon(Icons.arrow_back, size: 20),
              visualDensity: VisualDensity.compact,
            ),
          if (wide) picker else Expanded(child: picker),
          if (wide) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.scopeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (widget.openControls != null) ...[
            const SizedBox(width: 4),
            if (wide)
              TextButton.icon(
                onPressed: widget.openControls,
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('Accounts / Controls'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              )
            else
              IconButton(
                onPressed: widget.openControls,
                tooltip: 'Accounts / Controls',
                icon: const Icon(Icons.settings_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ],
      );
    },
  );

  Widget _toolbar(double availableWidth) {
    final options = _result?.options ?? {};
    return Wrap(
      spacing: 6,
      runSpacing: 6,
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
          width: availableWidth < 270 ? availableWidth : 270,
          child: TextField(
            key: const ValueKey('accounting-search'),
            controller: _search,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
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
          visualDensity: VisualDensity.compact,
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
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _navigation(),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (_, box) => _toolbar(box.maxWidth)),
          const SizedBox(height: 6),
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
                padding: const EdgeInsets.only(bottom: 6),
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
                  visualDensity: VisualDensity.compact,
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
                  visualDensity: VisualDensity.compact,
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
      return _journalTable(result.rows, result.columns);
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
  Widget _journalStatusBadge(Map<String, dynamic> r) {
    final status = (r['status'] ?? r['balance_status'] ?? '').toString();
    final posting = (r['posting_status'] ?? '').toString().toLowerCase();
    final balanced = r['balance_status'] == 'Balanced' || status == 'Balanced';
    final colors = Theme.of(context).colorScheme;

    String label;
    Color bg;
    Color fg;

    if (status.toLowerCase() == 'reversed' || posting == 'reversed') {
      label = 'Reversed';
      bg = colors.surfaceContainerHighest;
      fg = colors.onSurfaceVariant;
    } else if (status.toLowerCase() == 'draft' || posting == 'draft') {
      label = 'Draft';
      bg = colors.tertiaryContainer;
      fg = colors.onTertiaryContainer;
    } else if (status == 'Unbalanced' || !balanced) {
      label = 'Unbalanced';
      bg = colors.errorContainer;
      fg = colors.error;
    } else {
      label = 'Balanced';
      bg = colors.primaryContainer.withValues(alpha: 0.6);
      fg = colors.onPrimaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Widget _journalExpandedDetails(Map<String, dynamic> r, ColorScheme colors) {
    final lines = accountingMaps(r['lines']);
    final num totalDebit = lines.fold(0, (sum, l) => sum + (l['debit'] as num? ?? 0));
    final num totalCredit = lines.fold(0, (sum, l) => sum + (l['credit'] as num? ?? 0));
    final bool balanced = (totalDebit - totalCredit).abs() <= 0.005;

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              children: [
                Expanded(flex: 5, child: Text('Account', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                SizedBox(width: 90, child: Text('Debit', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                SizedBox(width: 90, child: Text('Credit', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                Expanded(flex: 4, child: Padding(padding: EdgeInsets.only(left: 12), child: Text('Narration', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))),
              ],
            ),
          ),
          const SizedBox(height: 2),
          ...lines.map((l) {
            final code = l['account_code']?.toString() ?? '';
            final name = l['account_name']?.toString() ?? '';
            final label = code.isNotEmpty ? '$code · $name' : name;
            final narration = (l['description'] ?? r['description'] ?? '—').toString();
            return InkWell(
              onTap: l['account_id'] != null
                  ? () => _section(
                        'general_ledger',
                        filters: {'account_id': l['account_id'].toString()},
                        drill: true,
                      )
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: l['account_id'] != null ? colors.primary : colors.onSurface,
                          decoration: l['account_id'] != null ? TextDecoration.underline : null,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _money(l['debit']),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        _money(l['credit']),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          narration,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const Divider(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                const Expanded(
                  flex: 5,
                  child: Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    _money(totalDebit),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    _money(totalCredit),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      balanced ? 'Balanced ✓ (DR = CR)' : '⚠️ Unbalanced (Diff: ${_money(totalDebit - totalCredit)})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: balanced ? colors.primary : colors.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (r['created_at'] != null)
                Text(
                  'Posted: ${r['created_at']}',
                  style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
                ),
              if (r['location'] != null && r['location'].toString().isNotEmpty)
                Text(
                  'Store: ${r['location']}',
                  style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
                ),
              if (r['document_id'] != null)
                TextButton.icon(
                  onPressed: () => _openOriginal(r),
                  icon: const Icon(Icons.description_outlined, size: 14),
                  label: const Text('Original document', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              if (widget.openHistory != null)
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await widget.openHistory!(r);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not load audit history: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.history, size: 14),
                  label: const Text('Audit history', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              if (r['reversal_of'] != null)
                TextButton(
                  onPressed: () => _section(
                    'journal',
                    filters: {'journal_id': r['reversal_of'].toString()},
                    drill: true,
                    from: DateTime(1900),
                  ),
                  child: Text('Reversal of ${r['reversal_of']}', style: const TextStyle(fontSize: 11)),
                ),
              for (final rev in accountingMaps(r['reversals']))
                TextButton(
                  onPressed: () => _section(
                    'journal',
                    filters: {'journal_id': rev['journal_id'].toString()},
                    drill: true,
                    from: DateTime(1900),
                  ),
                  child: Text('Reversed by ${rev['reference']}', style: const TextStyle(fontSize: 11)),
                ),
              TextButton(
                onPressed: () => _details(r),
                child: const Text('All audit fields…', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _journalTable(
    List<Map<String, dynamic>> rows,
    List<ThqAccountingColumn> cols,
  ) => LayoutBuilder(
    builder: (ctx, box) {
      final compact = box.maxWidth < 760;
      final colors = Theme.of(ctx).colorScheme;

      if (compact) {
        return ListView.builder(
          controller: _scroll,
          itemCount: rows.length,
          itemBuilder: (ctx, i) {
            final r = rows[i];
            final jid = (r['journal_id'] ?? r['id'] ?? r['entry_number'] ?? i).toString();
            final expanded = _expandedJournals.contains(jid);
            final entryNumber = r['entry_number']?.toString() ?? r['reference']?.toString() ?? '—';
            final sourceRef = r['source_reference']?.toString() ?? r['reference']?.toString() ?? '—';
            final type = (r['type'] ?? r['source_type'] ?? '').toString();
            final party = (r['party'] ?? '').toString();
            final debit = r['debit'] ?? r['amount'] ?? 0;
            final credit = r['credit'] ?? r['amount'] ?? 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    if (expanded) {
                      _expandedJournals.remove(jid);
                    } else {
                      _expandedJournals.add(jid);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(entryNumber, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$sourceRef · $type${party.isNotEmpty ? ' · $party' : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          _journalStatusBadge(r),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(_day(r['date']), style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                          const Spacer(),
                          Text('DR ${_money(debit)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 10),
                          Text('CR ${_money(credit)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18),
                        ],
                      ),
                      if (expanded) _journalExpandedDetails(r, colors),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }

      final headers = [
        {'key': 'date', 'label': 'Date', 'flex': 2, 'numeric': false},
        {'key': 'entry_number', 'label': 'Journal No.', 'flex': 2, 'numeric': false},
        {'key': 'reference', 'label': 'Source Reference', 'flex': 3, 'numeric': false},
        {'key': 'source_type', 'label': 'Type', 'flex': 2, 'numeric': false},
        {'key': 'debit', 'label': 'Debit', 'flex': 2, 'numeric': true},
        {'key': 'credit', 'label': 'Credit', 'flex': 2, 'numeric': true},
        {'key': 'status', 'label': 'Status', 'flex': 2, 'numeric': false},
      ];

      Widget headerWidget() => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            for (final h in headers)
              Expanded(
                flex: h['flex'] as int,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () {
                      final k = h['key'] as String;
                      _change(
                        _query.copyWith(
                          sortKey: k,
                          descending: _query.sortKey == k ? !_query.descending : false,
                          offset: 0,
                        ),
                      );
                    },
                    child: Tooltip(
                      message: 'Sort by ${h['label']}',
                      child: Text(
                        '${h['label']}${_query.sortKey == h['key'] ? (_query.descending ? ' ↓' : ' ↑') : ''}',
                        textAlign: (h['numeric'] as bool) ? TextAlign.right : TextAlign.left,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 28),
          ],
        ),
      );

      return Column(
        children: [
          headerWidget(),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: rows.length,
              itemBuilder: (ctx, i) {
                final r = rows[i];
                final jid = (r['journal_id'] ?? r['id'] ?? r['entry_number'] ?? i).toString();
                final expanded = _expandedJournals.contains(jid);
                final entryNumber = r['entry_number']?.toString() ?? r['reference']?.toString() ?? '—';
                final sourceRef = r['source_reference']?.toString() ?? r['reference']?.toString() ?? '—';
                final type = (r['type'] ?? (r['source_type'] ?? '').toString().replaceAll('_', ' ')).toString();
                final party = (r['party'] ?? '').toString();
                final debit = r['debit'] ?? r['amount'] ?? 0;
                final credit = r['credit'] ?? r['amount'] ?? 0;

                return Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5))),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (expanded) {
                              _expandedJournals.remove(jid);
                            } else {
                              _expandedJournals.add(jid);
                            }
                          });
                        },
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(_day(r['date']), style: const TextStyle(fontSize: 11.5)))),
                              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(entryNumber, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)))),
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Tooltip(
                                    message: party.isNotEmpty ? '$sourceRef · $party' : sourceRef,
                                    child: Text(
                                      party.isNotEmpty ? '$sourceRef · $party' : sourceRef,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(type, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)))),
                              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(_money(debit), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)))),
                              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(_money(credit), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)))),
                              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Align(alignment: Alignment.centerLeft, child: _journalStatusBadge(r)))),
                              SizedBox(
                                width: 28,
                                child: Icon(
                                  expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 18,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (expanded)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: _journalExpandedDetails(r, colors),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );

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
    final colors = Theme.of(context).colorScheme;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in result.rows) {
      groups
          .putIfAbsent(row['group']?.toString() ?? 'Other', () => [])
          .add(row);
    }

    num groupTotal(String g) =>
        accountingMap(result.data['group_totals'])[g] as num? ??
        groups[g]?.fold<num>(0, (s, r) => s + (r['amount'] as num? ?? 0)) ??
        0;

    final allSectionKeys = groups.keys.toList();
    final allCollapsed = allSectionKeys.isNotEmpty &&
        allSectionKeys.every((k) => _collapsedStatementSections.contains(k));

    void toggleAll() {
      setState(() {
        if (allCollapsed) {
          _collapsedStatementSections.clear();
        } else {
          _collapsedStatementSections.addAll(allSectionKeys);
        }
      });
    }

    Widget sectionHeader(String title, num amount, {bool isSubgroup = false}) {
      final collapsed = _collapsedStatementSections.contains(title);
      return InkWell(
        onTap: () {
          setState(() {
            if (collapsed) {
              _collapsedStatementSections.remove(title);
            } else {
              _collapsedStatementSections.add(title);
            }
          });
        },
        child: Container(
          height: isSubgroup ? 32 : 36,
          padding: EdgeInsets.only(left: isSubgroup ? 18 : 8, right: 12),
          decoration: BoxDecoration(
            color: isSubgroup
                ? colors.surfaceContainerLow.withValues(alpha: 0.5)
                : colors.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4))),
          ),
          child: Row(
            children: [
              Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: isSubgroup ? 16 : 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isSubgroup ? 12 : 12.5,
                    fontWeight: isSubgroup ? FontWeight.w600 : FontWeight.bold,
                  ),
                ),
              ),
              Text(
                _money(amount),
                style: TextStyle(
                  fontSize: isSubgroup ? 12 : 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget accountRow(Map<String, dynamic> r, {double indent = 28}) {
      final name = r['account_name']?.toString() ?? r['reference']?.toString() ?? '';
      final desc = r['description']?.toString() ?? '';
      final amt = (r['amount'] as num? ?? 0);
      final hasAccount = r['account_id'] != null && _query.report != 'cash_flow';

      return InkWell(
        onTap: () => hasAccount
            ? _section(
                'general_ledger',
                filters: {'account_id': r['account_id'].toString()},
                drill: true,
                from: _query.report == 'balance_sheet' ? DateTime(1900) : null,
              )
            : _details(r),
        child: Container(
          height: 32,
          padding: EdgeInsets.only(left: indent, right: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.25))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: hasAccount ? colors.primary : colors.onSurface,
                        ),
                      ),
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                _money(amt),
                style: const TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
      );
    }

    Widget subtotalRow(String title, num amount, {bool isPrimary = false, String? subtitle}) => Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isPrimary
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : colors.surfaceContainerHighest.withValues(alpha: 0.7),
        border: Border(
          top: BorderSide(color: isPrimary ? colors.primary : colors.outlineVariant, width: isPrimary ? 1.5 : 1),
          bottom: BorderSide(color: isPrimary ? colors.primary : colors.outlineVariant, width: isPrimary ? 1.5 : 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isPrimary ? 13 : 12,
                    fontWeight: FontWeight.w800,
                    color: isPrimary ? colors.onPrimaryContainer : colors.onSurface,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Text(
            _money(amount),
            style: TextStyle(
              fontSize: isPrimary ? 14 : 12.5,
              fontWeight: FontWeight.w800,
              color: isPrimary ? colors.onPrimaryContainer : colors.onSurface,
            ),
          ),
        ],
      ),
    );

    List<Widget> items = [];

    items.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            Text(
              thqAccountingSections[_query.report] ?? 'Financial Statement',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: toggleAll,
              icon: Icon(allCollapsed ? Icons.unfold_more : Icons.unfold_less, size: 16),
              label: Text(allCollapsed ? 'Expand all' : 'Collapse all', style: const TextStyle(fontSize: 11.5)),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ),
    );

    if (_query.report == 'profit_loss') {
      final revenue = groupTotal('Revenue');
      final cogs = groupTotal('Cost of Goods Sold');
      final grossProfit = revenue - cogs;
      final expenses = groupTotal('Operating Expenses');
      final other = groups.entries
          .where((e) => !['Revenue', 'Cost of Goods Sold', 'Operating Expenses'].contains(e.key))
          .fold<num>(0, (s, e) => s + e.value.fold<num>(0, (s2, r) => s2 + (r['amount'] as num? ?? 0)));
      final netProfit = grossProfit - expenses + other;

      items.add(sectionHeader('Revenue', revenue));
      if (!_collapsedStatementSections.contains('Revenue')) {
        for (final r in groups['Revenue'] ?? []) {
          items.add(accountRow(r));
        }
      }

      items.add(sectionHeader('Cost of Goods Sold', cogs));
      if (!_collapsedStatementSections.contains('Cost of Goods Sold')) {
        for (final r in groups['Cost of Goods Sold'] ?? []) {
          items.add(accountRow(r));
        }
      }

      items.add(subtotalRow('Gross Profit', grossProfit, subtitle: 'Revenue − Cost of Goods Sold'));

      items.add(sectionHeader('Operating Expenses', expenses));
      if (!_collapsedStatementSections.contains('Operating Expenses')) {
        for (final r in groups['Operating Expenses'] ?? []) {
          items.add(accountRow(r));
        }
      }

      for (final e in groups.entries) {
        if (!['Revenue', 'Cost of Goods Sold', 'Operating Expenses'].contains(e.key)) {
          final amt = groupTotal(e.key);
          items.add(sectionHeader(e.key, amt));
          if (!_collapsedStatementSections.contains(e.key)) {
            for (final r in e.value) {
              items.add(accountRow(r));
            }
          }
        }
      }

      items.add(subtotalRow(netProfit >= 0 ? 'Net Profit' : 'Net Loss', netProfit, isPrimary: true));

    } else if (_query.report == 'balance_sheet') {
      final assets = groupTotal('Assets');
      final liabilities = groupTotal('Liabilities');
      final equity = groups['Equity']?.fold<num>(0, (s, r) => s + (r['amount'] as num? ?? 0)) ?? groupTotal('Equity');
      final totalLiabEquity = liabilities + equity;
      final diff = assets - totalLiabEquity;
      final balanced = diff.abs() <= 0.005;

      items.add(sectionHeader('Assets', assets));
      if (!_collapsedStatementSections.contains('Assets')) {
        final assetRows = groups['Assets'] ?? [];
        final subs = <String, List<Map<String, dynamic>>>{};
        for (final r in assetRows) {
          subs.putIfAbsent(r['subgroup']?.toString() ?? 'Assets', () => []).add(r);
        }
        for (final sub in subs.entries) {
          final subTotal = accountingMap(result.data['subgroup_totals'])['Assets:${sub.key}'] as num? ??
              sub.value.fold<num>(0, (n, r) => n + (r['amount'] as num? ?? 0));
          if (subs.length > 1) {
            items.add(sectionHeader(sub.key, subTotal, isSubgroup: true));
            if (!_collapsedStatementSections.contains(sub.key)) {
              for (final r in sub.value) {
                items.add(accountRow(r, indent: 36));
              }
            }
          } else {
            for (final r in sub.value) {
              items.add(accountRow(r));
            }
          }
        }
      }
      items.add(subtotalRow('Total Assets', assets));

      items.add(sectionHeader('Liabilities', liabilities));
      if (!_collapsedStatementSections.contains('Liabilities')) {
        for (final r in groups['Liabilities'] ?? []) {
          items.add(accountRow(r));
        }
      }
      items.add(subtotalRow('Total Liabilities', liabilities));

      items.add(sectionHeader('Equity', equity));
      if (!_collapsedStatementSections.contains('Equity')) {
        for (final r in groups['Equity'] ?? []) {
          items.add(accountRow(r));
        }
      }
      items.add(subtotalRow('Total Equity', equity));

      items.add(subtotalRow('Total Liabilities & Equity', totalLiabEquity));

      items.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: balanced
                ? colors.primaryContainer.withValues(alpha: 0.3)
                : colors.errorContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: balanced
                  ? colors.primary.withValues(alpha: 0.5)
                  : colors.error,
            ),
          ),
          child: Row(
            children: [
              Icon(
                balanced ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                size: 20,
                color: balanced ? colors.primary : colors.error,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      balanced
                          ? 'Assets = Liabilities + Equity (${_money(assets)}) · Balanced ✓'
                          : 'Unexplained Difference: ${_money(diff)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: balanced ? colors.onSurface : colors.error,
                      ),
                    ),
                    if (!balanced)
                      Text(
                        'Total Assets ${_money(assets)} ≠ Total Liabilities & Equity ${_money(totalLiabEquity)}. Statement does not manufacture artificial balancing entries.',
                        style: TextStyle(fontSize: 10.5, color: colors.onErrorContainer),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

    } else {
      for (final e in groups.entries) {
        final total = groupTotal(e.key);
        items.add(sectionHeader(e.key, total));
        if (!_collapsedStatementSections.contains(e.key)) {
          for (final r in e.value) {
            items.add(accountRow(r));
          }
        }
      }
      final netMovement = groups.values.fold<num>(
        0,
        (sum, list) => sum + list.fold<num>(0, (s, r) => s + (r['amount'] as num? ?? 0)),
      );
      items.add(subtotalRow('Net Cash Movement', netMovement, isPrimary: true));
    }

    return ListView(
      controller: _scroll,
      children: items,
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
          ['party', 'description', 'account_name'].contains(c.key)
          ? 3
          : ['payment_status', 'status'].contains(c.key)
          ? 1
          : 2;
      Widget row(Map<String, dynamic> r, {bool header = false}) => Container(
        height: header ? 34 : 40,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
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
                          textAlign: c.numeric
                              ? TextAlign.right
                              : TextAlign.left,
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
