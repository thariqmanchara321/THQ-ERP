import 'offline_storage_adapter.dart';
import 'offline_sync_result.dart';
import 'offline_sync_verifier.dart';

/// Callback type for executing a remote synchronization RPC.
typedef RemoteSaleSyncExecutor = Future<dynamic> Function({
  required String tenantId,
  required String locationId,
  required String deviceId,
  required String requestId,
  required Map<String, dynamic> payload,
});

/// Shared synchronization coordinator that enforces FIFO queue ordering,
/// authoritative GST verification, single-flight locking, and safe retry policies.
class OfflineSyncCoordinator {
  final OfflineStorageAdapter storage;
  bool _isSyncInProgress = false;

  OfflineSyncCoordinator({required this.storage});

  /// Whether a sync operation is currently active.
  bool get isSyncInProgress => _isSyncInProgress;

  /// Synchronizes pending transactions with the backend server.
  ///
  /// - Enforces FIFO order (oldest transactions first via `rows.reversed`).
  /// - Halts immediately upon transport outages to preserve chronological ordering.
  /// - Marks records as 'conflict' if rejected by server business rules.
  /// - Marks records as 'synced' only upon receiving authoritative GST evidence.
  Future<OfflineSyncResult> syncQueue({
    required String tenantId,
    required String locationId,
    required String deviceId,
    required RemoteSaleSyncExecutor rpcExecutor,
    bool includeConflicts = false,
    String? onlyRequestId,
  }) async {
    if (_isSyncInProgress) {
      return const OfflineSyncResult(
        attempted: 0,
        synced: 0,
        conflicts: 0,
        pending: 0,
      );
    }
    _isSyncInProgress = true;

    try {
      final statuses = <String>{'pending', 'syncing', 'error'};
      if (includeConflicts) statuses.add('conflict');

      var rows = await storage.fetchQueue(
        tenantId: tenantId,
        deviceId: deviceId,
        statuses: statuses,
      );

      if (onlyRequestId != null) {
        rows = rows.where((r) => r.requestId == onlyRequestId).toList();
      }

      var synced = 0;
      var conflicts = 0;
      var pending = 0;

      // Queue is sorted newest first (DESC); process reversed for strict FIFO order (oldest first).
      for (final record in rows.reversed) {
        if (record.status == 'conflict') {
          await storage.retry(record.requestId);
        }

        await storage.markSyncing(record.requestId);

        try {
          final rawResult = await rpcExecutor(
            tenantId: tenantId,
            locationId: locationId,
            deviceId: deviceId,
            requestId: record.requestId,
            payload: record.payload,
          );

          final verification = OfflineSyncVerifier.verify(rawResult);

          if (verification.isConflict) {
            await storage.markConflict(
              record.requestId,
              code: verification.conflictCode ?? 'SERVER_VALIDATION',
              message: verification.conflictMessage ?? 'Server rejected offline invoice.',
            );
            conflicts++;
          } else if (verification.isSuccess) {
            await storage.markSynced(record.requestId, verification.rawResponse);
            synced++;
          } else {
            // Missing GST snapshot / journal evidence is treated as server validation failure.
            throw StateError(
              verification.conflictMessage ??
                  'Sync response missing authoritative GST recovery evidence.',
            );
          }
        } catch (error) {
          // Transport / network outage is not a permanent failure.
          // Keep the immutable request pending with its original ID and halt the loop
          // to prevent head-of-line skipping.
          await storage.markPending(record.requestId, message: error.toString());
          pending++;
          break;
        }
      }

      return OfflineSyncResult(
        attempted: rows.length,
        synced: synced,
        conflicts: conflicts,
        pending: pending,
      );
    } finally {
      _isSyncInProgress = false;
    }
  }
}
