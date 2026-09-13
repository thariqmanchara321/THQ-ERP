import 'package:flutter/material.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';
import '../services/mobile_pos_local_store.dart';
import '../services/mobile_pos_sync_service.dart';
import '../services/mobile_receipt_service.dart';

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
  late Future<List<LocalInvoice>> future;

  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<List<LocalInvoice>> load() =>
      local.queue(widget.session.tenantId, widget.session.deviceId);

  void reload() {
    setState(() => future = load());
  }

  Future<void> syncAll() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await sync.sync(widget.session);
      if (mounted) reload();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> handleAction(String action, LocalInvoice invoice) async {
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
      );
    } else if (action == 'share') {
      await receipt.shareReceipt(
        session: widget.session,
        localNumber: invoice.localNumber,
        payload: invoice.payload,
        synced: invoice.status == 'synced',
        serverResponse: invoice.serverResponse,
      );
    }

    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        title: const Text('Offline Sync'),
        actions: [
          IconButton(
            tooltip: 'Sync all',
            onPressed: busy ? null : syncAll,
            icon: const Icon(Icons.sync_rounded),
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
            return Center(child: Text(snapshot.error.toString()));
          }

          final rows = snapshot.data ?? const <LocalInvoice>[];
          if (rows.isEmpty) {
            return const Center(child: Text('No local invoices yet.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              final next = load();
              setState(() => future = next);
              await next;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 5),
              itemBuilder: (context, index) {
                final invoice = rows[index];
                final hasProblem =
                    invoice.status == 'conflict' || invoice.status == 'error';

                return Card(
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      child: Icon(
                        invoice.status == 'synced'
                            ? Icons.cloud_done
                            : hasProblem
                            ? Icons.warning_amber
                            : Icons.cloud_upload_outlined,
                      ),
                    ),
                    title: Text(invoice.localNumber),
                    subtitle: Text(
                      '${invoice.status.toUpperCase()} • ${invoice.conflictCode}\n${invoice.conflictMessage}',
                      maxLines: 3,
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
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
                        const PopupMenuItem(
                          value: 'print',
                          child: Text('Print'),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Text('Share PDF'),
                        ),
                      ],
                    ),
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
