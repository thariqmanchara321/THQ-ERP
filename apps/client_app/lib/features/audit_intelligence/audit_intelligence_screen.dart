import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/client_session.dart';
import '../../services/location_scope_service.dart';
import 'audit_intelligence_service.dart';
import 'audit_detail_dialogs.dart';
import 'transaction_story_dialog.dart';

class AuditIntelligenceScreen extends StatefulWidget {
  const AuditIntelligenceScreen({
    super.key,
    required this.session,
    this.service,
  });
  final ClientSession session;
  final AuditIntelligenceService? service;
  @override
  State<AuditIntelligenceScreen> createState() =>
      _AuditIntelligenceScreenState();
}

class _AuditIntelligenceScreenState extends State<AuditIntelligenceScreen>
    with WidgetsBindingObserver {
  late final AuditIntelligenceService _service;
  final _search = TextEditingController();
  late DateTime _from, _to;
  String _view = 'findings',
      _severity = '',
      _status = 'active',
      _sort = 'date',
      _metric = 'gross_profit';
  bool _descending = true,
      _loading = false,
      _exporting = false,
      _foreground = true;
  int _offset = 0, _request = 0;
  Map<String, dynamic> _data = {};
  String? _error;
  DateTime? _refreshed;
  Timer? _debounce, _poll;
  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);
  bool get _canConfigure =>
      widget.session.hasPermission('audit_center.configure');
  static const _sections = {
    'findings': 'Findings',
    'activity': 'Transaction activity',
    'accounts': 'Account reconciliation',
    'journals': 'All journals',
    'profitability': 'Product profitability',
    'explain': 'Explain a number',
  };
  Map<String, String> get _availableSections => {
    for (final e in _sections.entries)
      if ((e.key != 'profitability' ||
              widget.session.hasPermission('profitability.view')) &&
          (e.key != 'explain' || widget.session.hasPermission('explain.view')))
        e.key: e.value,
  };
  static const _metrics = {
    'sales': 'Sales revenue',
    'cogs': 'Cost of goods sold',
    'gross_profit': 'Gross profit',
    'net_profit': 'Net profit',
    'inventory_value': 'Inventory value',
    'receivables': 'Receivables',
    'payables': 'Payables',
    'cash': 'Cash',
    'bank': 'Bank',
    'upi': 'UPI clearing',
    'card': 'Card clearing',
    'gst_payable': 'Net GST payable',
  };
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AuditIntelligenceService();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 29));
    WidgetsBinding.instance.addObserver(this);
    LocationScopeService.selectedLocationId.addListener(_scopeChanged);
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_foreground && !_loading && !_exporting) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _poll?.cancel();
    _search.dispose();
    LocationScopeService.selectedLocationId.removeListener(_scopeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _reload();
  }

  void _scopeChanged() {
    _offset = 0;
    _data = {};
    _reload();
  }

  void _refresh() => _reload();
  Future<void> _reload() async {
    _debounce?.cancel();
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Map<String, dynamic> data;
      if (_view == 'profitability') {
        final rows = await _service.profitability(
          tenantId: _tenantId,
          from: _from,
          to: _to,
          locationId: _locationId,
          query: _search.text,
          limit: 1000,
        );
        data = {'rows': rows, 'total_rows': rows.length};
      } else if (_view == 'explain') {
        data = await _service.metricExplanation(
          tenantId: _tenantId,
          metric: _metric,
          from: _from,
          to: _to,
          locationId: _locationId,
        );
      } else {
        data = await _service.workspace(
          tenantId: _tenantId,
          view: _view,
          from: _from,
          to: _to,
          locationId: _locationId,
          query: _search.text,
          severity: _severity,
          status: _status,
          sort: _sort,
          descending: _descending,
          offset: _offset,
        );
      }
      if (!mounted || request != _request) return;
      if (_offset > 0 && auditRows(data['rows']).isEmpty) {
        _offset = 0;
        _reload();
        return;
      }
      setState(() {
        _data = data;
        _loading = false;
        _refreshed = DateTime.now();
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'Could not refresh audit data. $e';
        });
      }
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) ThqNotify.error(context, 'Could not complete action: $e');
    }
  }

  Future<void> _pickPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null || !mounted) return;
    _from = picked.start;
    _to = picked.end;
    _offset = 0;
    _reload();
  }

  void _section(String value) {
    _view = value;
    _offset = 0;
    _search.clear();
    _data = {};
    _sort = value == 'accounts' ? 'account_name' : 'date';
    _descending = value != 'accounts';
    _reload();
  }

  Widget _select(
    String label,
    String value,
    Map<String, String> options,
    void Function(String) change, {
    double width = 170,
  }) => SizedBox(
    width: width,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: const OutlineInputBorder(),
      ),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(
                e.value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          )
          .toList(),
      onChanged: _exporting
          ? null
          : (v) {
              if (v != null) change(v);
            },
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _select(
              'Audit section',
              _view,
              _availableSections,
              _section,
              width: 235,
            ),
            OutlinedButton.icon(
              onPressed: _exporting ? null : _pickPeriod,
              icon: const Icon(Icons.date_range, size: 16),
              label: Text(
                '${auditDate(_from.toIso8601String().substring(0, 10))} – ${auditDate(_to.toIso8601String().substring(0, 10))}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            IconButton(
              tooltip: 'Refresh audit',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh, size: 20),
            ),
            if (_canConfigure)
              IconButton(
                tooltip: 'Risk rules',
                onPressed: () => _guard(_openRiskRules),
                icon: const Icon(Icons.tune, size: 20),
              ),
            if (_view != 'explain' && _view != 'profitability')
              IconButton(
                tooltip: 'Export all matching rows to CSV',
                onPressed: _exporting || _loading ? null : _export,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined, size: 20),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${LocationScopeService.scopeLabel(widget.session)} · Live ledger evidence',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            Text(
              _refreshed == null
                  ? ''
                  : 'Refreshed ${auditDate(_refreshed!.toIso8601String()).split(' ').last}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      if (_loading)
        const LinearProgressIndicator(minHeight: 2)
      else
        const SizedBox(height: 2),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      if (_view == 'explain') ...[
        Padding(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _select('Explain this number', _metric, _metrics, (v) {
              _metric = v;
              _data = {};
              _reload();
            }, width: 260),
          ),
        ),
        Expanded(child: _explanation()),
      ] else ...[
        _summary(),
        if (_view == 'accounts')
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Positive balances are debit; negative balances are credit. Includes archived accounts and effective reversals.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        if (_view == 'profitability' && auditRows(_data['rows']).length >= 1000)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Text(
              'Showing the first 1,000 matching products. Refine your search to inspect the remaining products.',
            ),
          ),
        _filters(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _loading && _data.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : AuditTable(
                    columns: _columns,
                    rows: auditRows(_data['rows']),
                    currency: widget.session.currencyCode,
                    onOpen: (row) => _guard(() => _openRow(row)),
                    empty: _view == 'findings'
                        ? 'No matching findings. Review all statuses or adjust the period.'
                        : 'No matching records for this period and store.',
                  ),
          ),
        ),
        _pager(),
      ],
    ],
  );
  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
    child: LayoutBuilder(
      builder: (context, b) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: (b.maxWidth * .35).clamp(180, 400),
            child: TextField(
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  _offset = 0;
                  _reload();
                });
              },
              onSubmitted: (_) {
                _offset = 0;
                _reload();
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: _view == 'profitability'
                    ? 'Search product / SKU'
                    : 'Search reference, account, user…',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _search.clear();
                    _offset = 0;
                    _reload();
                  },
                  icon: const Icon(Icons.clear, size: 16),
                ),
              ),
            ),
          ),
          if (_view == 'findings') ...[
            _select(
              'Risk',
              _severity,
              const {
                '': 'All risks',
                'high_risk': 'High risk',
                'needs_review': 'Needs review',
              },
              (v) {
                _severity = v;
                _offset = 0;
                _reload();
              },
              width: 140,
            ),
            _select(
              'Status',
              _status,
              const {
                'active': 'Needs attention',
                '': 'All statuses',
                'open': 'Open',
                'under_review': 'Under review',
                'explained': 'Explained',
                'resolved': 'Resolved',
                'escalated': 'Escalated',
                'dismissed': 'Dismissed',
              },
              (v) {
                _status = v;
                _offset = 0;
                _reload();
              },
              width: 165,
            ),
          ],
          if (_view != 'profitability') ...[
            _select(
              'Sort',
              _sort,
              _view == 'accounts'
                  ? const {
                      'account_name': 'Account',
                      'closing': 'Closing balance',
                      'debit': 'Period debit',
                      'credit': 'Period credit',
                      'reference': 'Code',
                    }
                  : _view == 'journals'
                  ? const {
                      'date': 'Date',
                      'reference': 'Reference',
                      'amount': 'Amount',
                      'status': 'Posting status',
                      'balance_status': 'Balance status',
                    }
                  : const {
                      'date': 'Date',
                      'reference': 'Reference',
                      'title': 'Description',
                      'actor': 'User',
                    },
              (v) {
                _sort = v;
                _offset = 0;
                _reload();
              },
              width: 150,
            ),
            IconButton(
              tooltip: _descending
                  ? 'Newest / highest first'
                  : 'Oldest / lowest first',
              onPressed: () {
                _descending = !_descending;
                _offset = 0;
                _reload();
              },
              icon: Icon(
                _descending ? Icons.arrow_downward : Icons.arrow_upward,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    ),
  );
  Widget _summary() {
    if (_data.isEmpty) return const SizedBox.shrink();
    final summary = auditMap(_data['summary']),
        checks = auditMap(_data['checks']),
        totals = auditMap(_data['account_totals']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: AuditMetrics({
        if (summary.isNotEmpty) 'High risk': '${summary['high_risk'] ?? 0}',
        if (summary.isNotEmpty)
          'Needs review': '${summary['needs_review'] ?? 0}',
        if (summary.isNotEmpty)
          'Active findings': '${summary['open_attention'] ?? 0}',
        if (checks.isNotEmpty)
          'Unbalanced journals': '${checks['unbalanced_journals'] ?? 0}',
        if (_view == 'accounts')
          'Period difference': auditMoney(
            totals['difference'],
            widget.session.currencyCode,
          ),
        if (_view == 'accounts')
          'Closing difference': auditMoney(
            totals['closing_difference'],
            widget.session.currencyCode,
          ),
      }),
    );
  }

  List<AuditColumn> get _columns => switch (_view) {
    'accounts' => const [
      AuditColumn('account_name', 'Account', flex: 4),
      AuditColumn('account_type', 'Type', compact: false),
      AuditColumn('opening', 'Opening DR ±', numeric: true, compact: false),
      AuditColumn('debit', 'Debit', numeric: true, compact: false),
      AuditColumn('credit', 'Credit', numeric: true, compact: false),
      AuditColumn('closing', 'Closing DR ±', numeric: true),
      AuditColumn('status', 'State', compact: false),
    ],
    'journals' => const [
      AuditColumn('date', 'Date', compact: false),
      AuditColumn('reference', 'Reference', flex: 3),
      AuditColumn('type', 'Source', flex: 3, compact: false),
      AuditColumn('party', 'Party', flex: 3, compact: false),
      AuditColumn('amount', 'Debit total', numeric: true),
      AuditColumn('balance_status', 'Balance'),
      AuditColumn('status', 'Posting', compact: false),
    ],
    'activity' => const [
      AuditColumn('date', 'When', compact: false),
      AuditColumn('reference', 'Reference'),
      AuditColumn('title', 'Event', flex: 4),
      AuditColumn('actor', 'User', compact: false),
      AuditColumn('location', 'Store', compact: false),
      AuditColumn('evidence_quality', 'Evidence', compact: false),
    ],
    'profitability' => const [
      AuditColumn('product_name', 'Product', flex: 4),
      AuditColumn('sku', 'SKU', compact: false),
      AuditColumn('net_revenue', 'Net sales', numeric: true),
      AuditColumn('net_cogs', 'Cost of goods', numeric: true, compact: false),
      AuditColumn('gross_profit', 'Gross profit', numeric: true),
      AuditColumn(
        'margin_pct',
        'Margin',
        numeric: true,
        format: 'percent',
        compact: false,
      ),
    ],
    _ => const [
      AuditColumn('date', 'Detected', compact: false),
      AuditColumn('reference', 'Reference'),
      AuditColumn('title', 'Finding', flex: 4),
      AuditColumn('severity', 'Risk'),
      AuditColumn('status', 'Status', compact: false),
      AuditColumn('actor', 'User', compact: false),
      AuditColumn('location', 'Store', compact: false),
    ],
  };
  Widget _pager() {
    final total = auditNumber(_data['total_rows']).toInt(),
        count = auditRows(_data['rows']).length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _view == 'profitability'
                  ? '$total products${total >= 1000 ? ' · Search to narrow the first 1,000' : ''}'
                  : total == 0
                  ? '0 records'
                  : '${_offset + 1}–${_offset + count} of $total',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          if (_view != 'profitability') ...[
            IconButton(
              tooltip: 'Previous page',
              onPressed: _loading || _offset == 0
                  ? null
                  : () {
                      _offset = (_offset - 50).clamp(0, total);
                      _reload();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Next page',
              onPressed: _loading || _offset + count >= total
                  ? null
                  : () {
                      _offset += 50;
                      _reload();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ],
      ),
    );
  }

  Widget _explanation() {
    if (_data.isEmpty) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    final previous = auditMap(_data['previous']),
        bridge = auditMap(_data['driver_reconciliation']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        AuditMetrics({
          auditText(_data['label']): auditMoney(
            _data['value'],
            widget.session.currencyCode,
          ),
          _data['kind'] == 'balance'
              ? 'Before selected period'
              : 'Previous equal period': auditMoney(
            previous['value'],
            widget.session.currencyCode,
          ),
          'Change': auditMoney(_data['change'], widget.session.currencyCode),
        }),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            auditText(_data['equation']),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const Text(
          'Linked account contributions',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        AuditTable(
          shrinkWrap: true,
          currency: widget.session.currencyCode,
          columns: const [
            AuditColumn('label', 'Account', flex: 4),
            AuditColumn(
              'previous_value',
              'Previous',
              numeric: true,
              compact: false,
            ),
            AuditColumn('value', 'Contribution', numeric: true),
            AuditColumn('change', 'Change', numeric: true),
          ],
          rows: auditRows(_data['components']),
          onOpen: (r) => _guard(() => _account(r)),
        ),
        const SizedBox(height: 16),
        const Text(
          'What changed',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        AuditTable(
          shrinkWrap: true,
          currency: widget.session.currencyCode,
          columns: const [
            AuditColumn('label', 'Business source', flex: 4),
            AuditColumn(
              'previous_value',
              'Previous',
              numeric: true,
              compact: false,
            ),
            AuditColumn('current_value', 'Current', numeric: true),
            AuditColumn('impact', 'Impact on change', numeric: true),
          ],
          rows: auditRows(_data['drivers']),
          onOpen: (r) =>
              _guard(() => _sourceJournals(auditText(r['source_type']))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            bridge['reconciles'] == true
                ? 'Source impacts reconcile to the change.'
                : 'The source bridge differs from the change. Review the linked journals.',
            style: TextStyle(
              color: bridge['reconciles'] == true
                  ? null
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
        Text(
          auditText(_data['basis']),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _openRow(Map<String, dynamic> row) async {
    if (_view == 'accounts') {
      await _account(row);
      return;
    }
    if (_view == 'journals') {
      await showAuditJournalDialog(
        context: context,
        service: _service,
        tenantId: _tenantId,
        journal: row,
        session: widget.session,
        from: _from,
        to: _to,
        locationId: _locationId,
      );
      return;
    }
    if (_view == 'profitability') {
      final data = await _service.productProfitExplanation(
        tenantId: _tenantId,
        variantId: auditText(row['variant_id']),
        from: _from,
        to: _to,
        locationId: _locationId,
      );
      if (!mounted) return;
      await showAuditEvidenceDialog(
        context: context,
        title: 'Product profitability · ${auditText(row['product_name'])}',
        currency: widget.session.currencyCode,
        sections: {
          'Profit equation': data['equation'],
          'Profit drivers': data['drivers'],
          'Returns': data['returns'],
          'Previous period': data['previous_period'],
          'Profit change': data['profit_change'],
        },
      );
      return;
    }
    if (_view == 'findings') {
      final changed = await showAuditFindingDialog(
        context: context,
        service: _service,
        session: widget.session,
        findingId: auditText(row['finding_id'] ?? row['id']),
        from: _from,
        to: _to,
        locationId: _locationId,
      );
      if (changed && mounted) _reload();
      return;
    }
    final type = auditText(
          row['root_entity_type'] ?? row['entity_type'],
          fallback: '',
        ),
        id = auditText(row['root_entity_id'] ?? row['entity_id'], fallback: '');
    if (type.isEmpty || id.isEmpty) return;
    await showTransactionStoryDialog(
      context: context,
      service: _service,
      tenantId: _tenantId,
      entityType: type,
      entityId: id,
      session: widget.session,
      from: _from,
      to: _to,
      locationId: _locationId,
    );
  }

  Future<void> _account(Map<String, dynamic> row) => showAuditLedgerDialog(
    context: context,
    service: _service,
    session: widget.session,
    accountId: auditText(row['account_id'] ?? row['id']),
    accountName: auditText(row['account_name'] ?? row['label']),
    from: _from,
    to: _to,
    locationId: _locationId,
  );
  Future<void> _sourceJournals(String source) => showAuditSourceJournalsDialog(
    context: context,
    service: _service,
    session: widget.session,
    source: source,
    from: _data['kind'] == 'period'
        ? DateTime.tryParse(auditText(auditMap(_data['previous'])['from'])) ??
              _from
        : _from,
    to: _to,
    locationId: _locationId,
  );
  Future<void> _export() async {
    _debounce?.cancel();
    setState(() => _exporting = true);
    await _guard(
      () => _service.exportWorkspace(
        tenantId: _tenantId,
        view: _view,
        from: _from,
        to: _to,
        locationId: _locationId,
        query: _search.text,
        severity: _severity,
        status: _status,
        sort: _sort,
        descending: _descending,
        columns: {for (final c in _columns) c.key: c.label},
      ),
    );
    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _openRiskRules() async {
    final config = await _service.riskConfig(tenantId: _tenantId);
    if (!mounted) return;

    final discountReview = TextEditingController(
      text: auditText(config['discount_review_pct'], fallback: '10'),
    );
    final discountHigh = TextEditingController(
      text: auditText(config['discount_high_pct'], fallback: '20'),
    );
    final stockReview = TextEditingController(
      text: auditText(
        config['stock_adjustment_review_value'],
        fallback: '10000',
      ),
    );
    final stockHigh = TextEditingController(
      text: auditText(config['stock_adjustment_high_value'], fallback: '50000'),
    );
    final backdateReview = TextEditingController(
      text: auditText(config['backdate_review_days'], fallback: '1'),
    );
    final backdateHigh = TextEditingController(
      text: auditText(config['backdate_high_days'], fallback: '7'),
    );

    var negativeMargin = config['negative_margin_high'] != false;
    var manualJournal = config['manual_journal_review'] != false;
    var postedPurchase = config['posted_purchase_edit_review'] != false;
    var paymentEdit = config['payment_edit_high'] != false;

    Future<void> save(BuildContext dialogContext) async {
      final numeric = <String, num?>{
        'discount_review_pct': double.tryParse(discountReview.text.trim()),
        'discount_high_pct': double.tryParse(discountHigh.text.trim()),
        'stock_adjustment_review_value': double.tryParse(
          stockReview.text.trim(),
        ),
        'stock_adjustment_high_value': double.tryParse(stockHigh.text.trim()),
        'backdate_review_days': int.tryParse(backdateReview.text.trim()),
        'backdate_high_days': int.tryParse(backdateHigh.text.trim()),
      };
      if (numeric.values.any((value) => (value ?? -1) < 0)) {
        ThqNotify.showSnackBar(
          context,
          const SnackBar(content: Text('Enter valid non-negative thresholds.')),
        );
        return;
      }
      if (numeric['discount_high_pct']! > 100 ||
          numeric['discount_review_pct']! > numeric['discount_high_pct']! ||
          numeric['stock_adjustment_review_value']! >
              numeric['stock_adjustment_high_value']! ||
          numeric['backdate_review_days']! > numeric['backdate_high_days']!) {
        ThqNotify.error(
          context,
          'Review thresholds must not exceed high-risk thresholds. Discount percentages cannot exceed 100.',
        );
        return;
      }
      await _service.setRiskConfig(
        tenantId: _tenantId,
        config: {
          ...numeric.map((key, value) => MapEntry(key, value!)),
          'negative_margin_high': negativeMargin,
          'manual_journal_review': manualJournal,
          'posted_purchase_edit_review': postedPurchase,
          'payment_edit_high': paymentEdit,
        },
      );
      if (!mounted || !dialogContext.mounted) {
        return;
      }
      Navigator.of(dialogContext).pop();
      _refresh();
      ThqNotify.success(context, 'Audit risk rules updated.');
    }

    var saving = false;
    await showThqDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget numberField(TextEditingController controller, String label) {
            return TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            );
          }

          return AlertDialog(
            title: const Text('Audit Risk Rules'),
            content: SizedBox(
              width: 720,
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Text(
                    'Risk means attention required; it is not an accusation of fraud or wrongdoing.',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: numberField(discountReview, 'Discount review %'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: numberField(
                          discountHigh,
                          'Discount high-risk %',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: numberField(
                          stockReview,
                          'Stock adjustment review value',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: numberField(
                          stockHigh,
                          'Stock adjustment high-risk value',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: numberField(
                          backdateReview,
                          'Backdated review days',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: numberField(
                          backdateHigh,
                          'Backdated high-risk days',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: negativeMargin,
                    onChanged: (value) =>
                        setDialogState(() => negativeMargin = value),
                    title: const Text('Negative margin is High Risk'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: manualJournal,
                    onChanged: (value) =>
                        setDialogState(() => manualJournal = value),
                    title: const Text('Manual journals Need Review'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: postedPurchase,
                    onChanged: (value) =>
                        setDialogState(() => postedPurchase = value),
                    title: const Text('Posted purchase edits Need Review'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: paymentEdit,
                    onChanged: (value) =>
                        setDialogState(() => paymentEdit = value),
                    title: const Text('Posted payment edits are High Risk'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        if (saving) return;
                        setDialogState(() => saving = true);
                        await _guard(() => save(dialogContext));
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      },
                icon: const Icon(Icons.save_outlined),
                label: Text(saving ? 'Saving…' : 'Save'),
              ),
            ],
          );
        },
      ),
    );

    discountReview.dispose();
    discountHigh.dispose();
    stockReview.dispose();
    stockHigh.dispose();
    backdateReview.dispose();
    backdateHigh.dispose();
  }
}
