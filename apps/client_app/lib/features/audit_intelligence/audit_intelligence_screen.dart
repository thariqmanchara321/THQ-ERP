import 'package:flutter/material.dart';

import '../../models/client_session.dart';
import '../../services/location_scope_service.dart';
import 'audit_intelligence_service.dart';
import 'transaction_story_dialog.dart';

class AuditIntelligenceScreen extends StatefulWidget {
  const AuditIntelligenceScreen({super.key, required this.session});

  final ClientSession session;

  @override
  State<AuditIntelligenceScreen> createState() =>
      _AuditIntelligenceScreenState();
}

class _AuditIntelligenceScreenState extends State<AuditIntelligenceScreen> {
  final AuditIntelligenceService _service = AuditIntelligenceService();
  final TextEditingController _profitSearch = TextEditingController();

  late DateTime _from;
  late DateTime _to;
  String _metric = 'gross_profit';
  int _generation = 0;

  String get _tenantId => widget.session.business.id;
  String? get _locationId => LocationScopeService.selectedLocationId.value;

  bool get _canReview => widget.session.hasPermission('audit_center.review');

  bool get _canResolve => widget.session.hasPermission('audit_center.resolve');

  bool get _canActOnFindings => _canReview || _canResolve;

  bool get _canConfigure =>
      widget.session.hasPermission('audit_center.configure');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 29));
  }

  @override
  void dispose() {
    _profitSearch.dispose();
    super.dispose();
  }

  void _refresh() => setState(() => _generation++);

  Future<void> _pickPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
      _generation++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.policy_outlined),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Audit Intelligence & Explainability',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${_dateLabel(_from)} — ${_dateLabel(_to)}'
                        '${_locationId == null ? ' • All permitted stores' : ' • Selected store'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_canConfigure) ...[
                  IconButton(
                    tooltip: 'Risk rules',
                    onPressed: _openRiskRules,
                    icon: const Icon(Icons.tune_outlined),
                  ),
                  const SizedBox(width: 4),
                ],
                OutlinedButton.icon(
                  onPressed: _pickPeriod,
                  icon: const Icon(Icons.date_range_outlined, size: 17),
                  label: const Text('Period'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.shield_outlined), text: 'Audit Center'),
              Tab(icon: Icon(Icons.rule_outlined), text: 'Findings'),
              Tab(
                icon: Icon(Icons.trending_up_outlined),
                text: 'Profitability',
              ),
              Tab(icon: Icon(Icons.lightbulb_outline), text: 'Explain Number'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                _overviewTab(),
                _findingsTab(),
                _profitabilityTab(),
                _explainTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewTab() {
    final key = ValueKey('overview-$_generation-${_locationId ?? 'all'}');
    return FutureBuilder<List<dynamic>>(
      key: key,
      future: Future.wait<dynamic>([
        _service.auditCenterSummary(
          tenantId: _tenantId,
          from: _from,
          to: _to,
          locationId: _locationId,
        ),
        _service.normalTransactions(
          tenantId: _tenantId,
          from: _from,
          to: _to,
          locationId: _locationId,
        ),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _ErrorPanel(error: snapshot.error);
        final values = snapshot.data ?? const [];
        final summary = values.isNotEmpty
            ? Map<String, dynamic>.from(values[0] as Map)
            : <String, dynamic>{};
        final normal = values.length > 1
            ? List<Map<String, dynamic>>.from(values[1] as List)
            : const <Map<String, dynamic>>[];

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _RiskCard(
                    label: 'High Risk',
                    value: _integer(summary['high_risk']),
                    icon: Icons.priority_high,
                    emphasis: true,
                  ),
                  _RiskCard(
                    label: 'Needs Review',
                    value: _integer(summary['needs_review']),
                    icon: Icons.manage_search_outlined,
                  ),
                  _RiskCard(
                    label: 'Normal',
                    value: _integer(summary['normal']),
                    icon: Icons.check_circle_outline,
                  ),
                  _RiskCard(
                    label: 'Open Attention',
                    value: _integer(summary['open_attention']),
                    icon: Icons.pending_actions_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SectionHeader(
                title: 'Normal transaction story',
                subtitle:
                    'Risk is an attention signal, not an accusation. Open a row to see recorded evidence.',
              ),
              const SizedBox(height: 8),
              if (normal.isEmpty)
                const _EmptyPanel(
                  message: 'No normal transactions in this period.',
                )
              else
                ...normal
                    .take(100)
                    .map(
                      (row) => Card(
                        margin: const EdgeInsets.only(bottom: 7),
                        child: ListTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(
                            _text(
                              row['entity_number'],
                              fallback: _text(row['entity_type']),
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            [
                              _text(row['action']),
                              _text(row['event_time']),
                              _text(row['user_name']),
                              _text(row['device_name']),
                            ].where((e) => e != '—').join(' • '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openStory(row),
                        ),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  Widget _findingsTab() {
    final key = ValueKey('findings-$_generation-${_locationId ?? 'all'}');
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: key,
      future: _service.findings(
        tenantId: _tenantId,
        from: _from,
        to: _to,
        locationId: _locationId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _ErrorPanel(error: snapshot.error);
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const _EmptyPanel(
            message: 'No audit findings for this period.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final severity = _text(row['severity']);
              final status = _text(row['status']);
              return Card(
                child: ListTile(
                  leading: Icon(_severityIcon(severity)),
                  title: Text(
                    _text(row['title']),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      severity,
                      status,
                      _text(row['entity_number']),
                      _text(row['event_time']),
                    ].where((e) => e != '—').join(' • '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openFinding(row),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _profitabilityTab() {
    final key = ValueKey(
      'profit-$_generation-${_locationId ?? 'all'}-${_profitSearch.text}',
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _profitSearch,
            onSubmitted: (_) => _refresh(),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Search product / SKU',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: _refresh,
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            key: key,
            future: _service.profitability(
              tenantId: _tenantId,
              from: _from,
              to: _to,
              locationId: _locationId,
              query: _profitSearch.text,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return _ErrorPanel(error: snapshot.error);
              final rows = snapshot.data ?? const <Map<String, dynamic>>[];
              if (rows.isEmpty) {
                return const _EmptyPanel(
                  message:
                      'No recognized product profitability for this period.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final profit = _number(
                      row['gross_profit'] ?? row['profit'],
                    );
                    final margin = _number(
                      row['margin_pct'] ??
                          row['margin_percent'] ??
                          row['margin'],
                    );
                    return Card(
                      child: ListTile(
                        title: Text(
                          _text(row['product_name'] ?? row['name']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            _text(row['sku'], fallback: ''),
                            _text(row['category_name'], fallback: ''),
                            _text(row['brand_name'], fallback: ''),
                          ].where((e) => e.isNotEmpty).join(' • '),
                        ),
                        trailing: SizedBox(
                          width: 300,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _MoneyStat(
                                label: 'Sales',
                                value: _money(
                                  _number(row['net_revenue'] ?? row['sales']),
                                ),
                              ),
                              _MoneyStat(
                                label: 'COGS',
                                value: _money(
                                  _number(row['net_cogs'] ?? row['cost']),
                                ),
                              ),
                              _MoneyStat(
                                label: 'Profit',
                                value: _money(profit),
                              ),
                              _MoneyStat(
                                label: 'Margin',
                                value: '${margin.toStringAsFixed(2)}%',
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                        onTap: () => _openProductProfit(row),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _explainTab() {
    final key = ValueKey(
      'metric-$_generation-${_locationId ?? 'all'}-$_metric',
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 340,
              child: DropdownButtonFormField<String>(
                initialValue: _metric,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Explain this number',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'sales', child: Text('Sales')),
                  DropdownMenuItem(value: 'cogs', child: Text('COGS')),
                  DropdownMenuItem(
                    value: 'gross_profit',
                    child: Text('Gross Profit'),
                  ),
                  DropdownMenuItem(
                    value: 'net_profit',
                    child: Text('Net Profit'),
                  ),
                  DropdownMenuItem(
                    value: 'inventory_value',
                    child: Text('Inventory Value'),
                  ),
                  DropdownMenuItem(
                    value: 'receivables',
                    child: Text('Accounts Receivable'),
                  ),
                  DropdownMenuItem(
                    value: 'payables',
                    child: Text('Accounts Payable'),
                  ),
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  DropdownMenuItem(
                    value: 'net_gst_payable',
                    child: Text('Net GST Payable'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _metric = value;
                    _generation++;
                  });
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            key: key,
            future: _service.metricExplanation(
              tenantId: _tenantId,
              metric: _metric,
              from: _from,
              to: _to,
              locationId: _locationId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return _ErrorPanel(error: snapshot.error);
              final data = snapshot.data ?? const <String, dynamic>{};
              final metric = data;
              final previous = _map(data['previous']);
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Wrap(
                        spacing: 28,
                        runSpacing: 10,
                        children: [
                          _LargeMetric(
                            label: _text(metric['label'], fallback: _metric),
                            value: _money(_number(metric['value'])),
                          ),
                          _LargeMetric(
                            label: 'Previous',
                            value: _money(_number(previous['value'])),
                          ),
                          _LargeMetric(
                            label: 'Change',
                            value: _money(_number(data['change'])),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _StructuredSection(
                    title: 'Formula',
                    value: metric['equation'],
                  ),
                  _StructuredSection(
                    title: 'Components',
                    value: data['components'],
                  ),
                  _StructuredSection(
                    title: 'Deterministic drivers',
                    value: data['drivers'],
                  ),
                  const SizedBox(height: 8),
                  const _EmptyPanel(
                    message:
                        'THQ calculates first and explains second. These values are returned by the authoritative accounting / inventory engine; the UI does not invent or recompute them.',
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openRiskRules() async {
    final config = await _service.riskConfig(tenantId: _tenantId);
    if (!mounted) return;

    final discountReview = TextEditingController(
      text: _text(config['discount_review_pct'], fallback: '10'),
    );
    final discountHigh = TextEditingController(
      text: _text(config['discount_high_pct'], fallback: '20'),
    );
    final stockReview = TextEditingController(
      text: _text(config['stock_adjustment_review_value'], fallback: '10000'),
    );
    final stockHigh = TextEditingController(
      text: _text(config['stock_adjustment_high_value'], fallback: '50000'),
    );
    final backdateReview = TextEditingController(
      text: _text(config['backdate_review_days'], fallback: '1'),
    );
    final backdateHigh = TextEditingController(
      text: _text(config['backdate_high_days'], fallback: '7'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid non-negative thresholds.')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audit risk rules updated.')),
      );
    }

    await showDialog<void>(
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
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => save(dialogContext),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
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

  Future<void> _openStory(Map<String, dynamic> row) async {
    final entityType = _text(
      row['root_entity_type'] ?? row['entity_type'],
      fallback: '',
    );
    final entityId = _text(
      row['root_entity_id'] ?? row['entity_id'],
      fallback: '',
    );
    if (entityType.isEmpty || entityId.isEmpty) return;
    await showTransactionStoryDialog(
      context: context,
      service: _service,
      tenantId: _tenantId,
      entityType: entityType,
      entityId: entityId,
    );
  }

  Future<void> _openFinding(Map<String, dynamic> row) async {
    final findingId = _text(row['finding_id'], fallback: '');
    if (findingId.isEmpty) return;
    final detail = await _service.findingDetail(
      tenantId: _tenantId,
      findingId: findingId,
    );
    if (!mounted) return;

    final finding = _map(detail['finding']);
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
          child: Column(
            children: [
              ListTile(
                leading: Icon(_severityIcon(_text(finding['severity']))),
                title: Text(
                  _text(finding['title']),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${_text(finding['severity'])} • ${_text(finding['status'])}',
                ),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(_text(finding['description'])),
                    const SizedBox(height: 12),
                    _StructuredSection(
                      title: 'Transaction Story',
                      value: detail['transaction_story'],
                    ),
                    _StructuredSection(
                      title: 'Finding Evidence',
                      value: finding['evidence'],
                    ),
                    _StructuredSection(
                      title: 'Review History',
                      value: {
                        'reviewer_id': finding['reviewer_id'],
                        'reviewed_at': finding['reviewed_at'],
                        'review_note': finding['review_note'],
                        'resolution_note': finding['resolution_note'],
                      },
                    ),
                    if (_canActOnFindings) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Review / resolution note',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        final entityType = _text(
                          finding['entity_type'],
                          fallback: '',
                        );
                        final entityId = _text(
                          finding['entity_id'],
                          fallback: '',
                        );
                        if (entityType.isEmpty || entityId.isEmpty) return;
                        showTransactionStoryDialog(
                          context: dialogContext,
                          service: _service,
                          tenantId: _tenantId,
                          entityType: entityType,
                          entityId: entityId,
                        );
                      },
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Why / History'),
                    ),
                    const Spacer(),
                    if (_canActOnFindings)
                      PopupMenuButton<String>(
                        tooltip: 'Update finding',
                        onSelected: (status) async {
                          final note = controller.text.trim();
                          if (note.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Add a review note before changing status.',
                                ),
                              ),
                            );
                            return;
                          }
                          await _service.reviewFinding(
                            tenantId: _tenantId,
                            findingId: findingId,
                            status: status,
                            note: note,
                          );
                          if (!mounted || !dialogContext.mounted) {
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                          _refresh();
                        },
                        itemBuilder: (_) => [
                          if (_canReview)
                            const PopupMenuItem(
                              value: 'under_review',
                              child: Text('Under Review'),
                            ),
                          if (_canReview)
                            const PopupMenuItem(
                              value: 'explained',
                              child: Text('Explained'),
                            ),
                          if (_canResolve)
                            const PopupMenuItem(
                              value: 'resolved',
                              child: Text('Resolved'),
                            ),
                          if (_canResolve)
                            const PopupMenuItem(
                              value: 'escalated',
                              child: Text('Escalated'),
                            ),
                          if (_canResolve)
                            const PopupMenuItem(
                              value: 'dismissed',
                              child: Text('Dismissed'),
                            ),
                        ],
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Text(
                              'Review action',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
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
    controller.dispose();
  }

  Future<void> _openProductProfit(Map<String, dynamic> row) async {
    final variantId = _text(
      row['variant_id'] ?? row['product_variant_id'] ?? row['product_id'],
      fallback: '',
    );
    if (variantId.isEmpty) return;
    final data = await _service.productProfitExplanation(
      tenantId: _tenantId,
      variantId: variantId,
      from: _from,
      to: _to,
      locationId: _locationId,
    );
    if (!mounted) return;
    final equation = _map(data['equation']);
    final product = _map(data['product']);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Why is profit low? • ${_text(product['product_name'], fallback: _text(row['product_name']))}',
        ),
        content: SizedBox(
          width: 680,
          child: ListView(
            shrinkWrap: true,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _LargeMetric(
                    label: 'Sales',
                    value: _money(_number(equation['net_sales'])),
                  ),
                  _LargeMetric(
                    label: 'COGS',
                    value: _money(_number(equation['recognized_cogs'])),
                  ),
                  _LargeMetric(
                    label: 'Profit',
                    value: _money(_number(equation['gross_profit'])),
                  ),
                  _LargeMetric(
                    label: 'Margin',
                    value:
                        '${_number(equation['margin_pct']).toStringAsFixed(2)}%',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StructuredSection(
                title: 'Profit drivers',
                value: data['drivers'],
              ),
              _StructuredSection(title: 'Returns', value: data['returns']),
              _StructuredSection(
                title: 'Previous period',
                value: data['previous_period'],
              ),
              _StructuredSection(
                title: 'Profit change',
                value: data['profit_change'],
              ),
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
  }

  String _money(num value) {
    final symbol = widget.session.currencyCode == 'INR'
        ? '₹'
        : '${widget.session.currencyCode} ';
    return '$symbol${value.toStringAsFixed(2)}';
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({
    required this.label,
    required this.value,
    required this.icon,
    this.emphasis = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 185,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      color: emphasis && value > 0
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoneyStat extends StatelessWidget {
  const _MoneyStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _LargeMetric extends StatelessWidget {
  const _LargeMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _StructuredSection extends StatelessWidget {
  const _StructuredSection({required this.title, required this.value});
  final String title;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty(value)) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: SelectableText(
                _pretty(value),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 10),
            const Text(
              'Audit Intelligence could not load.',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            SelectableText(
              error?.toString() ?? 'Unknown error',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

IconData _severityIcon(String severity) {
  return switch (severity.toLowerCase()) {
    'high risk' || 'high_risk' => Icons.priority_high,
    'needs review' || 'needs_review' => Icons.manage_search_outlined,
    _ => Icons.info_outline,
  };
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

String _text(dynamic value, {String fallback = '—'}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

num _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

int _integer(dynamic value) => _number(value).toInt();

bool _isEmpty(dynamic value) {
  if (value == null) return true;
  if (value is Map) return value.isEmpty;
  if (value is List) return value.isEmpty;
  final text = value.toString().trim();
  return text.isEmpty || text == '{}' || text == '[]' || text == 'null';
}

String _pretty(dynamic value) {
  if (value is Map) {
    return value.entries
        .map((entry) => '${entry.key}: ${_pretty(entry.value)}')
        .join('\n');
  }
  if (value is List) {
    return value
        .asMap()
        .entries
        .map((entry) => '[${entry.key + 1}] ${_pretty(entry.value)}')
        .join('\n');
  }
  return value?.toString() ?? 'null';
}

String _dateLabel(DateTime value) {
  final d = value.day.toString().padLeft(2, '0');
  final m = value.month.toString().padLeft(2, '0');
  return '$d-$m-${value.year}';
}
