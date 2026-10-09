import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-only audit and account evidence; POS billing writers stay independent.
class PosAuditHistoryScreen extends StatefulWidget {
  const PosAuditHistoryScreen({
    super.key,
    required this.tenantId,
    this.locationId,
  });
  final String tenantId;
  final String? locationId;
  @override
  State<PosAuditHistoryScreen> createState() => _PosAuditHistoryScreenState();
}

class _PosAuditHistoryScreenState extends State<PosAuditHistoryScreen> {
  final _search = TextEditingController();
  late DateTime _from, _to;
  late Future<Map<String, dynamic>> _future;
  int _offset = 0;
  String _query = '';
  SupabaseClient get _client => Supabase.instance.client;
  String _date(DateTime d) => d.toIso8601String().substring(0, 10);
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = _to = DateTime(now.year, now.month, now.day);
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async => auditMap(
    await _client.rpc(
      'audit_workspace_page_v703',
      params: {
        'p_tenant_id': widget.tenantId,
        'p_view': 'activity',
        'p_from': _date(_from),
        'p_to': _date(_to),
        'p_location_id': widget.locationId,
        'p_query': _query,
        'p_offset': _offset,
        'p_limit': 50,
        'p_source_type': '',
      },
    ),
  );
  Future<void> _guard(Future<void> Function() task) async {
    try {
      await task();
    } catch (e) {
      if (mounted) {
        ThqNotify.error(context, 'Could not load audit evidence: $e');
      }
    }
  }

