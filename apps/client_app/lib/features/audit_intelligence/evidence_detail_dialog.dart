import 'package:flutter/material.dart';

import '../../models/client_session.dart';
import 'audit_intelligence_service.dart';
import 'audit_detail_dialogs.dart';
import 'audit_widgets.dart';
import 'models/audit_evidence_models.dart';

/// Opens the authoritative evidence detail dialog for an audit record.
Future<void> showEvidenceRecordDetailDialog({
  required BuildContext context,
  required AuditIntelligenceService service,
  required String tenantId,
  required String dataset,
  required String recordId,
  required ClientSession session,
  DateTime? from,
  DateTime? to,
  String? locationId,
}) async {
  final future = service.evidenceDetail(
    tenantId: tenantId,
    dataset: dataset,
    recordId: recordId,
    locationId: locationId,
  );

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 820),
        child: Column(
          children: [
            ListTile(
              dense: true,
              title: Text(
                'Evidence Detail · $recordId',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Dataset: $dataset · Read-only investigation'),
              trailing: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<AuditEvidenceDetail>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Could not load evidence detail.\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final detail = snapshot.data!;
                  final record = detail.record;
                  final ref = auditText(
                    record['sale_number'] ??
                        record['purchase_number'] ??
                        record['invoice_number'] ??
                        record['return_number'] ??
                        record['entry_number'] ??
                        record['receipt_number'] ??
                        record['payment_number'] ??
                        record['name'] ??
                        record['reference'] ??
                        record['id'] ??
                        recordId,
                  );

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Header card with status and sensitivity
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ref,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    detail.dataset,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (detail.sensitiveValuesVisible)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Authorized Sensitive View',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Redacted View (PII Masked)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Warnings & Coverage Notices
                      if (detail.warnings.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade700),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Evidence & Coverage Notice',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    for (final w in detail.warnings)
                                      Text(w, style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Section: Captured Audit History
                      _sectionHeader(
                        context,
                        'Captured Audit History',
                        subtitle:
                            'Live captured event sequence vs historical baseline reconstruction',
                      ),
                      const SizedBox(height: 6),
                      if (detail.events.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: const Text(
                            'No native change events captured for this record. Saved values represent current state.',
                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: detail.events.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final ev = detail.events[i];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              leading: Icon(
                                ev.isRecordedEvent
                                    ? Icons.check_circle_outline
                                    : Icons.history,
                                color: ev.isRecordedEvent ? Colors.teal : Colors.amber.shade700,
                                size: 20,
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    auditLabel(ev.label),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ev.isRecordedEvent
                                          ? Colors.teal.withValues(alpha: 0.12)
                                          : Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      ev.quality,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: ev.isRecordedEvent
                                            ? Colors.teal.shade800
                                            : Colors.amber.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                '${auditDate(ev.date)} · By ${auditText(ev.actor, fallback: 'System')}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 18),

                      // Section: Linked Accounting Journals
                      if (detail.journals.isNotEmpty) ...[
                        _sectionHeader(
                          context,
                          'Linked Accounting Journals',
                          subtitle: 'Authoritative double-entry postings for this transaction',
                        ),
                        const SizedBox(height: 6),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: detail.journals.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final j = detail.journals[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.account_balance, size: 20),
                              title: Text(
                                j.entryNumber,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                '${auditDate(j.date)} · Status: ${auditLabel(j.status)} · Source: ${auditLabel(auditText(j.sourceType))}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: TextButton.icon(
                                icon: const Icon(Icons.open_in_new, size: 14),
                                label: const Text('View Journal', style: TextStyle(fontSize: 12)),
                                onPressed: () => showAuditJournalDialog(
                                  context: context,
                                  service: service,
                                  tenantId: tenantId,
                                  journal: {
                                    'id': j.id,
                                    'entry_number': j.entryNumber,
                                    'date': j.date,
                                    'status': j.status,
                                    'source_type': j.sourceType,
                                  },
                                  session: session,
                                  from: from ?? DateTime(2020),
                                  to: to ?? DateTime.now(),
                                  locationId: locationId,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Section: Related & Linked Evidence
                      if (detail.links.isNotEmpty) ...[
                        _sectionHeader(
                          context,
                          'Linked & Related Records',
                          subtitle: 'Verified database foreign keys and associated records',
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final link in detail.links)
                              ActionChip(
                                avatar: Icon(
                                  link.isParent ? Icons.arrow_upward : Icons.account_tree,
                                  size: 16,
                                ),
                                label: Text(
                                  link.isParent
                                      ? '${link.relation} (${link.label})'
                                      : '${link.label} (${link.count})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () {
                                  if (link.isParent && link.recordId != null) {
                                    showEvidenceRecordDetailDialog(
                                      context: context,
                                      service: service,
                                      tenantId: tenantId,
                                      dataset: link.dataset,
                                      recordId: link.recordId!,
                                      session: session,
                                      from: from,
                                      to: to,
                                      locationId: locationId,
                                    );
                                  } else if (link.isChild &&
                                      link.matchKey != null &&
                                      link.matchValue != null) {
                                    showRelatedEvidenceDialog(
                                      context: context,
                                      service: service,
                                      tenantId: tenantId,
                                      dataset: link.dataset,
                                      label: link.label,
                                      matchField: link.matchKey!,
                                      matchValue: link.matchValue!,
                                      session: session,
                                      locationId: locationId,
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Section: Original Saved Business Record
                      _sectionHeader(
                        context,
                        'Original Business Record Fields',
                        subtitle:
                            'Cleaned server-side evidence fields with sensitive data redaction applied',
                      ),
                      const SizedBox(height: 6),
                      AuditEvidence(
                        title: 'Record Attributes',
                        value: detail.record,
                        currency: session.currencyCode,
                        expanded: true,
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

/// Opens a dialog displaying records related to a parent via [audit_related_v704].
Future<void> showRelatedEvidenceDialog({
  required BuildContext context,
  required AuditIntelligenceService service,
  required String tenantId,
  required String dataset,
  required String label,
  required String matchField,
  required String matchValue,
  required ClientSession session,
  String? locationId,
}) async {
  var offset = 0;
  Future<AuditEvidencePage> load(int off) => service.relatedEvidence(
    tenantId: tenantId,
    dataset: dataset,
    matchField: matchField,
    matchValue: matchValue,
    locationId: locationId,
    offset: off,
    limit: 50,
  );

  var future = load(0);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1050, maxHeight: 750),
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text(
                  'Related Records · $label',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('Matching $matchField = $matchValue'),
                trailing: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<AuditEvidencePage>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Could not load related records: ${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => setDialogState(
                                  () => future = load(offset),
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final page = snapshot.data!;
                    final rows = page.rows;
                    final total = page.totalRows;

                    if (rows.isEmpty) {
                      return const Center(
                        child: Text('No related records found.'),
                      );
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final r = rows[i];
                              return ListTile(
                                dense: true,
                                title: Row(
                                  children: [
                                    Text(
                                      r.reference,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    AuditBadge(r.status),
                                  ],
                                ),
                                subtitle: Text(
                                  '${auditDate(r.date)}'
                                  '${r.party != null ? ' · ${r.party}' : ''}'
                                  '${r.amount != null ? ' · ${auditMoney(r.amount, session.currencyCode)}' : ''}'
                                  '${r.quantity != null ? ' · Qty: ${r.quantity}' : ''}'
                                  '${r.location != null ? ' · ${r.location}' : ''}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: const Icon(Icons.chevron_right, size: 18),
                                onTap: () => showEvidenceRecordDetailDialog(
                                  context: context,
                                  service: service,
                                  tenantId: tenantId,
                                  dataset: r.dataset,
                                  recordId: r.id,
                                  session: session,
                                  locationId: locationId,
                                ),
                              );
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${offset + 1}–${offset + rows.length} of $total',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Previous page',
                                onPressed: offset == 0
                                    ? null
                                    : () => setDialogState(() {
                                        offset = (offset - 50).clamp(0, total);
                                        future = load(offset);
                                      }),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              IconButton(
                                tooltip: 'Next page',
                                onPressed: offset + rows.length >= total
                                    ? null
                                    : () => setDialogState(() {
                                        offset += 50;
                                        future = load(offset);
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
}

Widget _sectionHeader(
  BuildContext context,
  String title, {
  required String subtitle,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ],
  );
}
