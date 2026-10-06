import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import '../../widgets/mobile_workspace_widgets.dart';

class MobileApprovalsPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;

  const MobileApprovalsPage({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  State<MobileApprovalsPage> createState() => _MobileApprovalsPageState();
}

class _MobileApprovalsPageState extends State<MobileApprovalsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.service.approvals(widget.session);
  }

  Future<void> _refresh() async {
    final next = widget.service.approvals(widget.session);
    setState(() => _future = next);
    await next;
  }

  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final note = await showThqDialog<String>(
      context: context,
      builder: (context) => _ApprovalNoteDialog(
        title: approve ? 'Approve request' : 'Reject request',
        noteRequired: !approve,
      ),
    );
    if (note == null) {
      return;
    }
    try {
      await widget.service.decide(
        widget.session,
        type: row['approval_type']?.toString() ?? '',
        id: row['id']?.toString() ?? '',
        approve: approve,
        note: note,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Request approved.' : 'Request rejected.'),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.canApprove) {
      return Scaffold(
        appBar: AppBar(title: const Text('Approvals')),
        body: const ThqMobileEmptyState(
          title: 'Approval access not assigned',
          message: 'Your current role does not have approval authority.',
          icon: Icons.lock_outline_rounded,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approvals'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const WorkspaceLoadingList();
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
              ],
            );
          }
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  ThqMobileEmptyState(
                    title: 'All caught up',
                    message: 'There are no pending approval requests.',
                    icon: Icons.task_alt_rounded,
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final row = rows[index];
                return WorkspaceRecordCard(
                  title: row['reference']?.toString() ?? 'Approval request',
                  subtitle: row['summary']?.toString() ?? '',
                  status: row['status']?.toString() ?? 'pending',
                  trailing: row['amount'] == null
                      ? null
                      : workspaceMoney(widget.session, row['amount']),
                  fields: [
                    WorkspaceRecordField(
                      'Module',
                      workspaceLabel(row['module_key']?.toString() ?? ''),
                      icon: Icons.apps_outlined,
                    ),
                    WorkspaceRecordField(
                      'Store',
                      row['location_name']?.toString() ?? '',
                      icon: Icons.storefront_outlined,
                    ),
                    WorkspaceRecordField(
                      'Requested',
                      workspaceDateTime(row['requested_at']),
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                  footer: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _decide(row, false),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _decide(row, true),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class MobileNotificationsPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;

  const MobileNotificationsPage({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  State<MobileNotificationsPage> createState() =>
      _MobileNotificationsPageState();
}

class _MobileNotificationsPageState extends State<MobileNotificationsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.service.notifications(widget.session, limit: 150);
  }

  Future<void> _refresh() async {
    final next = widget.service.notifications(widget.session, limit: 150);
    setState(() => _future = next);
    await next;
  }

  Future<void> _markRead(Map<String, dynamic> row) async {
    if (row['read_at'] != null) {
      return;
    }
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) {
      return;
    }
    await widget.service.markNotificationRead(widget.session, id);
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _markAll() async {
    await widget.service.markAllNotificationsRead(widget.session);
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notifications'),
      actions: [TextButton(onPressed: _markAll, child: const Text('Read all'))],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const WorkspaceLoadingList();
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
            ],
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                ThqMobileEmptyState(
                  title: 'No notifications',
                  message: 'New business alerts will appear here.',
                  icon: Icons.notifications_none_rounded,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              final unread = row['read_at'] == null;
              return WorkspaceRecordCard(
                title: row['title']?.toString() ?? 'Notification',
                subtitle: row['message']?.toString() ?? '',
                status: row['severity']?.toString(),
                onTap: () => _markRead(row),
                fields: [
                  WorkspaceRecordField(
                    'Category',
                    workspaceLabel(row['category']?.toString() ?? ''),
                    icon: Icons.label_outline_rounded,
                  ),
                  WorkspaceRecordField(
                    'Time',
                    workspaceDateTime(row['created_at']),
                    icon: Icons.schedule_rounded,
                  ),
                  if (unread)
                    const WorkspaceRecordField(
                      'State',
                      'Unread',
                      icon: Icons.circle_notifications_outlined,
                    ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}

class MobileAuditPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileAuditPage({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
  });

  @override
  State<MobileAuditPage> createState() => _MobileAuditPageState();
}

class _MobileAuditPageState extends State<MobileAuditPage> {
  late Future<List<dynamic>> _future;
  String? _severity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));
    _future = Future.wait<dynamic>([
      widget.service.auditSummary(
        widget.session,
        locationId: widget.locationId,
        from: from,
        to: now,
      ),
      widget.service.auditFindings(
        widget.session,
        locationId: widget.locationId,
        from: from,
        to: now,
        severity: _severity,
        limit: 200,
      ),
    ]);
  }

  Future<void> _refresh() async {
    _load();
    setState(() {});
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.canViewAudit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audit Center')),
        body: const ThqMobileEmptyState(
          title: 'Audit access not assigned',
          message: 'Your current role does not have Audit Center visibility.',
          icon: Icons.shield_outlined,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Center')),
      body: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const WorkspaceLoadingList();
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
              ],
            );
          }
          final summary = snapshot.data?[0] is Map
              ? Map<String, dynamic>.from(snapshot.data![0] as Map)
              : <String, dynamic>{};
          final findings = (snapshot.data?[1] as List? ?? const [])
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ThqMobileMetricCard(
                        label: 'High risk',
                        value: '${summary['high_risk'] ?? 0}',
                        icon: Icons.gpp_bad_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ThqMobileMetricCard(
                        label: 'Needs review',
                        value: '${summary['needs_review'] ?? 0}',
                        icon: Icons.rate_review_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ThqMobileMetricCard(
                        label: 'Normal',
                        value: '${summary['normal'] ?? 0}',
                        icon: Icons.verified_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _AuditFilterChip(
                        label: 'All',
                        selected: _severity == null,
                        onTap: () {
                          _severity = null;
                          _refresh();
                        },
                      ),
                      _AuditFilterChip(
                        label: 'High risk',
                        selected: _severity == 'high_risk',
                        onTap: () {
                          _severity = 'high_risk';
                          _refresh();
                        },
                      ),
                      _AuditFilterChip(
                        label: 'Needs review',
                        selected: _severity == 'needs_review',
                        onTap: () {
                          _severity = 'needs_review';
                          _refresh();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ThqMobileSectionHeader(
                  title: 'Findings',
                  subtitle: 'Last 30 days • ${findings.length} results',
                ),
                const SizedBox(height: 9),
                if (findings.isEmpty)
                  const ThqMobileEmptyState(
                    title: 'No findings in this view',
                    message: 'No audit items match the selected category.',
                    icon: Icons.verified_user_outlined,
                  )
                else
                  ...findings.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: WorkspaceRecordCard(
                        title: row['title']?.toString() ?? 'Audit finding',
                        subtitle: row['description']?.toString() ?? '',
                        status: row['severity']?.toString(),
                        fields: [
                          WorkspaceRecordField(
                            'Reference',
                            row['entity_reference']?.toString() ?? '',
                            icon: Icons.link_rounded,
                          ),
                          WorkspaceRecordField(
                            'State',
                            workspaceLabel(row['status']?.toString() ?? ''),
                            icon: Icons.flag_outlined,
                          ),
                          WorkspaceRecordField(
                            'Risk',
                            '${row['risk_score'] ?? ''}',
                            icon: Icons.analytics_outlined,
                          ),
                          WorkspaceRecordField(
                            'Detected',
                            workspaceDateTime(row['detected_at']),
                            icon: Icons.schedule_rounded,
                          ),
                          WorkspaceRecordField(
                            'Actor',
                            row['actor_name']?.toString() ?? '',
                            icon: Icons.person_outline_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class MobileTraceabilityPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileTraceabilityPage({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
  });

  @override
  State<MobileTraceabilityPage> createState() => _MobileTraceabilityPageState();
}

class _MobileTraceabilityPageState extends State<MobileTraceabilityPage> {
  final _search = TextEditingController();
  String _mode = 'serials';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    final query = _search.text.trim();
    _future = switch (_mode) {
      'batches' => widget.service.batches(
        widget.session,
        locationId: widget.locationId,
        query: query,
        limit: 200,
      ),
      'warranty' => widget.service.warranties(
        widget.session,
        locationId: widget.locationId,
        query: query,
        limit: 200,
      ),
      _ => widget.service.serials(
        widget.session,
        locationId: widget.locationId,
        query: query,
        limit: 200,
      ),
    };
  }

  Future<void> _refresh() async {
    _load();
    setState(() {});
    await _future;
  }

  void _changeMode(String mode) {
    setState(() {
      _mode = mode;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.canViewTraceability) {
      return Scaffold(
        appBar: AppBar(title: const Text('Traceability')),
        body: const ThqMobileEmptyState(
          title: 'Traceability access not assigned',
          message:
              'Serial, batch and warranty visibility is controlled by your role.',
          icon: Icons.qr_code_scanner_rounded,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Traceability')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'serials',
                      label: Text('Serials'),
                      icon: Icon(Icons.qr_code_2_rounded),
                    ),
                    ButtonSegment(
                      value: 'batches',
                      label: Text('Batches'),
                      icon: Icon(Icons.layers_outlined),
                    ),
                    ButtonSegment(
                      value: 'warranty',
                      label: Text('Warranty'),
                      icon: Icon(Icons.shield_outlined),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) => _changeMode(value.first),
                ),
                const SizedBox(height: 9),
                ThqMobileSearchField(
                  controller: _search,
                  hintText: 'Serial, batch, product, SKU or party',
                  onSubmitted: (_) => _refresh(),
                  onClear: () {
                    _search.clear();
                    _refresh();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const WorkspaceLoadingList();
                }
                if (snapshot.hasError) {
                  return ListView(
                    children: [
                      WorkspaceErrorView(
                        error: snapshot.error!,
                        onRetry: _refresh,
                      ),
                    ],
                  );
                }
                final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                if (rows.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        ThqMobileEmptyState(
                          title: 'No traceability records',
                          message: 'Try a different search or category.',
                          icon: Icons.qr_code_scanner_rounded,
                        ),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (_mode == 'batches') {
                        return _batchCard(row);
                      }
                      if (_mode == 'warranty') {
                        return _warrantyCard(row);
                      }
                      return _serialCard(row);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _serialCard(Map<String, dynamic> row) => WorkspaceRecordCard(
    title: row['serial_number']?.toString() ?? 'Serial',
    subtitle: row['product_name']?.toString() ?? '',
    status: row['status']?.toString(),
    fields: [
      WorkspaceRecordField('SKU', row['sku']?.toString() ?? ''),
      WorkspaceRecordField('Store', row['location_name']?.toString() ?? ''),
      WorkspaceRecordField('Customer', row['customer_name']?.toString() ?? ''),
      WorkspaceRecordField('Sale', row['sale_number']?.toString() ?? ''),
      WorkspaceRecordField(
        'Warranty',
        row['warranty_status']?.toString() ?? '',
      ),
      WorkspaceRecordField('Expiry', workspaceDate(row['warranty_expiry'])),
    ],
  );

  Widget _batchCard(Map<String, dynamic> row) => WorkspaceRecordCard(
    title: row['batch_number']?.toString() ?? 'Batch',
    subtitle: row['product_name']?.toString() ?? '',
    status: row['status']?.toString(),
    trailing: '${workspaceNumber(row['quantity'], decimals: 2)} units',
    fields: [
      WorkspaceRecordField('SKU', row['sku']?.toString() ?? ''),
      WorkspaceRecordField('Supplier', row['supplier_name']?.toString() ?? ''),
      WorkspaceRecordField(
        'Purchase',
        row['purchase_number']?.toString() ?? '',
      ),
      WorkspaceRecordField('Expiry', workspaceDate(row['expiry_on'])),
    ],
  );

  Widget _warrantyCard(Map<String, dynamic> row) {
    final serial = row['serial_number']?.toString() ?? '';
    final batch = row['batch_number']?.toString() ?? '';
    return WorkspaceRecordCard(
      title: serial.isNotEmpty
          ? serial
          : (batch.isNotEmpty ? batch : 'Warranty'),
      subtitle: row['product_name']?.toString() ?? '',
      status: row['status']?.toString(),
      fields: [
        WorkspaceRecordField(
          'Customer',
          row['customer_name']?.toString() ?? '',
        ),
        WorkspaceRecordField('Sale', row['sale_number']?.toString() ?? ''),
        WorkspaceRecordField('Start', workspaceDate(row['warranty_start'])),
        WorkspaceRecordField('Expiry', workspaceDate(row['warranty_expiry'])),
        WorkspaceRecordField('Days', '${row['days_remaining'] ?? ''}'),
      ],
    );
  }
}

class MobilePurchasesPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobilePurchasesPage({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
  });

  @override
  State<MobilePurchasesPage> createState() => _MobilePurchasesPageState();
}

class _MobilePurchasesPageState extends State<MobilePurchasesPage> {
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.purchases(
      widget.session,
      locationId: widget.locationId,
      limit: 250,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = widget.service.purchases(
      widget.session,
      locationId: widget.locationId,
      limit: 250,
    );
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchases')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const WorkspaceLoadingList();
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
            ],
          );
        }
        final q = _search.text.trim().toLowerCase();
        final all = snapshot.data ?? const <Map<String, dynamic>>[];
        final rows = q.isEmpty
            ? all
            : all
                  .where(
                    (row) => row.values.any(
                      (value) =>
                          value?.toString().toLowerCase().contains(q) == true,
                    ),
                  )
                  .toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
            children: [
              ThqMobileSearchField(
                controller: _search,
                hintText: 'Document, supplier, store or status',
                onChanged: (_) => setState(() {}),
                onClear: () {
                  _search.clear();
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              ThqMobileSectionHeader(
                title: 'Purchase activity',
                subtitle: '${rows.length} recent documents',
              ),
              const SizedBox(height: 9),
              if (rows.isEmpty)
                const ThqMobileEmptyState(
                  title: 'No purchases match',
                  message: 'Try another supplier, document or status.',
                  icon: Icons.shopping_bag_outlined,
                )
              else
                ...rows.map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: WorkspaceRecordCard(
                      title: row['document_number']?.toString() ?? 'Purchase',
                      subtitle: row['supplier_name']?.toString() ?? '',
                      status: row['status']?.toString(),
                      trailing: workspaceMoney(
                        widget.session,
                        row['grand_total'],
                      ),
                      fields: [
                        WorkspaceRecordField(
                          'Type',
                          workspaceLabel(
                            row['document_type']?.toString() ?? '',
                          ),
                        ),
                        WorkspaceRecordField(
                          'Date',
                          workspaceDate(row['document_date']),
                        ),
                        WorkspaceRecordField(
                          'Balance',
                          workspaceMoney(widget.session, row['balance_due']),
                        ),
                        WorkspaceRecordField(
                          'Store',
                          row['location_name']?.toString() ?? '',
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class MobileStorePerformancePage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;

  const MobileStorePerformancePage({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  State<MobileStorePerformancePage> createState() =>
      _MobileStorePerformancePageState();
}

class _MobileStorePerformancePageState
    extends State<MobileStorePerformancePage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service.storePerformance(widget.session);
  }

  Future<void> _refresh() async {
    final next = widget.service.storePerformance(widget.session);
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Store Performance')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const WorkspaceLoadingList();
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
            ],
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final row = rows[index];
              return WorkspaceRecordCard(
                title: row['location_name']?.toString() ?? 'Store',
                subtitle: row['location_code']?.toString() ?? '',
                trailing: workspaceMoney(widget.session, row['net_sales']),
                fields: [
                  WorkspaceRecordField(
                    'Profit',
                    workspaceMoney(widget.session, row['gross_profit']),
                  ),
                  WorkspaceRecordField(
                    'Invoices',
                    '${row['invoice_count'] ?? 0}',
                  ),
                  WorkspaceRecordField(
                    'Stock',
                    workspaceMoney(widget.session, row['inventory_value']),
                  ),
                  WorkspaceRecordField(
                    'Receivable',
                    workspaceMoney(widget.session, row['receivables']),
                  ),
                  WorkspaceRecordField(
                    'Payable',
                    workspaceMoney(widget.session, row['payables']),
                  ),
                  WorkspaceRecordField(
                    'Low stock',
                    '${row['low_stock_count'] ?? 0}',
                  ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}

class MobileReportsPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileReportsPage({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
  });

  @override
  State<MobileReportsPage> createState() => _MobileReportsPageState();
}

class _MobileReportsPageState extends State<MobileReportsPage> {
  late DateTime _from;
  late DateTime _to;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = now;
    _load();
  }

  void _load() {
    _future = widget.service.report(
      widget.session,
      from: _from,
      to: _to,
      locationId: widget.locationId,
    );
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range == null) {
      return;
    }
    setState(() {
      _from = range.start;
      _to = range.end;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reports'),
      actions: [
        IconButton(
          tooltip: 'Date range',
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range_outlined),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const WorkspaceLoadingList();
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(
                error: snapshot.error!,
                onRetry: () => setState(_load),
              ),
            ],
          );
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          children: [
            ThqMobileSectionHeader(
              title: 'Business summary',
              subtitle: '${workspaceDate(_from)} – ${workspaceDate(_to)}',
            ),
            const SizedBox(height: 9),
            if (data.isEmpty)
              const ThqMobileEmptyState(
                title: 'No report data',
                message: 'No summary values were returned for this period.',
                icon: Icons.analytics_outlined,
              )
            else
              ...data.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      title: Text(workspaceLabel(entry.key)),
                      trailing: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          entry.value?.toString() ?? '—',
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class MobileCustomerPaymentPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileCustomerPaymentPage({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
  });

  @override
  State<MobileCustomerPaymentPage> createState() =>
      _MobileCustomerPaymentPageState();
}

class _MobileCustomerPaymentPageState extends State<MobileCustomerPaymentPage> {
  late Future<List<Map<String, dynamic>>> _customers;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String? _customerId;
  String _method = 'cash';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _customers = widget.service.customerOutstanding(
      widget.session,
      locationId: widget.locationId,
      limit: 500,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = double.tryParse(_amount.text.trim()) ?? 0;
    if (_customerId == null || value <= 0 || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.receiveCustomerPayment(
        widget.session,
        customerId: _customerId!,
        amount: value,
        method: _method,
        reference: _reference.text.trim(),
        notes: _notes.text.trim(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer payment recorded.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receive Payment')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _customers,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const WorkspaceLoadingList(count: 3);
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(
                error: snapshot.error!,
                onRetry: () => setState(() {
                  _customers = widget.service.customerOutstanding(
                    widget.session,
                    locationId: widget.locationId,
                    limit: 500,
                  );
                }),
              ),
            ],
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _customerId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Customer',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              items: rows
                  .map(
                    (row) => DropdownMenuItem<String>(
                      value: row['customer_id']?.toString() ?? '',
                      child: Text(
                        '${row['customer_name'] ?? 'Customer'} • ${workspaceMoney(widget.session, row['total_outstanding'])}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _customerId = value),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${widget.session.currencyCode})',
                prefixIcon: const Icon(Icons.currency_rupee_rounded),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _method = value);
                      }
                    },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reference,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Reference',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              enabled: !_busy,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(_busy ? 'Recording…' : 'Record payment'),
            ),
          ],
        );
      },
    ),
  );
}

class MobileGlobalSearchPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileGlobalSearchPage({
    super.key,
    required this.session,
    required this.service,
    required this.locationId,
  });

  @override
  State<MobileGlobalSearchPage> createState() => _MobileGlobalSearchPageState();
}

class _MobileGlobalSearchPageState extends State<MobileGlobalSearchPage> {
  final _search = TextEditingController();
  Future<Map<String, List<Map<String, dynamic>>>>? _future;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _run() {
    final query = _search.text.trim();
    if (query.length < 2) {
      setState(() => _future = null);
      return;
    }
    setState(() {
      _future = widget.service.globalSearch(
        widget.session,
        query: query,
        locationId: widget.locationId,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search Business')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: ThqMobileSearchField(
            controller: _search,
            hintText: 'Invoice, product, party, SKU…',
            onSubmitted: (_) => _run(),
            onClear: () {
              _search.clear();
              setState(() => _future = null);
            },
          ),
        ),
        Expanded(
          child: _future == null
              ? const ThqMobileEmptyState(
                  title: 'Search across the business',
                  message:
                      'Enter at least two characters to search sales, purchases, inventory, customers and suppliers.',
                  icon: Icons.manage_search_rounded,
                )
              : FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const WorkspaceLoadingList();
                    }
                    if (snapshot.hasError) {
                      return ListView(
                        children: [
                          WorkspaceErrorView(
                            error: snapshot.error!,
                            onRetry: _run,
                          ),
                        ],
                      );
                    }
                    final groups =
                        snapshot.data ??
                        const <String, List<Map<String, dynamic>>>{};
                    final total = groups.values.fold<int>(
                      0,
                      (sum, rows) => sum + rows.length,
                    );
                    if (total == 0) {
                      return const ThqMobileEmptyState(
                        title: 'Nothing found',
                        message:
                            'Try another invoice number, product, party or SKU.',
                        icon: Icons.search_off_rounded,
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                      children: groups.entries
                          .where((entry) => entry.value.isNotEmpty)
                          .expand(
                            (entry) => <Widget>[
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  bottom: 7,
                                ),
                                child: ThqMobileSectionHeader(
                                  title: entry.key,
                                  subtitle: '${entry.value.length} matches',
                                ),
                              ),
                              ...entry.value.map(
                                (row) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: WorkspaceRecordCard(
                                    title: _searchTitle(entry.key, row),
                                    subtitle: _searchSubtitle(entry.key, row),
                                    status: row['status']?.toString(),
                                    trailing: _searchTrailing(entry.key, row),
                                  ),
                                ),
                              ),
                            ],
                          )
                          .toList(),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  String _searchTitle(String group, Map<String, dynamic> row) =>
      switch (group) {
        'Sales' => row['sale_number']?.toString() ?? 'Sale',
        'Purchases' => row['document_number']?.toString() ?? 'Purchase',
        'Inventory' => row['product_name']?.toString() ?? 'Product',
        'Customers' => row['customer_name']?.toString() ?? 'Customer',
        'Suppliers' => row['supplier_name']?.toString() ?? 'Supplier',
        _ => 'Result',
      };

  String _searchSubtitle(String group, Map<String, dynamic> row) =>
      switch (group) {
        'Sales' => row['customer_name']?.toString() ?? '',
        'Purchases' => row['supplier_name']?.toString() ?? '',
        'Inventory' => '${row['sku'] ?? ''} • ${row['location_name'] ?? ''}',
        'Customers' => row['phone']?.toString() ?? '',
        'Suppliers' => row['phone']?.toString() ?? '',
        _ => '',
      };

  String? _searchTrailing(String group, Map<String, dynamic> row) =>
      switch (group) {
        'Sales' ||
        'Purchases' => workspaceMoney(widget.session, row['grand_total']),
        'Inventory' =>
          '${workspaceNumber(row['available'], decimals: 2)} available',
        'Customers' ||
        'Suppliers' => workspaceMoney(widget.session, row['total_outstanding']),
        _ => null,
      };
}

class _ApprovalNoteDialog extends StatefulWidget {
  final String title;
  final bool noteRequired;

  const _ApprovalNoteDialog({required this.title, required this.noteRequired});

  @override
  State<_ApprovalNoteDialog> createState() => _ApprovalNoteDialogState();
}

class _ApprovalNoteDialogState extends State<_ApprovalNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: widget.noteRequired ? 'Reason required' : 'Note (optional)',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final note = _controller.text.trim();
          if (widget.noteRequired && note.isEmpty) {
            return;
          }
          Navigator.pop(context, note);
        },
        child: const Text('Continue'),
      ),
    ],
  );
}

class _AuditFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AuditFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}
