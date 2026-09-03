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
    final path = _local.databasePath ?? 'Initializing...';
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Offline POS Sync',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh queue',
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
                const SizedBox(width: 3),
                FilledButton.icon(
                  onPressed: _busy ? null : _syncNow,
                  icon: _busy
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined, size: 15),
                  label: Text(_busy ? 'Syncing...' : 'Sync Now'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 54,
            child: Row(
              children: [
                Expanded(
                  child: _Stat('Pending', _summary.pending, Icons.schedule),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _Stat(
                    'Conflict',
                    _summary.conflict,
                    Icons.warning_amber_outlined,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _Stat('Error', _summary.error, Icons.error_outline),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _Stat(
                    'Synced',
                    _summary.synced,
                    Icons.cloud_done_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.storage_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    path,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 7.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_message != null)
                  Expanded(
                    child: Text(
                      _message!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 7.8,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: .45,
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Local Invoice',
                            style: TextStyle(
                              fontSize: 8.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Created / Attempts',
                            style: TextStyle(
                              fontSize: 8.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Server / Conflict',
                            style: TextStyle(
                              fontSize: 8.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 92,
                          child: Text(
                            'Status',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 8.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(width: 64),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _rows.isEmpty
                        ? const Center(
                            child: Text(
                              'No offline invoices yet.',
                              style: TextStyle(fontSize: 9),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _rows.length,
                            itemBuilder: (context, index) =>
                                _queueRow(_rows[index]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueRow(OfflineInvoiceRecord row) {
    final scheme = Theme.of(context).colorScheme;
    final serverNo = row.serverResponse?['sale_number']?.toString();

    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 15,
                  color: _statusColor(context, row.status),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    row.localInvoiceNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 8.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${row.createdAt.toString().split('.').first} | '
              '${row.attempts} attempt(s)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 7.8),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              serverNo != null && serverNo.isNotEmpty
                  ? 'Server $serverNo'
                  : row.conflictCode != null
                  ? '${row.conflictCode}: ${row.conflictMessage ?? ''}'
                  : '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 7.8, color: scheme.onSurfaceVariant),
            ),
          ),
          SizedBox(
            width: 92,
            child: Center(
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _statusColor(
                    context,
                    row.status,
                  ).withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  row.status.toUpperCase(),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    color: _statusColor(context, row.status),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (row.status == 'conflict' || row.status == 'error')
                  IconButton(
                    tooltip: 'Retry',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => _retry(row),
                    icon: const Icon(Icons.replay, size: 14),
                  ),
                if (!const {'synced', 'cancelled'}.contains(row.status))
                  IconButton(
                    tooltip: 'Cancel local invoice',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => _cancel(row),
                    icon: const Icon(Icons.cancel_outlined, size: 14),
                  ),
              ],
            ),
          ),
        ],
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 7.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
