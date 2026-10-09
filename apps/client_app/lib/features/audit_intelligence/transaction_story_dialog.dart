import 'package:flutter/material.dart';

import '../../models/client_session.dart';
import 'audit_intelligence_service.dart';
import 'audit_detail_dialogs.dart';
import 'audit_widgets.dart';

Future<void> showTransactionStoryDialog({
  required BuildContext context,
  required AuditIntelligenceService service,
  required String tenantId,
  required String entityType,
  required String entityId,
  ClientSession? session,
  DateTime? from,
  DateTime? to,
  String? locationId,
}) {
  final future = service.transactionExplanation(
    tenantId: tenantId,
    entityType: entityType,
    entityId: entityId,
    eventLimit: 2000,
  );
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 780),
        child: Column(
          children: [
            ListTile(
              dense: true,
              title: const Text(
                'Transaction story',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Could not load transaction history. ${snapshot.error}',
                        ),
                      ),
                    );
                  }
                  final data = snapshot.data ?? {},
                      current = auditMap(data['current_record']),
                      events = auditRows(data['transaction_story']),
                      journals = auditRows(data['journals']);
                  final currency = session?.currencyCode ?? 'INR';
                  Future<void> openJournal(Map<String, dynamic> row) async {
                    if (session == null) return;
                    await showAuditJournalDialog(
                      context: context,
                      service: service,
                      tenantId: tenantId,
                      journal: row,
                      session: session,
                      from: from ?? DateTime(2020),
                      to: to ?? DateTime.now(),
                      locationId: locationId,
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Text(
                        auditText(
                          current['sale_number'] ??
                              current['purchase_number'] ??
                              current['invoice_number'] ??
                              current['entry_number'],
                          fallback: auditLabel(entityType),
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          auditText(data['historical_notice']),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      AuditMetrics({
                        'Recorded events': '${events.length}',
                        'Payments': '${auditRows(data['payments']).length}',
                        'Journals': '${journals.length}',
                        'Stock movements':
                            '${auditRows(data['stock_movements']).length}',
                      }),
                      const SizedBox(height: 12),
                      const Text(
                        'Recorded timeline',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (events.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No enhanced event timeline was recorded. Saved records and linked evidence are shown below.',
                          ),
                        ),
                      for (final e in events)
                        AuditEvidence(
                          title:
                              '${auditDate(e['event_time'])} · ${auditLabel(auditText(e['action']))}',
                          currency: currency,
                          value: {
                            'User':
                                auditMap(e['actor'])['name'] ?? 'Not recorded',
                            'Device':
                                auditMap(e['device'])['name'] ?? 'Not recorded',
                            'App': auditMap(e['device'])['app'],
                            'Reference': e['entity_reference'],
                            'Reason': e['reason'],
                            'changed_fields': e['changed_fields'],
                            'before': e['before'],
                            'after': e['after'],
                            'approval': e['approval'],
                            'evidence_quality': e['evidence_quality'],
                          },
                        ),
                      if (events.length >= 2000)
                        const Text(
                          'The first 2,000 recorded events are shown. Narrow the activity period for more recent events.',
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Accounting evidence',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      AuditTable(
                        shrinkWrap: true,
                        currency: currency,
                        columns: const [
                          AuditColumn('date', 'Date', compact: false),
                          AuditColumn('entry_number', 'Journal', flex: 3),
                          AuditColumn(
                            'type',
                            'Source',
                            flex: 3,
                            compact: false,
                          ),
                          AuditColumn('debit', 'Debit', numeric: true),
                          AuditColumn(
                            'credit',
                            'Credit',
                            numeric: true,
                            compact: false,
                          ),
                          AuditColumn('balance_status', 'Balance'),
                        ],
                        rows: journals,
                        onOpen: session == null
                            ? null
                            : (r) async {
                                try {
                                  await openJournal(r);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not open journal: $e',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                      if (session == null)
                        for (final j in journals)
                          AuditEvidence(
                            title:
                                '${auditText(j['entry_number'])} · Account lines',
                            value: j['lines'],
                            currency: currency,
                          ),
                      AuditEvidence(
                        title: 'Saved transaction',
                        value: current,
                        currency: currency,
                      ),
                      AuditEvidence(
                        title: 'Payments',
                        value: data['payments'],
                        currency: currency,
                        expanded: true,
                      ),
                      AuditEvidence(
                        title: 'Approvals',
                        value: data['approvals'],
                        currency: currency,
                      ),
                      AuditEvidence(
                        title: 'Document origin',
                        value: data['origin'],
                        currency: currency,
                      ),
                      AuditEvidence(
                        title: 'Stock movements',
                        value: data['stock_movements'],
                        currency: currency,
                      ),
                      AuditEvidence(
                        title: 'GST evidence',
                        value: data['gst_evidence'],
                        currency: currency,
                      ),
                      AuditEvidence(
                        title: 'Earlier audit evidence',
                        value: data['legacy_audit_evidence'],
                        currency: currency,
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
  );
}
