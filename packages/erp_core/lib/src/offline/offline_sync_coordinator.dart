import 'offline_storage_adapter.dart';
import 'offline_sync_result.dart';
import 'offline_sync_status.dart';
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

  /// Global lock registry tracking active sync operations per tenant:device.
  /// Guarantees single-flight execution across multiple coordinator instances.
  static final Set<String> _activeLocks = <String>{};

  OfflineSyncCoordinator({required this.storage});

  /// Builds the composite lock key for a tenant and device.
  static String lockKey(String tenantId, String deviceId) => '$tenantId:$deviceId';

  /// Resets all active locks. Used exclusively in unit tests.
  static void resetLocksForTest() => _activeLocks.clear();

  /// Whether a sync operation is currently active for the specified tenant and device.
  static bool isSyncLocked(String tenantId, String deviceId) =>
      _activeLocks.contains(lockKey(tenantId, deviceId));

  /// Whether any sync operation is active in this process.
  bool get isSyncInProgress => _activeLocks.isNotEmpty;

  /// Computes bounded exponential backoff in seconds based on attempt count.
  /// 1 -> 1s, 2 -> 2s, 3 -> 4s, 4 -> 8s, 5 -> 16s, 6 -> 32s, 7+ -> 60s max.
  static int computeBackoffSeconds(int attempts, {int maxSeconds = 60}) {
    if (attempts <= 0) return 0;
    final exponent = (attempts - 1).clamp(0, 6);
    final seconds = 1 << exponent;
    return seconds > maxSeconds ? maxSeconds : seconds;
  }

  /// Synchronizes pending transactions with the backend server.
  ///
  /// - Enforces single-flight locking scoped per tenant + device.
  /// - Automatically recovers interrupted syncs (status 'syncing' reset to 'pending').
  /// - Enforces strict FIFO order (`created_at ASC, rowid ASC`).
  /// - Respects bounded exponential backoff for retrying items in automatic runs.
  /// - Halts immediately upon transport outages or expired auth to preserve FIFO order.
  /// - Marks records as 'conflict' if rejected by server business rules, retaining evidence.
  /// - Marks records as 'synced' only upon receiving authoritative GST evidence.
  Future<OfflineSyncResult> syncQueue({
    required String tenantId,
    required String locationId,
    required String deviceId,
    required RemoteSaleSyncExecutor rpcExecutor,
    bool includeConflicts = false,
    String? onlyRequestId,
  }) async {
    final key = lockKey(tenantId, deviceId);
    if (_activeLocks.contains(key)) {
      return const OfflineSyncResult(
        attempted: 0,
        synced: 0,
        conflicts: 0,
        pending: 0,
      );
    }
    _activeLocks.add(key);

    try {
      // 1. Recover any records left in 'syncing' status from a previous crash/interruption.
      await storage.recoverInterruptedSync(
        tenantId: tenantId,
        deviceId: deviceId,
      );

      final statuses = <String>{'pending', 'syncing', 'error'};
      if (includeConflicts) statuses.add('conflict');

      // 2. Fetch queue in deterministic FIFO order (oldest first).
      var rows = await storage.fetchSyncQueue(
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
      final isManualOrForced = onlyRequestId != null || includeConflicts;
      final now = DateTime.now();

      // Process in strict FIFO order (rows is already oldest-first).
      for (var i = 0; i < rows.length; i++) {
        final record = rows[i];

        // 3. Evaluate bounded exponential backoff for previously failed transactions.
        if (!isManualOrForced && record.attempts > 0) {
          final backoffSec = computeBackoffSeconds(record.attempts);
          final eligibleAt = record.updatedAt.add(Duration(seconds: backoffSec));
          if (now.isBefore(eligibleAt)) {
            // Head-of-line transaction is not yet eligible for retry.
            // Halt queue execution to preserve strict chronological FIFO order.
            pending += (rows.length - i);
            break;
          }
        }

        // 3b. Validate multi-tenant and cross-location boundary isolation
        final payloadTenant = record.payload['tenant_id']?.toString();
        if (payloadTenant != null && payloadTenant.isNotEmpty && payloadTenant != tenantId) {
          await storage.markConflict(
            record.requestId,
            code: OfflineConflictCodes.tenantMismatch,
            message: 'Cross-tenant sync rejected: payload tenant $payloadTenant != session tenant $tenantId.',
          );
          conflicts++;
          continue;
        }

        final payloadLocation = record.payload['location_id']?.toString();
        if (payloadLocation != null && payloadLocation.isNotEmpty && payloadLocation != locationId) {
          await storage.markConflict(
            record.requestId,
            code: OfflineConflictCodes.locationMismatch,
            message: 'Cross-location sync rejected: payload location $payloadLocation != terminal location $locationId.',
          );
          conflicts++;
          continue;
        }

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
              code: verification.conflictCode ?? OfflineConflictCodes.serverValidation,
              message: verification.conflictMessage ?? 'Server rejected offline invoice.',
            );
            conflicts++;

            // If session/auth expired, halt the queue because subsequent transactions will also fail auth.
            if (verification.conflictCode == OfflineConflictCodes.authExpired) {
              pending += (rows.length - i - 1);
              break;
            }
          } else if (verification.isSuccess) {
            await storage.markSynced(record.requestId, verification.rawResponse);
            synced++;
          } else {
            // Missing GST snapshot / journal evidence is treated as server validation failure.
            await storage.markConflict(
              record.requestId,
              code: verification.conflictCode ?? OfflineConflictCodes.unexpectedError,
              message: verification.conflictMessage ??
                  'Sync response missing authoritative GST recovery evidence.',
            );
            conflicts++;
          }
        } catch (error) {
          // Transport / network outage is not a permanent failure.
          // Keep the immutable request pending with its original ID and halt the loop
          // to prevent head-of-line skipping.
          await storage.markPending(record.requestId, message: error.toString());
          pending += (rows.length - i);
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
      _activeLocks.remove(key);
    }
  }
}
