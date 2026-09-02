import 'package:flutter/material.dart';

import 'audit_intelligence_service.dart';

Future<void> showTransactionStoryDialog({
  required BuildContext context,
  required AuditIntelligenceService service,
  required String tenantId,
  required String entityType,
  required String entityId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TransactionStoryDialog(
      service: service,
      tenantId: tenantId,
      entityType: entityType,
      entityId: entityId,
    ),
  );
}

class _TransactionStoryDialog extends StatelessWidget {
  const _TransactionStoryDialog({
    required this.service,
    required this.tenantId,
    required this.entityType,
    required this.entityId,
  });

  final AuditIntelligenceService service;
  final String tenantId;
  final String entityType;
  final String entityId;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: FutureBuilder<Map<String, dynamic>>(
          future: service.transactionExplanation(
            tenantId: tenantId,
            entityType: entityType,
            entityId: entityId,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return _ErrorBody(error: snapshot.error);
            }
            final data = snapshot.data ?? const <String, dynamic>{};
            final entity = _map(data['entity']);
            final why = _map(data['why']);
            final effect = _map(why['effect']);
            final timeline = _list(data['timeline']);

            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(
                    '${_text(entity['number'], fallback: entityType)} • Transaction Story',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    _qualityLabel(entity['timeline_quality']?.toString()),
                  ),
                  trailing: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      if (_text(
                        entity['history_note'],
                        fallback: '',
                      ).isNotEmpty)
                        _InfoBanner(text: _text(entity['history_note'])),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _Fact(label: 'What', value: _text(why['what'])),
                          _Fact(label: 'Who', value: _text(why['who'])),
                          _Fact(label: 'When', value: _text(why['when'])),
                          _Fact(label: 'Where', value: _text(why['where'])),
                          _Fact(label: 'Why', value: _text(why['why'])),
                          _Fact(
                            label: 'Approval',
                            value: _text(why['approval']),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Business effect',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CountChip(
                            label: 'Payments',
                            value: effect['linked_payments'],
                          ),
                          _CountChip(
                            label: 'Stock',
                            value: effect['linked_stock_movements'],
                          ),
                          _CountChip(
                            label: 'Journals',
                            value: effect['linked_journals'],
                          ),
                          Chip(
                            avatar: Icon(
                              effect['has_gst_evidence'] == true
                                  ? Icons.verified_outlined
                                  : Icons.info_outline,
                              size: 17,
                            ),
                            label: Text(
                              effect['has_gst_evidence'] == true
                                  ? 'GST evidence linked'
                                  : 'No GST evidence',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Timeline',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (timeline.isEmpty)
                        const _InfoBanner(
                          text:
                              'No enhanced event timeline is available for this record.',
                        )
                      else
                        ...timeline.map(
                          (event) => _TimelineEvent(event: event),
                        ),
                      const SizedBox(height: 18),
                      _JsonSection(title: 'Payments', value: data['payments']),
                      _JsonSection(
                        title: 'Approvals',
                        value: data['approvals'],
                      ),
                      _JsonSection(
                        title: 'Document origin',
                        value: data['document_origins'],
                      ),
                      _JsonSection(
                        title: 'Stock movements',
                        value: data['stock_movements'],
                      ),
                      _JsonSection(title: 'Journals', value: data['journals']),
                      _JsonSection(title: 'GST evidence', value: data['gst']),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final action = _text(event['action'], fallback: 'event');
    final user = _text(event['user_name']);
    final device = _text(event['device_name']);
    final reason = _text(event['reason'], fallback: '');
    final time = _text(event['event_time']);
    final changed = event['changed_fields'];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.history_outlined, size: 18),
        ),
        title: Text(
          action.replaceAll('_', ' '),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (user != '—') user,
            if (device != '—') device,
            if (time != '—') time,
            if (reason.isNotEmpty) 'Reason: $reason',
            if (changed is List && changed.isNotEmpty)
              'Changed: ${changed.join(', ')}',
          ].join(' • '),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              SelectableText(value),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: ${_number(value).toInt()}'));
  }
}

class _JsonSection extends StatelessWidget {
  const _JsonSection({required this.title, required this.value});
  final String title;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty(value)) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            _pretty(value),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load transaction story.\n${error ?? ''}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

String _qualityLabel(String? quality) {
  return switch (quality) {
    'enhanced_v6_tracking' => 'Enhanced v6 provenance',
    'historical_reconstructed_baseline' =>
      'Historical reconstructed baseline — only recorded evidence is shown',
    'historical_baseline_only' =>
      'Historical baseline only — enhanced tracking was not available',
    _ => 'Recorded transaction evidence',
  };
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

String _text(dynamic value, {String fallback = '—'}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

num _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

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
        .map((entry) {
          return '[${entry.key + 1}] ${_pretty(entry.value)}';
        })
        .join('\n');
  }
  return value?.toString() ?? 'null';
}
