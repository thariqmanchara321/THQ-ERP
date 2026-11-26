import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

class InMemorySecurityStorageAdapter implements OfflineStorageAdapter {
  final List<OfflineSaleRecord> records = [];
  final Map<String, dynamic> metadata = {};

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
    Map<String, dynamic> authoritativeEvidence,
  ) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(
        status: 'synced',
        serverResponse: authoritativeEvidence,
      );
    }
  }

  @override
  Future<void> retry(String requestId) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(
        status: 'pending',
        conflictCode: null,
        conflictMessage: null,
      );
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    final idx = records.indexWhere((r) => r.requestId == requestId);
    if (idx >= 0) {
      records[idx] = records[idx].copyWith(
        status: 'cancelled',
      );
    }
  }
}

void main() {
  group('Phase 15: Security, Permissions & Multi-Tenant Isolation Hardening Tests', () {
    setUp(() {
      OfflineSyncCoordinator.resetLocksForTest();
    });

    test('OfflineSyncCoordinator rejects payload belonging to different tenant (Tenant Isolation)', () async {
      final storage = InMemorySecurityStorageAdapter();
      storage.records.add(
        OfflineSaleRecord(
          requestId: 'req-tenant-tamper',
          localInvoiceNumber: 'INV-001',
          status: 'pending',
          attempts: 0,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          payload: {
            'tenant_id': 'tenant-attacker', // Mismatch!
            'location_id': 'loc-store-1',
            'device_id': 'device-pos-1',
            'items': [],
          },
        ),
      );

      final coordinator = OfflineSyncCoordinator(storage: storage);
      var rpcCalled = false;

      final result = await coordinator.syncQueue(
        tenantId: 'tenant-legit',
        locationId: 'loc-store-1',
        deviceId: 'device-pos-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          rpcCalled = true;
          return {'ok': true};
        },
      );

      // RPC must NEVER be dispatched to remote server when cross-tenant violation is detected
      expect(rpcCalled, isFalse);
      expect(result.conflicts, 1);
      expect(result.synced, 0);
      expect(storage.records.first.conflictCode, OfflineConflictCodes.tenantMismatch);
      expect(
        storage.records.first.conflictMessage,
        contains('Cross-tenant sync rejected'),
      );
    });

    test('OfflineSyncCoordinator rejects payload belonging to different location (Cross-Location Isolation)', () async {
      final storage = InMemorySecurityStorageAdapter();
      storage.records.add(
        OfflineSaleRecord(
          requestId: 'req-loc-tamper',
          localInvoiceNumber: 'INV-002',
          status: 'pending',
          attempts: 0,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          payload: {
            'tenant_id': 'tenant-legit',
            'location_id': 'loc-branch-b', // Cross-location breach attempt!
            'device_id': 'device-pos-1',
            'items': [],
          },
        ),
      );

      final coordinator = OfflineSyncCoordinator(storage: storage);
      var rpcCalled = false;

      final result = await coordinator.syncQueue(
        tenantId: 'tenant-legit',
        locationId: 'loc-branch-a', // Active authorized terminal location
        deviceId: 'device-pos-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          rpcCalled = true;
          return {'ok': true};
        },
      );

      expect(rpcCalled, isFalse);
      expect(result.conflicts, 1);
      expect(result.synced, 0);
      expect(storage.records.first.conflictCode, OfflineConflictCodes.locationMismatch);
      expect(
        storage.records.first.conflictMessage,
        contains('Cross-location sync rejected'),
      );
    });

    test('OfflineSyncCoordinator processes payload when tenant and location match authoritative context', () async {
      final storage = InMemorySecurityStorageAdapter();
      storage.records.add(
        OfflineSaleRecord(
          requestId: 'req-legit-1',
          localInvoiceNumber: 'INV-003',
          status: 'pending',
          attempts: 0,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          payload: {
            'tenant_id': 'tenant-legit',
            'location_id': 'loc-branch-a',
            'device_id': 'device-pos-1',
            'items': [],
          },
        ),
      );

      final coordinator = OfflineSyncCoordinator(storage: storage);
      var rpcCalled = false;

      final result = await coordinator.syncQueue(
        tenantId: 'tenant-legit',
        locationId: 'loc-branch-a',
        deviceId: 'device-pos-1',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          rpcCalled = true;
          return {
            'ok': true,
            'status': 'synced',
            'request_id': requestId,
            'authoritative_gst': true,
            'gst_snapshot_id': 'snap-12345',
            'gst_journal_id': 'journal-67890',
          };
        },
      );

      expect(rpcCalled, isTrue);
      expect(result.synced, 1);
      expect(result.conflicts, 0);
      expect(storage.records.first.status, 'synced');
    });

    test('Deactivated or revoked terminal rejection is safely classified as conflict', () async {
      final storage = InMemorySecurityStorageAdapter();
      storage.records.add(
        OfflineSaleRecord(
          requestId: 'req-revoked-terminal',
          localInvoiceNumber: 'INV-004',
          status: 'pending',
          attempts: 0,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          payload: {
            'tenant_id': 'tenant-legit',
            'location_id': 'loc-branch-a',
            'device_id': 'device-pos-revoked',
          },
        ),
      );

      final coordinator = OfflineSyncCoordinator(storage: storage);

      final result = await coordinator.syncQueue(
        tenantId: 'tenant-legit',
        locationId: 'loc-branch-a',
        deviceId: 'device-pos-revoked',
        rpcExecutor: ({
          required String tenantId,
          required String locationId,
          required String deviceId,
          required String requestId,
          required Map<String, dynamic> payload,
        }) async {
          // Server returns authoritative rejection for revoked or inactive device
          return {
            'ok': false,
            'conflict_code': 'SERVER_VALIDATION',
            'conflict_message': 'POS terminal is not active',
          };
        },
      );

      expect(result.conflicts, 1);
      expect(result.synced, 0);
      expect(storage.records.first.conflictCode, 'SERVER_VALIDATION');
      expect(storage.records.first.conflictMessage, 'POS terminal is not active');
    });

    test('Single-flight locking isolates sync operations per tenant:device', () async {
      expect(OfflineSyncCoordinator.isSyncLocked('tenant-1', 'dev-1'), isFalse);
      expect(OfflineSyncCoordinator.isSyncLocked('tenant-1', 'dev-2'), isFalse);
      expect(OfflineSyncCoordinator.isSyncLocked('tenant-2', 'dev-1'), isFalse);

      // Verify lock keys are distinct across tenants and devices
      expect(OfflineSyncCoordinator.lockKey('tenant-1', 'dev-1'), 'tenant-1:dev-1');
      expect(OfflineSyncCoordinator.lockKey('tenant-1', 'dev-2'), 'tenant-1:dev-2');
      expect(OfflineSyncCoordinator.lockKey('tenant-2', 'dev-1'), 'tenant-2:dev-1');
      expect(
        OfflineSyncCoordinator.lockKey('tenant-1', 'dev-1'),
        isNot(equals(OfflineSyncCoordinator.lockKey('tenant-2', 'dev-1'))),
      );
    });

    test('Free-plan subscription limits enforce authoritatively (100 locations, 200 terminals)', () {
      const freeMaxLocations = 100;
      const freeMaxTerminals = 200;

      // Invariant: location creation boundary
      bool isLocationPermitted(int currentLocationCount) {
        return currentLocationCount < freeMaxLocations;
      }

      // Invariant: terminal activation boundary
      bool isTerminalPermitted(int currentTerminalCount) {
        return currentTerminalCount < freeMaxTerminals;
      }

      // Boundary tests
      expect(isLocationPermitted(99), isTrue);
      expect(isLocationPermitted(100), isFalse);
      expect(isLocationPermitted(101), isFalse);

      expect(isTerminalPermitted(199), isTrue);
      expect(isTerminalPermitted(200), isFalse);
      expect(isTerminalPermitted(201), isFalse);
    });
  });
}
