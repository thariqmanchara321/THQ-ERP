import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineSyncStatus and Conflict Codes', () {
    test('parses status string values correctly', () {
      expect(OfflineSyncStatus.fromString('pending'), OfflineSyncStatus.pending);
      expect(OfflineSyncStatus.fromString('SYNCING'), OfflineSyncStatus.syncing);
      expect(OfflineSyncStatus.fromString('synced'), OfflineSyncStatus.synced);
      expect(OfflineSyncStatus.fromString('conflict'), OfflineSyncStatus.conflict);
      expect(OfflineSyncStatus.fromString('error'), OfflineSyncStatus.error);
      expect(OfflineSyncStatus.fromString('cancelled'), OfflineSyncStatus.cancelled);
      expect(OfflineSyncStatus.fromString('unknown_state'), OfflineSyncStatus.error);
    });

    test('status helper getters work', () {
      expect(OfflineSyncStatus.pending.isPending, isTrue);
      expect(OfflineSyncStatus.syncing.isSyncing, isTrue);
      expect(OfflineSyncStatus.synced.isSynced, isTrue);
      expect(OfflineSyncStatus.conflict.isConflict, isTrue);
      expect(OfflineSyncStatus.error.isError, isTrue);
      expect(OfflineSyncStatus.cancelled.isCancelled, isTrue);
    });

    test('standard conflict codes are populated', () {
      expect(OfflineConflictCodes.priceChanged, 'PRICE_CHANGED');
      expect(OfflineConflictCodes.taxChanged, 'TAX_CHANGED');
      expect(OfflineConflictCodes.stockConflict, 'STOCK_CONFLICT');
      expect(OfflineConflictCodes.serialConflict, 'SERIAL_CONFLICT');
      expect(OfflineConflictCodes.serverValidation, 'SERVER_VALIDATION');
      expect(OfflineConflictCodes.authExpired, 'AUTH_EXPIRED');
      expect(OfflineConflictCodes.unexpectedError, 'UNEXPECTED_ERROR');
      expect(OfflineConflictCodes.all.length, 7);
    });
  });

  group('OfflineSalePayload and Items Serialization', () {
    test('OfflineSaleItem converts to and from map accurately', () {
      const item = OfflineSaleItem(
        variantId: 'v-101',
        productName: 'Stainless Bolt',
        sku: 'BOLT-SS-01',
        quantity: 5.0,
        baseQuantity: 5.0,
        conversionToBase: 1.0,
        unitId: 'u-pcs',
        unitCode: 'PCS',
        unitPrice: 12.50,
        taxRate: 18.0,
        taxAmount: 11.25,
        discountAmount: 0.0,
        lineTotal: 73.75,
        serialNumbers: ['SN-001', 'SN-002'],
        pricingSource: 'cached',
        trackingMode: 'serial',
        trackingRevision: 2,
      );

      final map = item.toMap();
      final roundtrip = OfflineSaleItem.fromMap(map);

      expect(roundtrip.variantId, 'v-101');
      expect(roundtrip.productName, 'Stainless Bolt');
      expect(roundtrip.sku, 'BOLT-SS-01');
      expect(roundtrip.quantity, 5.0);
      expect(roundtrip.unitPrice, 12.50);
      expect(roundtrip.taxRate, 18.0);
      expect(roundtrip.lineTotal, 73.75);
      expect(roundtrip.serialNumbers, ['SN-001', 'SN-002']);
      expect(roundtrip.trackingMode, 'serial');
      expect(roundtrip.trackingRevision, 2);
    });

    test('OfflineSalePayload serializes and deserializes properly', () {
      const payload = OfflineSalePayload(
        requestId: 'req-uuid-1234',
        localInvoiceNumber: 'OFF-20261126-120000-001',
        tenantId: 'tenant-demo',
        locationId: 'loc-main',
        deviceId: 'dev-pos-1',
        shiftId: 'shift-99',
        customerId: 'cust-walkin',
        customerName: 'Walk-in Customer',
        saleDate: '2026-11-26',
        saleTime: '2026-11-26T12:00:00Z',
        items: [
          OfflineSaleItem(
            variantId: 'v-1',
            productName: 'Widget A',
            sku: 'WID-A',
            quantity: 2.0,
            baseQuantity: 2.0,
            unitPrice: 50.0,
            taxRate: 18.0,
            lineTotal: 118.0,
          ),
        ],
        paymentAllocations: [
          OfflineSalePayment(methodCode: 'cash', amount: 118.0),
        ],
        total: 118.0,
        outstanding: 0.0,
        channel: 'desktop_pos',
      );

      final map = payload.toMap();
      final roundtrip = OfflineSalePayload.fromMap(map);

      expect(roundtrip.requestId, 'req-uuid-1234');
      expect(roundtrip.localInvoiceNumber, 'OFF-20261126-120000-001');
      expect(roundtrip.tenantId, 'tenant-demo');
      expect(roundtrip.channel, 'desktop_pos');
      expect(roundtrip.items.length, 1);
      expect(roundtrip.items.first.productName, 'Widget A');
      expect(roundtrip.paymentAllocations.first.methodCode, 'cash');
      expect(roundtrip.total, 118.0);
    });
  });

  group('OfflineSaleRecord and Compatibility', () {
    test('localNumber getter aliases localInvoiceNumber for mobile compatibility', () {
      final now = DateTime.now();
      final record = OfflineSaleRecord(
        requestId: 'req-1',
        localInvoiceNumber: 'MOB-20261126-120000-002',
        status: 'pending',
        payload: const {'channel': 'mobile_pos'},
        attempts: 0,
        createdAt: now,
        updatedAt: now,
      );

      expect(record.localInvoiceNumber, 'MOB-20261126-120000-002');
      expect(record.localNumber, 'MOB-20261126-120000-002');
      expect(record.isPending, isTrue);
      expect(record.isSyncing, isFalse);
    });

    test('OfflineQueueSummary supports dictionary access', () {
      const summary = OfflineQueueSummary(
        pending: 3,
        conflict: 1,
        error: 0,
        synced: 10,
      );

      expect(summary.pending, 3);
      expect(summary.conflict, 1);
      expect(summary.error, 0);
      expect(summary.synced, 10);
      expect(summary.needsAttention, 4);
      expect(summary.total, 14);

      // Backwards compatibility with mobile pos Map<String, int> subscript syntax:
      expect(summary['pending'], 3);
      expect(summary['conflict'], 1);
      expect(summary['error'], 0);
      expect(summary['synced'], 10);
      expect(summary['nonexistent'], 0);
    });

    test('OfflineSyncResult evaluates sync state', () {
      const fullSync = OfflineSyncResult(attempted: 5, synced: 5, conflicts: 0, pending: 0);
      expect(fullSync.isFullySynced, isTrue);
      expect(fullSync.hasConflicts, isFalse);
      expect(fullSync.hasFailures, isFalse);

      const partialSync = OfflineSyncResult(attempted: 5, synced: 3, conflicts: 1, pending: 1);
      expect(partialSync.isFullySynced, isFalse);
      expect(partialSync.hasConflicts, isTrue);
      expect(partialSync.hasFailures, isTrue);

      const mobileFormat = OfflineSyncResult.positional(4, 4, 0, 0);
      expect(mobileFormat.attempted, 4);
      expect(mobileFormat.synced, 4);
      expect(mobileFormat.isFullySynced, isTrue);
    });
  });

  group('OfflineSyncVerifier', () {
    test('verifies successful authoritative GST sync response', () {
      final response = {
        'ok': true,
        'status': 'synced',
        'authoritative_gst': true,
        'gst_snapshot_id': 'snap-001',
        'gst_journal_id': 'jour-001',
      };

      final result = OfflineSyncVerifier.verify(response);
      expect(result.isSuccess, isTrue);
      expect(result.isConflict, isFalse);
      expect(result.isAuthoritativeGst, isTrue);
      expect(result.gstSnapshotId, 'snap-001');
      expect(result.gstJournalId, 'jour-001');
    });

    test('flags rejection when status is conflict', () {
      final response = {
        'ok': false,
        'status': 'conflict',
        'code': 'PRICE_CHANGED',
        'message': 'Unit price increased to 15.00',
      };

      final result = OfflineSyncVerifier.verify(response);
      expect(result.isSuccess, isFalse);
      expect(result.isConflict, isTrue);
      expect(result.conflictCode, 'PRICE_CHANGED');
      expect(result.conflictMessage, 'Unit price increased to 15.00');
    });

    test('rejects response missing authoritative GST recovery evidence', () {
      final response = {
        'ok': true,
        'status': 'synced',
        'authoritative_gst': false,
      };

      final result = OfflineSyncVerifier.verify(response);
      expect(result.isSuccess, isFalse);
      expect(result.isConflict, isFalse);
      expect(result.conflictMessage, contains('missing authoritative GST'));
    });
  });

  group('OfflineSyncCoordinator Reliability & Mutex Locking', () {
    late FakeOfflineStorage storage;

    setUp(() {
      storage = FakeOfflineStorage();
      OfflineSyncCoordinator.resetLocksForTest();
    });

    test('computes bounded exponential backoff up to 60 seconds', () {
      expect(OfflineSyncCoordinator.computeBackoffSeconds(0), 0);
      expect(OfflineSyncCoordinator.computeBackoffSeconds(1), 1);
      expect(OfflineSyncCoordinator.computeBackoffSeconds(2), 2);
      expect(OfflineSyncCoordinator.computeBackoffSeconds(3), 4);
      expect(OfflineSyncCoordinator.computeBackoffSeconds(4), 8);
      expect(OfflineSyncCoordinator.computeBackoffSeconds(5), 16);
      expect(OfflineSyncCoordinator.computeBackoffSeconds(6), 32);
      expect(OfflineSyncCoordinator.computeBackoffSeconds(7), 60);
      expect(OfflineSyncCoordinator.computeBackoffSeconds(15), 60);
    });

    test('recovers interrupted sync records on startup before sync', () async {
      storage.records.add(OfflineSaleRecord(
        requestId: 'req-orphaned',
        localInvoiceNumber: 'LOCAL-001',
        status: 'syncing',
        payload: const {'item': 'widget'},
        attempts: 1,
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));

      final coordinator = OfflineSyncCoordinator(storage: storage);
      final result = await coordinator.syncQueue(
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        deviceId: 'dev-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          return {
            'ok': true,
            'status': 'synced',
            'authoritative_gst': true,
            'gst_snapshot_id': 'snap-1',
            'gst_journal_id': 'jour-1',
          };
        },
      );

      expect(storage.recoveredCount, equals(1));
      expect(result.synced, equals(1));
      expect(result.isFullySynced, isTrue);
      expect(storage.records.first.isSynced, isTrue);
    });

    test('enforces strict chronological FIFO processing order', () async {
      final now = DateTime.now();
      storage.records.addAll([
        OfflineSaleRecord(
          requestId: 'req-3',
          localInvoiceNumber: 'LOCAL-003',
          status: 'pending',
          payload: const {'seq': 3},
          attempts: 0,
          createdAt: now.add(const Duration(seconds: 2)),
          updatedAt: now.add(const Duration(seconds: 2)),
        ),
        OfflineSaleRecord(
          requestId: 'req-1',
          localInvoiceNumber: 'LOCAL-001',
          status: 'pending',
          payload: const {'seq': 1},
          attempts: 0,
          createdAt: now,
          updatedAt: now,
        ),
        OfflineSaleRecord(
          requestId: 'req-2',
          localInvoiceNumber: 'LOCAL-002',
          status: 'pending',
          payload: const {'seq': 2},
          attempts: 0,
          createdAt: now.add(const Duration(seconds: 1)),
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
      ]);

      final processedIds = <String>[];
      final coordinator = OfflineSyncCoordinator(storage: storage);
      final result = await coordinator.syncQueue(
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        deviceId: 'dev-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          processedIds.add(requestId);
          return {
            'ok': true,
            'status': 'synced',
            'authoritative_gst': true,
            'gst_snapshot_id': 'snap-$requestId',
            'gst_journal_id': 'jour-$requestId',
          };
        },
      );

      expect(result.synced, equals(3));
      expect(processedIds, equals(['req-1', 'req-2', 'req-3']));
    });

    test('single-flight locking prevents concurrent execution for same device', () async {
      storage.records.add(OfflineSaleRecord(
        requestId: 'req-slow',
        localInvoiceNumber: 'LOCAL-SLOW',
        status: 'pending',
        payload: const {},
        attempts: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final coord1 = OfflineSyncCoordinator(storage: storage);
      final coord2 = OfflineSyncCoordinator(storage: storage);

      late OfflineSyncResult result1;
      late OfflineSyncResult result2;

      // Launch two concurrent sync operations with different coordinator instances
      final future1 = coord1.syncQueue(
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        deviceId: 'dev-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          await Future.delayed(const Duration(milliseconds: 50));
          return {
            'ok': true,
            'status': 'synced',
            'authoritative_gst': true,
            'gst_snapshot_id': 'snap-1',
            'gst_journal_id': 'jour-1',
          };
        },
      );

      final future2 = coord2.syncQueue(
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        deviceId: 'dev-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          return {'ok': true};
        },
      );

      final results = await Future.wait([future1, future2]);
      result1 = results[0];
      result2 = results[1];

      // One completed successfully; the concurrent invocation was safely rejected with 0 attempted
      expect(result1.synced + result2.synced, equals(1));
      expect(result1.attempted == 0 || result2.attempted == 0, isTrue);

      // Lock is released after completion
      expect(OfflineSyncCoordinator.isSyncLocked('tenant-1', 'dev-1'), isFalse);
    });

    test('transport failure halts queue immediately and preserves immutable request', () async {
      storage.records.addAll([
        OfflineSaleRecord(
          requestId: 'req-success',
          localInvoiceNumber: 'LOCAL-1',
          status: 'pending',
          payload: const {'total': 100},
          attempts: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        OfflineSaleRecord(
          requestId: 'req-fail',
          localInvoiceNumber: 'LOCAL-2',
          status: 'pending',
          payload: const {'total': 200},
          attempts: 0,
          createdAt: DateTime.now().add(const Duration(seconds: 1)),
          updatedAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
        OfflineSaleRecord(
          requestId: 'req-blocked',
          localInvoiceNumber: 'LOCAL-3',
          status: 'pending',
          payload: const {'total': 300},
          attempts: 0,
          createdAt: DateTime.now().add(const Duration(seconds: 2)),
          updatedAt: DateTime.now().add(const Duration(seconds: 2)),
        ),
      ]);

      final coordinator = OfflineSyncCoordinator(storage: storage);
      final result = await coordinator.syncQueue(
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        deviceId: 'dev-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          if (requestId == 'req-fail') {
            throw Exception('Connection reset by peer');
          }
          return {
            'ok': true,
            'status': 'synced',
            'authoritative_gst': true,
            'gst_snapshot_id': 'snap-$requestId',
            'gst_journal_id': 'jour-$requestId',
          };
        },
      );

      expect(result.synced, equals(1));
      expect(result.pending, equals(2)); // Head-of-line halted: req-fail and req-blocked remain pending

      final failedRecord = await storage.invoice('req-fail');
      expect(failedRecord!.isPending, isTrue);
      expect(failedRecord.conflictMessage, contains('Connection reset by peer'));

      final blockedRecord = await storage.invoice('req-blocked');
      expect(blockedRecord!.isPending, isTrue);
      expect(blockedRecord.attempts, equals(0)); // Never attempted, preserving FIFO order
    });

    test('AUTH_EXPIRED conflict halts queue execution immediately', () async {
      storage.records.addAll([
        OfflineSaleRecord(
          requestId: 'req-auth-fail',
          localInvoiceNumber: 'LOCAL-1',
          status: 'pending',
          payload: const {},
          attempts: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        OfflineSaleRecord(
          requestId: 'req-auth-blocked',
          localInvoiceNumber: 'LOCAL-2',
          status: 'pending',
          payload: const {},
          attempts: 0,
          createdAt: DateTime.now().add(const Duration(seconds: 1)),
          updatedAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      ]);

      final coordinator = OfflineSyncCoordinator(storage: storage);
      final result = await coordinator.syncQueue(
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        deviceId: 'dev-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          return {
            'ok': false,
            'status': 'conflict',
            'code': OfflineConflictCodes.authExpired,
            'message': 'Device token has expired',
          };
        },
      );

      expect(result.conflicts, equals(1));
      expect(result.pending, equals(1));

      final authFail = await storage.invoice('req-auth-fail');
      expect(authFail!.isConflict, isTrue);
      expect(authFail.conflictCode, OfflineConflictCodes.authExpired);

      final authBlocked = await storage.invoice('req-auth-blocked');
      expect(authBlocked!.isPending, isTrue);
      expect(authBlocked.attempts, equals(0));
    });
  });
}

