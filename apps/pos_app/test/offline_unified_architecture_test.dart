import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/models/customer.dart';
import 'package:pos_app/models/inventory_product.dart';
import 'package:pos_app/services/offline_pos_service.dart';
import 'package:pos_app/services/pos_database_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late InMemoryPosDatabaseKeyStore keyStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thq_pos_arch_test_');
    dbPath = p.join(tempDir.path, 'thq_pos_offline_v486.sqlite');
    keyStore = InMemoryPosDatabaseKeyStore();
  });

  tearDown(() async {
    await OfflinePosService.instance.close();
    if (await tempDir.exists()) {
      for (int i = 0; i < 5; i++) {
        try {
          await tempDir.delete(recursive: true);
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }
  });

  test('OfflinePosService implements OfflineStorageAdapter contract', () async {
    final OfflineStorageAdapter adapter = OfflinePosService.instance;
    await OfflinePosService.instance.initialize(
      customDatabasePath: dbPath,
      keyStore: keyStore,
    );
    expect(adapter, isA<OfflineStorageAdapter>());
    await adapter.close();
  });

  test('Offline sale queuing, durability across restart, and idempotency', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    // Seed product and catalogue
    final product = InventoryProduct.fromMap({
      'product_id': 'p-1',
      'variant_id': 'v-1',
      'sku': 'SKU-BOLT',
      'product_name': 'Hex Bolt M8',
      'variant_name': 'M8 x 50',
      'selling_price': 15.0,
      'cost_price': 8.0,
      'tax_rate': 18.0,
      'stock_quantity': 20.0,
      'tracking_mode': 'none',
    });
    final customer = Customer.fromMap({
      'id': 'c-1',
      'name': 'Acme Hardware',
      'phone': '9876543210',
      'is_walk_in': false,
    });

    await service.replaceCatalogue(
      tenantId: 't-arch',
      locationId: 'loc-1',
      products: [product],
      customers: [customer],
      serials: [],
    );

    final payload = <String, dynamic>{
      'customer_id': 'c-1',
      'customer_name': 'Acme Hardware',
      'sale_date': '2026-11-26',
      'sale_time': '2026-11-26T10:00:00Z',
      'items': [
        {
          'variant_id': 'v-1',
          'product_name': 'Hex Bolt M8',
          'sku': 'SKU-BOLT',
          'quantity': 5.0,
          'base_quantity': 5.0,
          'conversion_to_base': 1.0,
          'unit_code': 'PCS',
          'unit_price': 15.0,
          'tax_rate': 18.0,
          'discount_amount': 0.0,
          'serial_numbers': <String>[],
        }
      ],
      'payment_allocations': [
        {'method_code': 'cash', 'amount': 88.50}
      ],
      'total': 88.50,
      'outstanding': 0.0,
    };

    // 1. Queue sale
    final localNum1 = await service.queueSale(
      requestId: 'req-sale-001',
      tenantId: 't-arch',
      locationId: 'loc-1',
      deviceId: 'dev-1',
      payload: payload,
      printRequested: true,
    );

    expect(localNum1, startsWith('OFF-'));

    // 2. Idempotent re-queue with same requestId returns same number
    final localNum2 = await service.queueSale(
      requestId: 'req-sale-001',
      tenantId: 't-arch',
      locationId: 'loc-1',
      deviceId: 'dev-1',
      payload: payload,
    );
    expect(localNum2, equals(localNum1));

    // 3. Verify stock reservation applied
    final cached = await service.cachedProducts(tenantId: 't-arch', locationId: 'loc-1');
    expect(cached.first.stockQuantity, equals(15.0)); // 20 - 5 = 15

    // 4. Restart service and verify queue record survives intact
    await service.close();
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    final record = await service.invoice('req-sale-001');
    expect(record, isNotNull);
    expect(record!.requestId, 'req-sale-001');
    expect(record.localInvoiceNumber, localNum1);
    expect(record.localNumber, localNum1); // Mobile POS alias compatibility
    expect(record.status, OfflineSyncStatus.pending.value);
    expect(record.isPending, isTrue);
    expect(record.printRequested, isTrue);

    // 5. Test queueSummary
    final summary = await service.queueSummary(tenantId: 't-arch', deviceId: 'dev-1');
    expect(summary.pending, equals(1));
    expect(summary.needsAttention, equals(1));
    expect(summary['pending'], equals(1));

    // 6. Test fetchQueue
    final queueRows = await service.fetchQueue(tenantId: 't-arch', deviceId: 'dev-1');
    expect(queueRows.length, equals(1));
    expect(queueRows.first.requestId, 'req-sale-001');

    // 7. Transition to syncing then synced with GST snapshot
    await service.markSyncing('req-sale-001');
    final syncingRecord = await service.invoice('req-sale-001');
    expect(syncingRecord!.isSyncing, isTrue);
    expect(syncingRecord.attempts, equals(1));

    final serverResponse = {
      'ok': true,
      'status': 'synced',
      'authoritative_gst': true,
      'gst_snapshot_id': 'snap-xyz',
      'gst_journal_id': 'jour-xyz',
    };
    final verification = OfflineSyncVerifier.verify(serverResponse);
    expect(verification.isSuccess, isTrue);

    await service.markSynced('req-sale-001', verification.rawResponse);
    final syncedRecord = await service.invoice('req-sale-001');
    expect(syncedRecord!.isSynced, isTrue);
    expect(syncedRecord.serverResponse!['gst_snapshot_id'], 'snap-xyz');
  });

  test('Conflict rejection and local cancellation reverses inventory reservation', () async {
    final service = OfflinePosService.instance;
    await service.initialize(customDatabasePath: dbPath, keyStore: keyStore);

    final product = InventoryProduct.fromMap({
      'product_id': 'p-2',
      'variant_id': 'v-2',
      'sku': 'SKU-WIDGET',
      'product_name': 'Smart Sensor',
      'variant_name': 'Standard',
      'selling_price': 100.0,
      'cost_price': 50.0,
      'tax_rate': 18.0,
      'stock_quantity': 10.0,
      'tracking_mode': 'none',
    });

    await service.replaceCatalogue(
      tenantId: 't-arch',
      locationId: 'loc-1',
      products: [product],
      customers: [],
      serials: [],
    );

    final payload = <String, dynamic>{
      'customer_id': 'walk-in',
      'items': [
        {
          'variant_id': 'v-2',
          'product_name': 'Smart Sensor',
          'sku': 'SKU-WIDGET',
          'quantity': 3.0,
          'base_quantity': 3.0,
          'unit_price': 100.0,
        }
      ],
      'total': 354.0,
    };

    await service.queueSale(
      requestId: 'req-conflict-01',
      tenantId: 't-arch',
      locationId: 'loc-1',
      deviceId: 'dev-1',
      payload: payload,
    );

    // Stock reserved: 10 - 3 = 7
    var products = await service.cachedProducts(tenantId: 't-arch', locationId: 'loc-1');
    expect(products.first.stockQuantity, equals(7.0));

    // Server returns price conflict
    final conflictResponse = {
      'ok': false,
      'status': 'conflict',
      'code': OfflineConflictCodes.priceChanged,
      'message': 'Price changed from 100 to 120',
    };
    final verification = OfflineSyncVerifier.verify(conflictResponse);
    expect(verification.isConflict, isTrue);

    await service.markConflict(
      'req-conflict-01',
      code: verification.conflictCode!,
      message: verification.conflictMessage!,
    );

    final conflictRecord = await service.invoice('req-conflict-01');
    expect(conflictRecord!.isConflict, isTrue);
    expect(conflictRecord.conflictCode, OfflineConflictCodes.priceChanged);

    // Local cancellation of the conflicted invoice
    await service.cancel('req-conflict-01');

    final cancelledRecord = await service.invoice('req-conflict-01');
    expect(cancelledRecord!.isCancelled, isTrue);

    // Reserved stock must be restored to 10
    products = await service.cachedProducts(tenantId: 't-arch', locationId: 'loc-1');
    expect(products.first.stockQuantity, equals(10.0));
  });
}
