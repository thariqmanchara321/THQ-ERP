import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/offline_pos_service.dart';
import '../services/offline_pos_sync_service.dart';

enum _QueueView { notSynced, synced, all }

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
  _QueueView _view = _QueueView.notSynced;
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
    final rows = await _local.queue(
      tenantId: _tenantId,
      deviceId: _deviceId,
      limit: 1000,
    );
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

  List<OfflineInvoiceRecord> get _visibleRows {
    switch (_view) {
      case _QueueView.synced:
        return _rows.where((row) => row.status == 'synced').toList();
      case _QueueView.notSynced:
        return _rows
            .where(
              (row) =>
                  row.status != 'synced' && row.status != 'cancelled',
            )
            .toList();
      case _QueueView.all:
        return _rows;
    }
  }

  int get _notSyncedCount => _rows
      .where((row) => row.status != 'synced' && row.status != 'cancelled')
      .length;

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
            'Attempted ${result.attempted} • Synced ${result.synced} • '
            'Conflicts ${result.conflicts} • Pending ${result.pending}',
      );
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _retry(OfflineInvoiceRecord row) async {
    if (_busy) return;
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
    if (_busy) return;
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

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'synced':
        return Colors.green;
      case 'conflict':
        return Colors.orange;
      case 'error':
        return Theme.of(context).colorScheme.error;
      case 'cancelled':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = _visibleRows;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 48,
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
                  height: 26,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline & Sync',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Synced and non-synced transactions are separated below',
                        style: TextStyle(fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh local queue',
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
                      : const Icon(Icons.sync_rounded, size: 15),
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
                  child: _Stat(
                    'Not Synced',
                    _notSyncedCount,
                    Icons.cloud_upload_outlined,
                  ),
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
                  child: _Stat(
                    'Error',
                    _summary.error,
                    Icons.error_outline,
                  ),
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
          Row(
            children: [
              Expanded(
                child: _viewButton(
                  _QueueView.notSynced,
                  'Not Synced',
                  Icons.cloud_upload_outlined,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _viewButton(
                  _QueueView.synced,
                  'Synced',
                  Icons.cloud_done_outlined,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: _viewButton(
                  _QueueView.all,
                  'All',
                  Icons.list_alt_rounded,
                ),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                _message!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ],
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
                    color: scheme.surfaceContainerHighest.withValues(alpha: .45),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Invoice',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Created / Attempts',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Server / Conflict',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Text(
                            'Status',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SizedBox(width: 70),
                      ],
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? Center(
                            child: Text(
                              _view == _QueueView.synced
                                  ? 'No synced transactions yet.'
                                  : _view == _QueueView.notSynced
                                      ? 'Nothing is waiting to sync.'
                                      : 'No local transactions yet.',
                              style: const TextStyle(fontSize: 11),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                _queueRow(visible[index]),
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Local database: ${_local.databasePath ?? 'Initializing...'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewButton(_QueueView target, String label, IconData icon) {
    final selected = _view == target;
    if (selected) {
      return FilledButton.icon(
        onPressed: () => setState(() => _view = target),
        icon: Icon(icon, size: 15),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => setState(() => _view = target),
      icon: Icon(icon, size: 15),
      label: Text(label),
    );
  }

  Widget _queueRow(OfflineInvoiceRecord row) {
    final scheme = Theme.of(context).colorScheme;
    final serverNo = row.serverResponse?['sale_number']?.toString();
    final total =
        (row.payload['total'] as num?)?.toDouble() ??
        double.tryParse('${row.payload['total']}') ??
        0.0;

    return Container(
      constraints: const BoxConstraints(minHeight: 52),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        serverNo?.isNotEmpty == true
                            ? serverNo!
                            : row.localInvoiceNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${widget.session.currencyCode} ${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 9,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${row.createdAt.toLocal().toString().split('.').first} | '
              '${row.attempts} attempt(s)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
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
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            width: 100,
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
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: _statusColor(context, row.status),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 70,
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
                    fontSize: 10,
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
