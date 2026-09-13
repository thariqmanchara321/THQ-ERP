import 'package:flutter/material.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';
import '../services/mobile_pos_local_store.dart';
import '../services/mobile_pos_sync_service.dart';
import '../services/mobile_receipt_service.dart';

enum _QueueView { notSynced, synced, all }

class OfflineQueueScreen extends StatefulWidget {
  final PosSession session;

  const OfflineQueueScreen({super.key, required this.session});

  @override
  State<OfflineQueueScreen> createState() => _OfflineQueueScreenState();
}

class _OfflineQueueScreenState extends State<OfflineQueueScreen> {
  final MobilePosLocalStore local = MobilePosLocalStore.instance;
  final MobilePosSyncService sync = MobilePosSyncService();
  final MobileReceiptService receipt = MobileReceiptService();

  bool busy = false;
  String? message;
  _QueueView view = _QueueView.notSynced;
  late Future<List<LocalInvoice>> future;

  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<LocalInvoice>> load() =>
      local.queue(widget.session.tenantId, widget.session.deviceId, limit: 1000);

  void reload() {
    setState(() => future = load());
  }

  List<LocalInvoice> _visible(List<LocalInvoice> rows) {
    switch (view) {
      case _QueueView.synced:
        return rows.where((row) => row.status == 'synced').toList();
      case _QueueView.notSynced:
        return rows
            .where(
              (row) =>
                  row.status != 'synced' && row.status != 'cancelled',
            )
            .toList();
      case _QueueView.all:
        return rows;
    }
  }

  int _countNotSynced(List<LocalInvoice> rows) => rows
      .where((row) => row.status != 'synced' && row.status != 'cancelled')
      .length;

  Future<void> syncAll() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await sync.sync(widget.session, includeConflicts: true);
      if (!mounted) return;
      setState(
        () => message =
            'Attempted ${result.attempted} • Synced ${result.synced} • '
            'Conflicts ${result.conflicts} • Pending ${result.pending}',
      );
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reload();
      }
    }
  }

  Future<void> handleAction(String action, LocalInvoice invoice) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (action == 'retry') {
        await local.retry(invoice.requestId);
        await sync.sync(
          widget.session,
          includeConflicts: true,
          only: invoice.requestId,
        );
      } else if (action == 'cancel') {
        await local.cancel(invoice.requestId);
      } else if (action == 'print') {
        await receipt.printReceipt(
          session: widget.session,
          localNumber: invoice.localNumber,
          payload: invoice.payload,
          synced: invoice.status == 'synced',
          serverResponse: invoice.serverResponse,
          requestId: invoice.requestId,
        );
      } else if (action == 'share') {
        await receipt.shareReceipt(
          session: widget.session,
          localNumber: invoice.localNumber,
          payload: invoice.payload,
          synced: invoice.status == 'synced',
          serverResponse: invoice.serverResponse,
          requestId: invoice.requestId,
        );
      }
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    } finally {
      if (mounted) {
        setState(() => busy = false);
        reload();
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'synced':
        return const Color(0xFF159A5C);
      case 'conflict':
        return const Color(0xFFD78B00);
      case 'error':
        return const Color(0xFFD06458);
      case 'cancelled':
        return const Color(0xFF7A8798);
      default:
        return const Color(0xFF147AF3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offline & Sync',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              'View synced and non-synced transactions separately',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh local queue',
            onPressed: busy ? null : reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: busy ? null : syncAll,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(busy ? 'Syncing' : 'Sync'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<LocalInvoice>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(snapshot.error.toString()),
              ),
            );
          }

          final rows = snapshot.data ?? const <LocalInvoice>[];
          final visible = _visible(rows);
          final synced = rows.where((row) => row.status == 'synced').length;
          final notSynced = _countNotSynced(rows);
          final conflicts =
              rows.where((row) => row.status == 'conflict').length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        'Not synced',
                        notSynced,
                        Icons.cloud_upload_outlined,
                        const Color(0xFF147AF3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _summaryCard(
                        'Synced',
                        synced,
                        Icons.cloud_done_outlined,
                        const Color(0xFF159A5C),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _summaryCard(
                        'Conflict',
                        conflicts,
                        Icons.warning_amber_rounded,
                        const Color(0xFFD78B00),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
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
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF315777),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 7),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          view == _QueueView.synced
                              ? 'No synced transactions yet.'
                              : view == _QueueView.notSynced
                                  ? 'Nothing is waiting to sync.'
                                  : 'No local transactions yet.',
                          style: const TextStyle(
                            color: Color(0xFF748196),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          final next = load();
                          setState(() => future = next);
                          await next;
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) =>
                              _invoiceCard(visible[index]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryCard(
    String label,
    int count,
    IconData icon,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE1E7EE)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7A8798),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewButton(_QueueView target, String label, IconData icon) {
    final selected = view == target;
    return selected
        ? FilledButton.icon(
            onPressed: () => setState(() => view = target),
            icon: Icon(icon, size: 16),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: () => setState(() => view = target),
            icon: Icon(icon, size: 16),
            label: Text(label),
          );
  }

  Widget _invoiceCard(LocalInvoice invoice) {
    final hasProblem =
        invoice.status == 'conflict' || invoice.status == 'error';
    final serverNo = invoice.serverResponse?['sale_number']?.toString();
    final total = numberValue(invoice.payload['total']);
    final customer =
        invoice.payload['customer_name']?.toString() ?? 'Walk-in Customer';
    final statusColor = _statusColor(invoice.status);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1E7EE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                invoice.status == 'synced'
                    ? Icons.cloud_done_outlined
                    : hasProblem
                        ? Icons.warning_amber_rounded
                        : Icons.cloud_upload_outlined,
                color: statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          serverNo?.isNotEmpty == true
                              ? serverNo!
                              : invoice.localNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF14233B),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${widget.session.currencyCode} ${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF748196),
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          invoice.status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          hasProblem
                              ? '${invoice.conflictCode}: ${invoice.conflictMessage}'
                              : '${invoice.createdAt.toLocal().toString().split('.').first} • ${invoice.attempts} attempt(s)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF7A8798),
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (action) => handleAction(action, invoice),
              itemBuilder: (_) => [
                if (hasProblem)
                  const PopupMenuItem(
                    value: 'retry',
                    child: Text('Retry'),
                  ),
                if (invoice.status != 'synced' &&
                    invoice.status != 'cancelled')
                  const PopupMenuItem(
                    value: 'cancel',
                    child: Text('Cancel local invoice'),
                  ),
                const PopupMenuItem(value: 'print', child: Text('Print')),
                const PopupMenuItem(
                  value: 'share',
                  child: Text('Share PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