class FakeOfflineStorage implements OfflineStorageAdapter {
  final List<OfflineSaleRecord> records = [];
  final Map<String, dynamic> metadata = {};
  int recoveredCount = 0;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> setMeta(String key, Object? value) async => metadata[key] = value;
  @override
  Future<dynamic> getMeta(String key) async => metadata[key];

  @override
  Future<String> queueSale({
    required String requestId,
    required String tenantId,
    required String locationId,
    required String deviceId,
    required Map<String, dynamic> payload,
    bool printRequested = false,
  }) async {
    final num = 'LOCAL-$requestId';
    records.add(OfflineSaleRecord(
      requestId: requestId,
      localInvoiceNumber: num,
      status: 'pending',
      payload: payload,
      attempts: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      printRequested: printRequested,
    ));
    return num;
  }

  @override
  Future<List<OfflineSaleRecord>> fetchQueue({
    required String tenantId,
    required String deviceId,
    Set<String>? statuses,
    int limit = 300,
  }) async {
    return records
        .where((r) => statuses == null || statuses.contains(r.status))
        .take(limit)
        .toList();
  }

  @override
  Future<List<OfflineSaleRecord>> fetchSyncQueue({
    required String tenantId,
    required String deviceId,
    Set<String>? statuses,
    int limit = 300,
  }) async {
    final matching = records
        .where((r) => statuses == null || statuses.contains(r.status))
        .toList();
    matching.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return matching.take(limit).toList();
  }

