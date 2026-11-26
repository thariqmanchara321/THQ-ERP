import 'offline_queue_summary.dart';
import 'offline_sale_record.dart';

/// Abstract storage adapter defining the unified offline database lifecycle.
///
/// Implemented by Desktop POS (native SQLite + SQLCipher encryption) and
/// Mobile POS (platform-specific durable Sqflite).
abstract class OfflineStorageAdapter {
  /// Opens the database and ensures all required tables and indexes exist.
  Future<void> initialize();

  /// Closes the underlying database connection.
  Future<void> close();

  /// Stores metadata key-value pair.
  Future<void> setMeta(String key, Object? value);

  /// Retrieves metadata by key.
  Future<dynamic> getMeta(String key);

  /// Queues a sale transaction into the durable local table.
  ///
  /// Returns the assigned local invoice number (e.g., `OFF-YYYYMMDD-...` or `MOB-YYYYMMDD-...`).
  /// Idempotent: re-queuing with the same `requestId` returns the existing local number.
  Future<String> queueSale({
    required String requestId,
    required String tenantId,
    required String locationId,
    required String deviceId,
    required Map<String, dynamic> payload,
    bool printRequested = false,
  });

  /// Retrieves queued transactions matching criteria, ordered chronologically (newest first).
  Future<List<OfflineSaleRecord>> fetchQueue({
    required String tenantId,
    required String deviceId,
    Set<String>? statuses,
    int limit = 300,
  });

  /// Retrieves a single transaction record by its unique request ID.
  Future<OfflineSaleRecord?> invoice(String requestId);

  /// Retrieves queue statistics by status.
  Future<OfflineQueueSummary> queueSummary({
    required String tenantId,
    required String deviceId,
  });

  /// Transitions transaction status to 'syncing' and increments attempt counter.
  Future<void> markSyncing(String requestId);

  /// Transitions transaction status back to 'pending' upon transport/network error.
  Future<void> markPending(String requestId, {String? message});

  /// Transitions transaction status to 'conflict' with error details.
  Future<void> markConflict(
    String requestId, {
    required String code,
    required String message,
  });

  /// Transitions transaction status to 'synced' with server response evidence.
  Future<void> markSynced(
    String requestId,
    Map<String, dynamic> serverResponse,
  );

  /// Resets a conflicted or errored transaction back to 'pending' for retry.
  Future<void> retry(String requestId);

  /// Locally cancels an unsynced transaction and rolls back reserved inventory/serials.
  ///
  /// Throws [StateError] if the transaction has already synchronized with the server.
  Future<void> cancel(String requestId);
}