  Future<void> _period() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range == null || !mounted) return;
    setState(() {
      _from = range.start;
      _to = range.end;
      _offset = 0;
      _future = _load();
    });
  }

  Future<void> _story(Map<String, dynamic> row) async {
    final data = auditMap(
      await _client.rpc(
        'transaction_explain_v600',
        params: {
          'p_tenant_id': widget.tenantId,
          'p_entity_type': row['root_entity_type'] ?? row['entity_type'],
          'p_entity_id': row['root_entity_id'] ?? row['entity_id'],
          'p_event_limit': 2000,
        },
      ),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text('History · ${auditText(row['reference'])}'),
                trailing: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(auditText(data['historical_notice'])),
                    for (final e in auditRows(data['transaction_story']))
                      AuditEvidence(
                        title:
                            '${auditDate(e['event_time'])} · ${auditLabel(auditText(e['action']))}',
                        value: {
                          'User': auditMap(e['actor'])['name'],
                          'Device': auditMap(e['device'])['name'],
                          'Reason': e['reason'],
                          'changed_fields': e['changed_fields'],
                          'before': e['before'],
                          'after': e['after'],
                          'approval': e['approval'],
                        },
                      ),
                    const SizedBox(height: 10),
                    const Text(
                      'Journals',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    AuditTable(
                      shrinkWrap: true,
                      columns: const [
                        AuditColumn('entry_number', 'Journal', flex: 3),
                        AuditColumn('type', 'Source', compact: false),
                        AuditColumn('debit', 'Debit', numeric: true),
                        AuditColumn('credit', 'Credit', numeric: true),
                      ],
                      rows: auditRows(data['journals']),
                      onOpen: (j) => _guard(() => _journal(j)),
                    ),
                    AuditEvidence(
                      title: 'Payments',
                      value: data['payments'],
                      expanded: true,
                    ),
                    AuditEvidence(
                      title: 'Saved transaction',
                      value: data['current_record'],
                    ),
                    AuditEvidence(
                      title: 'Stock movements',
                      value: data['stock_movements'],
                    ),
                    AuditEvidence(
                      title: 'GST evidence',
                      value: data['gst_evidence'],
                    ),
                    AuditEvidence(title: 'Approvals', value: data['approvals']),
                    AuditEvidence(
                      title: 'Earlier audit evidence',
                      value: data['legacy_audit_evidence'],
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

  Future<void> _journal(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 650),
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text('Journal · ${auditText(row['entry_number'])}'),
                trailing: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: AuditMetrics({
                  'Debit': auditMoney(row['debit']),
                  'Credit': auditMoney(row['credit']),
                  'Difference': auditMoney(row['difference']),
                }),
              ),
              Expanded(
                child: AuditTable(
                  columns: const [
                    AuditColumn('account_name', 'Account', flex: 4),
                    AuditColumn('party', 'Party', compact: false),
                    AuditColumn('debit', 'Debit', numeric: true),
                    AuditColumn('credit', 'Credit', numeric: true),
                  ],
                  rows: auditRows(row['lines']),
                  onOpen: (a) => _guard(() => _account(a)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _account(Map<String, dynamic> account) async {
    var offset = 0;
    Future<Map<String, dynamic>> load() async => auditMap(
      await _client.rpc(
        'audit_ledger_v703',
        params: {
          'p_tenant_id': widget.tenantId,
          'p_account_id': account['account_id'],
          'p_from': _date(_from),
          'p_to': _date(_to),
          'p_location_id': widget.locationId,
          'p_offset': offset,
          'p_limit': 50,
        },
      ),
    );
    var future = load();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 700),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  title: Text('Ledger · ${auditText(account['account_name'])}'),
                  trailing: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load account: ${snapshot.error}',
                          ),
                        );
                      }
                      final data = snapshot.data ?? {},
                          rows = auditRows(data['rows']),
                          total = auditNumber(data['total_rows']).toInt();
                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: AuditMetrics({
                              'Opening DR ±': auditMoney(data['opening']),
                              'Closing DR ±': auditMoney(data['closing']),
                            }),
                          ),
                          Expanded(
                            child: AuditTable(
                              columns: const [
                                AuditColumn('reference', 'Reference', flex: 3),
                                AuditColumn('date', 'Date', compact: false),
                                AuditColumn('debit', 'Debit', numeric: true),
                                AuditColumn(
                                  'credit',
                                  'Credit',
                                  numeric: true,
                                  compact: false,
                                ),
                                AuditColumn(
                                  'balance',
                                  'Balance DR ±',
                                  numeric: true,
                                ),
                              ],
                              rows: rows,
                              onOpen: (r) => _guard(() async {
                                final j = auditMap(
                                  await _client.rpc(
                                    'audit_journal_v703',
                                    params: {
                                      'p_tenant_id': widget.tenantId,
                                      'p_journal_id': r['journal_id'],
                                      'p_location_id': widget.locationId,
                                    },
                                  ),
                                );
                                if (mounted) await _journal(j);
                              }),
                            ),
                          ),
                          Row(
                            children: [
                              const SizedBox(width: 12),
                              Expanded(child: Text('$total matching records')),
                              IconButton(
                                tooltip: 'Previous page',
                                onPressed: offset == 0
                                    ? null
                                    : () => setState(() {
                                        offset -= 50;
                                        future = load();
                                      }),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              IconButton(
                                tooltip: 'Next page',
                                onPressed: offset + rows.length >= total
                                    ? null
                                    : () => setState(() {
                                        offset += 50;
                                        future = load();
                                      }),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Transaction history'),
      actions: [
        IconButton(
          tooltip: 'Period',
          onPressed: _period,
          icon: const Icon(Icons.date_range),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => setState(() => _future = _load()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            onSubmitted: (v) => setState(() {
              _query = v;
              _offset = 0;
              _future = _load();
            }),
            decoration: InputDecoration(
              isDense: true,
              labelText:
                  'Search activity · ${auditDate(_date(_from))} – ${auditDate(_date(_to))}',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Could not load history. ${snapshot.error}'),
                      TextButton(
                        onPressed: () => setState(() => _future = _load()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final data = snapshot.data ?? {},
                  rows = auditRows(data['rows']),
                  total = auditNumber(data['total_rows']).toInt();
              return Column(
                children: [
                  Expanded(
                    child: AuditTable(
                      columns: const [
                        AuditColumn('date', 'When', compact: false),
                        AuditColumn('reference', 'Reference', flex: 3),
                        AuditColumn('title', 'Event', flex: 4),
                        AuditColumn('actor', 'User', compact: false),
                        AuditColumn('device', 'Device', compact: false),
                      ],
                      rows: rows,
                      onOpen: (r) => _guard(() => _story(r)),
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          total == 0
                              ? 'No recorded activity'
                              : '${_offset + 1}–${_offset + rows.length} of $total',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _offset == 0
                            ? null
                            : () => setState(() {
                                _offset -= 50;
                                _future = _load();
                              }),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: _offset + rows.length >= total
                            ? null
                            : () => setState(() {
                                _offset += 50;
                                _future = _load();
                              }),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
