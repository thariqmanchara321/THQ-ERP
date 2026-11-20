import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/client_session.dart';
import '../../screens/sale_detail_screen.dart';
import '../../screens/purchase_detail_screen.dart';
import 'audit_intelligence_service.dart';
import 'models/audit_review_models.dart';
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
  final changed = await showDialog<bool>(
    context: context,
    builder: (context) => _AuditFindingReviewDialog(
      service: service,
      session: session,
      findingId: findingId,
      from: from,
      to: to,
      locationId: locationId,
    ),
  );
  return changed ?? false;
}

class _AuditFindingReviewDialog extends StatefulWidget {
  const _AuditFindingReviewDialog({
    required this.service,
    required this.session,
    required this.findingId,
    required this.from,
    required this.to,
    this.locationId,
  });

  final AuditIntelligenceService service;
  final ClientSession session;
  final String findingId;
  final DateTime from;
  final DateTime to;
  final String? locationId;

  @override
  State<_AuditFindingReviewDialog> createState() =>
      _AuditFindingReviewDialogState();
}

class _AuditFindingReviewDialogState extends State<_AuditFindingReviewDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AuditFindingReviewDetail? _detail;
  List<AuditAssignableUser> _assignableUsers = [];
  bool _loading = true;
  bool _busy = false;
  bool _hasChanged = false;
  String? _error;

  final _noteController = TextEditingController();
  final _refController = TextEditingController();
  String _selectedNoteType = 'investigation';

  bool get _canReview => widget.session.hasPermission('audit_center.review');
  bool get _canResolve => widget.session.hasPermission('audit_center.resolve');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.service.findingDetailV704(
          tenantId: widget.session.business.id,
          findingId: widget.findingId,
        ),
        widget.service.assignableUsers(tenantId: widget.session.business.id),
      ]);
      if (mounted) {
        setState(() {
          _detail = results[0] as AuditFindingReviewDetail;
          _assignableUsers = results[1] as List<AuditAssignableUser>;
          _loading = false;
        });
      }
    } catch (e) {
      try {
        final legacy = await widget.service.findingDetail(
          tenantId: widget.session.business.id,
          findingId: widget.findingId,
        );
        if (mounted) {
          setState(() {
            _detail = AuditFindingReviewDetail.fromJson(legacy);
            _assignableUsers = const [];
            _loading = false;
          });
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load finding details: $e';
        });
      }
    }
  }

  Future<void> _showAssignDialog() async {
    if (_detail == null) return;
    String selectedUserId = _detail!.assignedTo ?? '';
    String selectedPriority = _detail!.priority;
    DateTime? selectedDueDate = _detail!.dueDate != null
        ? DateTime.tryParse(_detail!.dueDate!)
        : null;
    final reasonController = TextEditingController();
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => AlertDialog(
          title: Text('Assign Finding · ${_detail!.reference}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedUserId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Assignee',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Unassigned'),
                      ),
                      ..._assignableUsers.map(
                        (u) => DropdownMenuItem(
                          value: u.userId,
                          child: Text(
                            '${u.username}${u.email != null ? ' (${u.email})' : ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) =>
                        setModalState(() => selectedUserId = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPriority,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'critical',
                        child: Text('Critical (immediate response required)'),
                      ),
                      DropdownMenuItem(
                        value: 'high',
                        child: Text('High priority'),
                      ),
                      DropdownMenuItem(
                        value: 'medium',
                        child: Text('Medium priority'),
                      ),
                      DropdownMenuItem(
                        value: 'low',
                        child: Text('Low priority'),
                      ),
                    ],
                    onChanged: (v) =>
                        setModalState(() => selectedPriority = v ?? 'medium'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedDueDate == null
                              ? 'Due date: Not set'
                              : 'Due date: ${auditDate(selectedDueDate!.toIso8601String().substring(0, 10))}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogCtx,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 30),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            initialDate: selectedDueDate ?? DateTime.now(),
                          );
                          if (picked != null) {
                            setModalState(() => selectedDueDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: const Text('Pick Date'),
                      ),
                      if (selectedDueDate != null)
                        IconButton(
                          tooltip: 'Clear due date',
                          onPressed: () =>
                              setModalState(() => selectedDueDate = null),
                          icon: const Icon(Icons.clear, size: 16),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Reason for assignment (optional)',
                      border: const OutlineInputBorder(),
                      errorText: dialogError,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await widget.service.assignFinding(
                    tenantId: widget.session.business.id,
                    findingId: widget.findingId,
                    assignTo: selectedUserId.isEmpty ? null : selectedUserId,
                    priority: selectedPriority,
                    dueDate: selectedDueDate,
                    reason: reasonController.text.trim().isEmpty
                        ? null
                        : reasonController.text.trim(),
                  );
                  _hasChanged = true;
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  await _load();
                  if (mounted) {
                    ThqNotify.success(context, 'Finding assignment updated.');
                  }
                } catch (e) {
                  setModalState(
                    () => dialogError = 'Could not assign finding: $e',
                  );
                }
              },
              child: const Text('Save assignment'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
  }

  Future<void> _showStatusDialog() async {
    if (_detail == null) return;
    final availableStatuses = <String, String>{};
    if (_canReview) {
      availableStatuses.addAll({
        'open': 'Open / Reopen',
        'under_review': 'Under review',
        'awaiting_info': 'Awaiting information',
        'explained': 'Explained by client',
      });
    }
    if (_canResolve) {
      availableStatuses.addAll({
        'resolved': 'Mark resolved',
        'escalated': 'Escalate to management',
        'dismissed': 'Dismiss finding',
      });
    }

    if (availableStatuses.isEmpty) {
      ThqNotify.error(context, 'You do not have review permissions.');
      return;
    }

    String selectedStatus = availableStatuses.containsKey(_detail!.status)
        ? _detail!.status
        : availableStatuses.keys.first;
    final noteController = TextEditingController();
    final resolutionController = TextEditingController();
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => AlertDialog(
          title: Text('Review Workflow Action · ${_detail!.reference}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Target status',
                      border: OutlineInputBorder(),
                    ),
                    items: availableStatuses.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setModalState(() => selectedStatus = v);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Review note (required)',
                      border: const OutlineInputBorder(),
                      errorText: dialogError,
                    ),
                  ),
                  if (selectedStatus == 'resolved' ||
                      selectedStatus == 'dismissed') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: resolutionController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Resolution summary (recommended)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (noteController.text.trim().isEmpty) {
                  setModalState(
                    () => dialogError = 'A review note is required.',
                  );
                  return;
                }
                try {
                  await widget.service.updateFindingStatus(
                    tenantId: widget.session.business.id,
                    findingId: widget.findingId,
                    status: selectedStatus,
                    note: noteController.text.trim(),
                    resolutionNote:
                        resolutionController.text.trim().isEmpty
                            ? null
                            : resolutionController.text.trim(),
                  );
                  _hasChanged = true;
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  await _load();
                  if (mounted) {
                    ThqNotify.success(
                      context,
                      'Finding status updated to ${auditLabel(selectedStatus)}.',
                    );
                  }
                } catch (e) {
                  setModalState(
                    () => dialogError = 'Status update failed: $e',
                  );
                }
              },
              child: const Text('Submit action'),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    resolutionController.dispose();
  }

  Future<void> _addNote() async {
    final noteText = _noteController.text.trim();
    if (noteText.isEmpty) {
      ThqNotify.error(context, 'Please enter a note before submitting.');
      return;
    }
    setState(() => _busy = true);
    try {
      final refs = _refController.text.trim().isNotEmpty
          ? [
              {
                'reference': _refController.text.trim(),
                'type': 'user_reference',
              },
            ]
          : const <Map<String, dynamic>>[];
      await widget.service.addFindingNote(
        tenantId: widget.session.business.id,
        findingId: widget.findingId,
        note: noteText,
        noteType: _selectedNoteType,
        evidenceRefs: refs,
      );
      _noteController.clear();
      _refController.clear();
      _hasChanged = true;
      await _load();
      if (mounted) {
        ThqNotify.success(context, 'Investigation note added.');
      }
    } catch (e) {
      if (mounted) {
        ThqNotify.error(context, 'Could not add note: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _detail == null) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 200),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null && _detail == null) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, _hasChanged),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final detail = _detail!;
    final isOverdue =
        detail.dueDate != null &&
        DateTime.tryParse(detail.dueDate!)?.isBefore(DateTime.now()) == true &&
        !['resolved', 'dismissed'].contains(detail.status);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            ListTile(
              dense: true,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      detail.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                '${detail.reference} · Rule: ${detail.ruleName} (v${detail.finding['rule_version'] ?? 1})',
              ),
              trailing: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context, _hasChanged),
                icon: const Icon(Icons.close),
              ),
            ),
            // Badges & Toolbar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  AuditBadge(detail.priority),
                  AuditBadge(detail.severity),
                  AuditBadge(detail.status),
                  if (isOverdue)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Overdue',
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (_canReview || _canResolve) ...[
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _showAssignDialog,
                      icon: const Icon(Icons.person_outline, size: 15),
                      label: Text(
                        detail.assignedTo == null
                            ? 'Assign reviewer'
                            : 'Reassign (${detail.assignee?['username'] ?? 'User'})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _showStatusDialog,
                      icon: const Icon(Icons.rule, size: 15),
                      label: const Text(
                        'Review action ▾',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: () => _action(
                      context,
                      () => showTransactionStoryDialog(
                        context: context,
                        service: widget.service,
                        tenantId: widget.session.business.id,
                        entityType: detail.entityType,
                        entityId: detail.entityId,
                        session: widget.session,
                        from: widget.from,
                        to: widget.to,
                        locationId: widget.locationId,
                      ),
                    ),
                    icon: const Icon(Icons.history, size: 15),
                    label: const Text(
                      'Transaction story',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (detail.entityType == 'sale' ||
                      detail.entityType == 'purchase')
                    TextButton.icon(
                      onPressed: () => _action(context, () async {
                        final screen = detail.entityType == 'sale'
                            ? SaleDetailScreen(
                                session: widget.session,
                                saleId: detail.entityId,
                              )
                            : PurchaseDetailScreen(
                                session: widget.session,
                                purchaseId: detail.entityId,
                              );
                        await Navigator.of(
                          context,
                        ).push(MaterialPageRoute(builder: (_) => screen));
                      }),
                      icon: const Icon(Icons.receipt_long, size: 15),
                      label: const Text(
                        'Open document',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Tab bar
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              tabs: [
                const Tab(
                  icon: Icon(Icons.shield_outlined, size: 16),
                  text: 'Risk intelligence',
                ),
                Tab(
                  icon: const Icon(Icons.comment_outlined, size: 16),
                  text: 'Notes (${detail.notes.length})',
                ),
                const Tab(
                  icon: Icon(Icons.receipt_long_outlined, size: 16),
                  text: 'Evidence & story',
                ),
                Tab(
                  icon: const Icon(Icons.timeline_outlined, size: 16),
                  text: 'Audit trail (${detail.history.length})',
                ),
              ],
            ),
            const Divider(height: 1),
            // Tab contents
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRiskIntelligenceTab(detail),
                  _buildNotesTab(detail),
                  _buildEvidenceTab(detail),
                  _buildHistoryTab(detail),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskIntelligenceTab(AuditFindingReviewDetail detail) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Exposure & Classification summary card
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FINANCIAL EXPOSURE / IMPACT',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        auditMoney(
                          detail.financialExposure,
                          widget.session.currencyCode,
                        ),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: detail.isConfirmed
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        detail.isConfirmed
                            ? Icons.warning
                            : Icons.auto_graph,
                        size: 16,
                        color: detail.isConfirmed
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        detail.isConfirmed
                            ? 'Confirmed Discrepancy'
                            : 'Operational Anomaly',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: detail.isConfirmed
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // What happened
        _buildSectionCard(
          title: 'What Happened',
          icon: Icons.info_outline,
          content: Text(
            detail.whatHappened,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),

        // Why detected
        _buildSectionCard(
          title: 'Detection Rule & Logic',
          icon: Icons.rule,
          content: Text(
            detail.whyDetected,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),

        // Recommended steps
        _buildSectionCard(
          title: 'Recommended Investigation Steps',
          icon: Icons.checklist,
          content: Text(
            detail.investigationSteps,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),

        // Duplicate / Related cluster warning
        if (detail.isDuplicate || detail.duplicates.isNotEmpty)
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.copy_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Duplicate / Related Pattern Alert',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      if (detail.duplicateGroupId != null)
                        Text(
                          'Cluster: ${detail.duplicateGroupId}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Identified ${detail.duplicates.length} duplicate or related records sharing critical reference numbers or transaction values.',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (detail.duplicates.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    AuditTable(
                      shrinkWrap: true,
                      currency: widget.session.currencyCode,
                      columns: const [
                        AuditColumn('entity_reference', 'Reference', flex: 3),
                        AuditColumn('status', 'Status'),
                        AuditColumn('severity', 'Risk'),
                        AuditColumn(
                          'financial_exposure',
                          'Exposure',
                          numeric: true,
                        ),
                      ],
                      rows: detail.duplicates,
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Ownership and Due Date summary
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Review Assignment & Lifecycle',
          icon: Icons.assignment_ind_outlined,
          content: Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _infoItem(
                'Assignee',
                detail.assignee?['username'] ?? 'Unassigned',
              ),
              _infoItem('Priority', auditLabel(detail.priority)),
              _infoItem(
                'Due date',
                detail.dueDate != null
                    ? auditDate(detail.dueDate!)
                    : 'Not specified',
              ),
              _infoItem(
                'Detected at',
                auditDate(detail.finding['detected_at']),
              ),
              if (detail.finding['assigned_at'] != null)
                _infoItem(
                  'Assigned at',
                  auditDate(detail.finding['assigned_at']),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotesTab(AuditFindingReviewDetail detail) {
    return Column(
      children: [
        Expanded(
          child: detail.notes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.note_alt_outlined,
                        size: 40,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No investigation notes recorded.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const Text(
                        'Add the first note below to log findings, explanations or requested evidence.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: detail.notes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final note = detail.notes[i];
                    return Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color:
                              Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AuditBadge(note.noteType),
                                const SizedBox(width: 8),
                                Text(
                                  note.authorName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  auditDate(
                                    note.createdAt.toIso8601String(),
                                  ),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              note.note,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            if (note.evidenceReferences.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final ref in note.evidenceReferences)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      labelPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                      label: Text(
                                        auditText(
                                          ref['reference'] ??
                                              ref['label'] ??
                                              ref['id'],
                                        ),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        // Add note form
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedNoteType,
                      isExpanded: true,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Note type',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'investigation',
                          child: Text('Investigation note'),
                        ),
                        DropdownMenuItem(
                          value: 'evidence_request',
                          child: Text('Evidence request'),
                        ),
                        DropdownMenuItem(
                          value: 'client_explanation',
                          child: Text('Client explanation'),
                        ),
                        DropdownMenuItem(
                          value: 'internal_note',
                          child: Text('Internal auditor note'),
                        ),
                        DropdownMenuItem(
                          value: 'auditor_conclusion',
                          child: Text('Auditor conclusion'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _selectedNoteType = v);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _refController,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Attached evidence reference (optional)',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _noteController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Add an immutable investigation note…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _addNote,
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, size: 16),
                    label: const Text('Post note'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEvidenceTab(AuditFindingReviewDetail detail) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AuditEvidence(
          title: 'Structured Finding Evidence',
          value: detail.evidence,
          currency: widget.session.currencyCode,
          expanded: true,
        ),
        const SizedBox(height: 16),
        if (detail.transactionStory.isNotEmpty) ...[
          const Text(
            'Recorded Transaction Timeline',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          AuditTable(
            shrinkWrap: true,
            currency: widget.session.currencyCode,
            columns: const [
              AuditColumn('event_time', 'When', compact: false),
              AuditColumn('action', 'Action'),
              AuditColumn('actor_name', 'Actor', compact: false),
              AuditColumn('entity_reference', 'Reference', flex: 3),
            ],
            rows: detail.transactionStory,
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryTab(AuditFindingReviewDetail detail) {
    if (detail.history.isEmpty) {
      return const Center(
        child: Text('No historical review transitions recorded.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: detail.history.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = detail.history[i];
        final beforeStatus = item.beforeState?['status'];
        final afterStatus = item.afterState?['status'];
        final afterAssigned = item.afterState?['assigned_to'];
        final transition = afterStatus != null && beforeStatus != null
            ? 'Status: ${auditLabel('$beforeStatus')} → ${auditLabel('$afterStatus')}'
            : afterAssigned != null
            ? 'Assignment updated'
            : item.action;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuditBadge(item.action),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transition,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    if (item.reason != null && item.reason!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          item.reason!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.actorName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    auditDate(item.createdAt.toIso8601String()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            content,
          ],
        ),
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ],
    );
  }
}
