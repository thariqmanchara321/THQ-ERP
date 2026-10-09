import 'package:flutter/material.dart';

import '../../models/client_session.dart';
import '../../screens/sale_detail_screen.dart';
import '../../screens/purchase_detail_screen.dart';
import 'audit_intelligence_service.dart';
import 'audit_widgets.dart';
import 'transaction_story_dialog.dart';

Future<void> showAuditEvidenceDialog({
  required BuildContext context,
  required String title,
  required Map<String, dynamic> sections,
  String currency = 'INR',
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
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
              padding: const EdgeInsets.all(12),
              children: [
                for (final e in sections.entries)
                  AuditEvidence(
                    title: e.key,
                    value: e.value,
                    currency: currency,
                    expanded: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _action(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load evidence: $e')));
    }
  }
}

Future<void> showAuditLedgerDialog({
  required BuildContext context,
  required AuditIntelligenceService service,
  required ClientSession session,
  required String accountId,
  required String accountName,
  required DateTime from,
  required DateTime to,
  String? locationId,
}) => _pagedDialog(
  context: context,
  title: 'Account ledger · $accountName',
  currency: session.currencyCode,
  load: (offset, query) => service.ledger(
    tenantId: session.business.id,
    accountId: accountId,
    from: from,
    to: to,
    locationId: locationId,
    offset: offset,
    query: query,
  ),
  columns: const [
    AuditColumn('date', 'Date', compact: false),
    AuditColumn('reference', 'Reference', flex: 3),
    AuditColumn('description', 'Description', flex: 4, compact: false),
    AuditColumn('debit', 'Debit', numeric: true),
    AuditColumn('credit', 'Credit', numeric: true, compact: false),
    AuditColumn('balance', 'Balance DR ±', numeric: true),
  ],
  open: (dialogContext, row) => _action(dialogContext, () async {
    final journal = await service.journal(
      tenantId: session.business.id,
      journalId: auditText(row['journal_id']),
      locationId: locationId,
    );
    if (!dialogContext.mounted) return;
    await showAuditJournalDialog(
      context: dialogContext,
      service: service,
      tenantId: session.business.id,
      journal: journal,
      session: session,
      from: from,
      to: to,
      locationId: locationId,
    );
  }),
);

Future<void> showAuditSourceJournalsDialog({
  required BuildContext context,
  required AuditIntelligenceService service,
  required ClientSession session,
  required String source,
  required DateTime from,
  required DateTime to,
  String? locationId,
}) => _pagedDialog(
  context: context,
  title: 'Journals · ${auditLabel(source)}',
  currency: session.currencyCode,
  load: (offset, query) => service.workspace(
    tenantId: session.business.id,
    view: 'journals',
    from: from,
    to: to,
    locationId: locationId,
    offset: offset,
    query: query,
    sourceType: source,
  ),
  columns: const [
    AuditColumn('date', 'Date', compact: false),
    AuditColumn('reference', 'Reference', flex: 3),
    AuditColumn('party', 'Party', flex: 3, compact: false),
    AuditColumn('amount', 'Debit total', numeric: true),
    AuditColumn('balance_status', 'Balance'),
    AuditColumn('status', 'Posting', compact: false),
  ],
  open: (dialogContext, row) => _action(
    dialogContext,
    () => showAuditJournalDialog(
      context: dialogContext,
      service: service,
      tenantId: session.business.id,
      journal: row,
      session: session,
      from: from,
      to: to,
      locationId: locationId,
    ),
  ),
);

Future<void> _pagedDialog({
  required BuildContext context,
  required String title,
  required String currency,
  required Future<Map<String, dynamic>> Function(int, String) load,
  required List<AuditColumn> columns,
  required void Function(BuildContext, Map<String, dynamic>) open,
}) async {
  var offset = 0, query = '';
  final search = TextEditingController();
  Future<Map<String, dynamic>> future = load(0, '');
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: search,
                  onSubmitted: (v) => setState(() {
                    query = v;
                    offset = 0;
                    future = load(offset, query);
                  }),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search this ledger and press Enter',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: () => setState(() {
                        query = search.text;
                        offset = 0;
                        future = load(offset, query);
                      }),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    border: const OutlineInputBorder(),
                  ),
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Could not load ledger. ${snapshot.error}'),
                            TextButton(
                              onPressed: () =>
                                  setState(() => future = load(offset, query)),
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
                        if (data.containsKey('opening'))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: AuditMetrics({
                              'Opening DR ±': auditMoney(
                                data['opening'],
                                currency,
                              ),
                              'Closing DR ±': auditMoney(
                                data['closing'],
                                currency,
                              ),
                            }),
                          ),
                        Expanded(
                          child: AuditTable(
                            columns: columns,
                            rows: rows,
                            currency: currency,
                            onOpen: (r) => open(context, r),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  total == 0
                                      ? '0 records'
                                      : '${offset + 1}–${offset + rows.length} of $total',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Previous page',
                                onPressed: offset == 0
                                    ? null
                                    : () => setState(() {
                                        offset = (offset - 50).clamp(0, total);
                                        future = load(offset, query);
                                      }),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              IconButton(
                                tooltip: 'Next page',
                                onPressed: offset + rows.length >= total
                                    ? null
                                    : () => setState(() {
                                        offset += 50;
                                        future = load(offset, query);
                                      }),
                                icon: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
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
  search.dispose();
}

Future<void> showAuditJournalDialog({
  required BuildContext context,
  required AuditIntelligenceService service,
  required String tenantId,
  required Map<String, dynamic> journal,
  required ClientSession session,
  required DateTime from,
  required DateTime to,
  String? locationId,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 740),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(
              'Journal · ${auditText(journal['entry_number'] ?? journal['reference'])}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${auditDate(journal['date'])} · ${auditText(journal['type'])} · ${auditText(journal['party'])}',
            ),
            trailing: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                AuditBadge(auditText(journal['status'])),
                AuditBadge(auditText(journal['balance_status'])),
                TextButton.icon(
                  onPressed: () => _action(
                    context,
                    () => showTransactionStoryDialog(
                      context: context,
                      service: service,
                      tenantId: tenantId,
                      entityType: 'journal_entry',
                      entityId: auditText(
                        journal['journal_id'] ?? journal['id'],
                      ),
                      session: session,
                      from: from,
                      to: to,
                      locationId: locationId,
                    ),
                  ),
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Transaction history'),
                ),
                if (journal['document_type'] == 'sale' ||
                    journal['document_type'] == 'purchase')
                  TextButton.icon(
                    onPressed: () => _action(context, () async {
                      final screen = journal['document_type'] == 'sale'
                          ? SaleDetailScreen(
                              session: session,
                              saleId: auditText(journal['document_id']),
                            )
                          : PurchaseDetailScreen(
                              session: session,
                              purchaseId: auditText(journal['document_id']),
                            );
                      await Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (_) => screen));
                    }),
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: const Text('Open source document'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AuditMetrics({
              'Debit total': auditMoney(journal['debit'], session.currencyCode),
              'Credit total': auditMoney(
                journal['credit'],
                session.currencyCode,
              ),
              'Difference': auditMoney(
                journal['difference'],
                session.currencyCode,
              ),
            }),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(auditText(journal['description'])),
                const SizedBox(height: 8),
                AuditTable(
                  shrinkWrap: true,
                  currency: session.currencyCode,
                  columns: const [
                    AuditColumn('account_name', 'Account', flex: 4),
                    AuditColumn('party', 'Party', flex: 3, compact: false),
                    AuditColumn('debit', 'Debit', numeric: true),
                    AuditColumn('credit', 'Credit', numeric: true),
                  ],
                  rows: auditRows(journal['lines']),
                  onOpen: (r) => _action(
                    context,
                    () => showAuditLedgerDialog(
                      context: context,
                      service: service,
                      session: session,
                      accountId: auditText(r['account_id']),
                      accountName: auditText(r['account_name']),
                      from: from,
                      to: to,
                      locationId: locationId,
                    ),
                  ),
                ),
                AuditEvidence(
                  title: 'Source details',
                  value: journal['source_details'],
                  currency: session.currencyCode,
                  expanded: true,
                ),
                AuditEvidence(
                  title: 'Reversal links',
                  value: journal['reversals'],
                  currency: session.currencyCode,
                  expanded: true,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<bool> showAuditFindingDialog({
  required BuildContext context,
  required AuditIntelligenceService service,
  required ClientSession session,
  required String findingId,
  required DateTime from,
  required DateTime to,
  String? locationId,
}) async {
  final data = await service.findingDetail(
    tenantId: session.business.id,
    findingId: findingId,
  );
  if (!context.mounted) return false;
  final finding = auditMap(data['finding']), note = TextEditingController();
  var busy = false;
  String? error;
  final actions = <String, String>{};
  if (session.hasPermission('audit_center.review')) {
    actions.addAll({
      'open': 'Reopen',
      'under_review': 'Under review',
      'explained': 'Explained',
    });
  }
  if (session.hasPermission('audit_center.resolve')) {
    actions.addAll({
      'resolved': 'Resolved',
      'escalated': 'Escalated',
      'dismissed': 'Dismissed',
    });
  }
  final changed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text(
                  auditText(finding['title']),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(auditText(finding['entity_reference'])),
                trailing: IconButton(
                  tooltip: 'Close',
                  onPressed: busy ? null : () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    AuditBadge(auditText(finding['severity'])),
                    const SizedBox(width: 8),
                    AuditBadge(auditText(finding['status'])),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _action(
                        context,
                        () => showTransactionStoryDialog(
                          context: context,
                          service: service,
                          tenantId: session.business.id,
                          entityType: auditText(finding['entity_type']),
                          entityId: auditText(finding['entity_id']),
                          session: session,
                          from: from,
                          to: to,
                          locationId: locationId,
                        ),
                      ),
                      icon: const Icon(Icons.history, size: 16),
                      label: const Text('Full history'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(auditText(finding['description'])),
                    AuditEvidence(
                      title: 'Finding evidence',
                      value: finding['evidence'],
                      currency: session.currencyCode,
                      expanded: true,
                    ),
                    AuditEvidence(
                      title: 'Recorded events',
                      value: data['transaction_story'],
                      currency: session.currencyCode,
                    ),
                    AuditEvidence(
                      title: 'Review history',
                      value:
                          data['review_history'] ??
                          {
                            'Reviewed at': finding['reviewed_at'],
                            'Review note': finding['review_note'],
                            'Resolution note': finding['resolution_note'],
                          },
                      currency: session.currencyCode,
                      expanded: true,
                    ),
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      TextField(
                        controller: note,
                        minLines: 1,
                        maxLines: 3,
                        enabled: !busy,
                        decoration: InputDecoration(
                          labelText: 'Review note (required)',
                          errorText: error,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: PopupMenuButton<String>(
                          enabled: !busy,
                          tooltip: 'Review action',
                          itemBuilder: (_) => actions.entries
                              .map(
                                (e) => PopupMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onSelected: (status) async {
                            if (note.text.trim().isEmpty) {
                              setState(
                                () => error =
                                    'Add a note before updating the finding.',
                              );
                              return;
                            }
                            setState(() {
                              busy = true;
                              error = null;
                            });
                            try {
                              await service.reviewFinding(
                                tenantId: session.business.id,
                                findingId: findingId,
                                status: status,
                                note: note.text,
                              );
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (e) {
                              if (context.mounted) {
                                setState(() {
                                  busy = false;
                                  error = 'Update failed: $e';
                                });
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              busy ? 'Saving…' : 'Review action ▾',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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
    ),
  );
  note.dispose();
  return changed ?? false;
}
