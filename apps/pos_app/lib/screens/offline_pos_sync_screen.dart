import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/offline_pos_service.dart';
import '../services/offline_pos_sync_service.dart';

class OfflinePosSyncScreen extends StatefulWidget {
  final ClientSession session;
  const OfflinePosSyncScreen({super.key, required this.session});

  @override
  State<OfflinePosSyncScreen> createState() => _OfflinePosSyncScreenState();
}

class _OfflinePosSyncScreenState extends State<OfflinePosSyncScreen> {
  final OfflinePosService _local = OfflinePosService.instance;
  final OfflinePosSyncService _sync = OfflinePosSyncService();
  bool _busy = false;
  String? _message;
  List<OfflineInvoiceRecord> _rows = const [];
  OfflineQueueSummary _summary = const OfflineQueueSummary(
    pending: 0,
    conflict: 0,
    error: 0,
    synced: 0,
  );

  String get _tenantId => widget.session.business.id;
  String get _deviceId => widget.session.device?.deviceId ?? '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_deviceId.isEmpty) return;
    await _local.initialize();
    final rows = await _local.queue(tenantId: _tenantId, deviceId: _deviceId);
    final summary = await _local.summary(
      tenantId: _tenantId,
      deviceId: _deviceId,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _summary = summary;
    });
  }

  Future<void> _syncNow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await _sync.syncPending(
        widget.session,
        includeConflicts: false,
      );
      try {
        await _sync.refreshCatalogue(widget.session);
      } catch (_) {}
      if (!mounted) return;
      setState(
        () => _message =
            'Attempted ${result.attempted} • Synced ${result.synced} • Conflicts ${result.conflicts} • Pending ${result.pending}',
      );
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _retry(OfflineInvoiceRecord row) async {
    setState(() => _busy = true);
    try {
      await _local.retry(row.requestId);
      await _sync.syncPending(
        widget.session,
        includeConflicts: true,
        onlyRequestId: row.requestId,
      );
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _cancel(OfflineInvoiceRecord row) async {
    setState(() => _busy = true);
    try {
      await _local.cancel(row.requestId);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Color _statusColor(BuildContext context, String status) => switch (status) {
    'synced' => Colors.green,
    'conflict' => Colors.orange,
    'error' => Colors.red,
    'cancelled' => Colors.grey,
    _ => Theme.of(context).colorScheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    final path = _local.databasePath ?? 'Initializing…';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline POS Sync'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _syncNow,
            icon: const Icon(Icons.cloud_sync_outlined),
            label: Text(_busy ? 'Syncing…' : 'Sync Now'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Stat('Pending', _summary.pending, Icons.schedule),
                _Stat(
                  'Conflict',
                  _summary.conflict,
                  Icons.warning_amber_outlined,
                ),
                _Stat('Error', _summary.error, Icons.error_outline),
                _Stat('Synced', _summary.synced, Icons.cloud_done_outlined),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              'Local database: $path',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text('No offline invoices yet.'))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final serverNo = row.serverResponse?['sale_number']
                            ?.toString();
                        return ListTile(
                          leading: Icon(
                            Icons.receipt_long_outlined,
                            color: _statusColor(context, row.status),
                          ),
                          title: Text(row.localInvoiceNumber),
                          subtitle: Text(
                            [
                              row.createdAt.toString().split('.').first,
                              'Attempts ${row.attempts}',
                              if (serverNo != null && serverNo.isNotEmpty)
                                'Server $serverNo',
                              if (row.conflictCode != null)
                                '${row.conflictCode}: ${row.conflictMessage ?? ''}',
                            ].join(' • '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Chip(label: Text(row.status.toUpperCase())),
                              if (row.status == 'conflict' ||
                                  row.status == 'error')
                                IconButton(
                                  onPressed: _busy ? null : () => _retry(row),
                                  tooltip: 'Retry',
                                  icon: const Icon(Icons.replay),
                                ),
                              if (!const {
                                'synced',
                                'cancelled',
                              }.contains(row.status))
                                IconButton(
                                  onPressed: _busy ? null : () => _cancel(row),
                                  tooltip: 'Cancel local invoice',
                                  icon: const Icon(Icons.cancel_outlined),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}
