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
}