  @override
  Future<int> recoverInterruptedSync({
    required String tenantId,
    required String deviceId,
  }) async {
    var count = 0;
    for (var i = 0; i < records.length; i++) {
      if (records[i].status == 'syncing') {
        records[i] = records[i].copyWith(
          status: 'pending',
          attempts: 0,
          conflictMessage: 'Recovered after interrupted sync',
        );
        count++;
      }
    }
    recoveredCount += count;
    return count;
  }

  @override
  Future<OfflineSaleRecord?> invoice(String requestId) async {
    return records.where((r) => r.requestId == requestId).firstOrNull;
  }

  @override
  Future<OfflineQueueSummary> queueSummary({
    required String tenantId,
    required String deviceId,
  }) async {
    return OfflineQueueSummary(
      pending: records.where((r) => r.isPending || r.isSyncing).length,
      conflict: records.where((r) => r.isConflict).length,
      error: records.where((r) => r.isError).length,
      synced: records.where((r) => r.isSynced).length,
    );
  }

  @override
  Future<void> markSyncing(String requestId) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(
        status: 'syncing',
        attempts: records[idx].attempts + 1,
      );
    }
  }

  @override
  Future<void> markPending(String requestId, {String? message}) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(
        status: 'pending',
        conflictMessage: message,
      );
    }
  }

  @override
  Future<void> markConflict(
    String requestId, {
    required String code,
    required String message,
  }) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(
        status: 'conflict',
        conflictCode: code,
        conflictMessage: message,
      );
    }
  }

  @override
  Future<void> markSynced(
    String requestId,
    Map<String, dynamic> serverResponse,
  ) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(
        status: 'synced',
        serverResponse: serverResponse,
      );
    }
  }

  @override
  Future<void> retry(String requestId) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(status: 'pending');
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(status: 'cancelled');
    }
  }
}
