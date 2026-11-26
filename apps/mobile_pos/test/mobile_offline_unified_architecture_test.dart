import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pos/services/mobile_pos_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = createDatabaseFactoryFfi(noIsolate: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thq_mpos_arch_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    await MobilePosLocalStore.instance.close();
  });

  tearDown(() async {
    await MobilePosLocalStore.instance.close();
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

  test('MobilePosLocalStore implements OfflineStorageAdapter contract', () async {
    final OfflineStorageAdapter adapter = MobilePosLocalStore.instance;
    await adapter.initialize();
    expect(adapter, isA<OfflineStorageAdapter>());
    await adapter.close();
  });

  test('Mobile POS sale queuing, idempotency, and OfflineQueueSummary compatibility', () async {
    final local = MobilePosLocalStore.instance;
    await local.initialize();

    // 1. Replace catalogue with sample product
    await local.replaceCatalogue(
      tenantId: 't-mpos',
      locationId: 'loc-1',
      products: [
        {
          'product_id': 'p-1',
          'variant_id': 'v-1',
          'product_name': 'Mobile Power Bank',
          'sku': 'PB-10K',
          'stock_quantity': 15.0,
          'selling_price': 1200.0,
          'tax_rate': 18.0,
          'tracking_mode': 'none',
        }
      ],
      customers: [
        {
          'customer_id': 'c-1',
          'customer_name': 'Store Customer',
          'phone': '9876500000',
        }
      ],
      serials: [],
      manifest: {'version': '8.2.2'},
    );

    final payload = <String, dynamic>{
      'customer_id': 'c-1',
      'customer_name': 'Store Customer',
      'items': [
        {
          'variant_id': 'v-1',
          'product_name': 'Mobile Power Bank',
          'sku': 'PB-10K',
          'quantity': 2.0,
          'base_quantity': 2.0,
          'unit_price': 1200.0,
          'tax_rate': 18.0,
        }
      ],
      'payment_allocations': [
        {'method_code': 'cash', 'amount': 2832.0}
      ],
      'total': 2832.0,
    };

    // 2. Queue sale
    final localNum1 = await local.queueSale(
      requestId: 'req-mpos-001',
      tenantId: 't-mpos',
      locationId: 'loc-1',
      deviceId: 'dev-m1',
      payload: payload,
      printRequested: true,
    );

    expect(localNum1, startsWith('MOB-'));

    // 3. Idempotent re-queue
    final localNum2 = await local.queueSale(
      requestId: 'req-mpos-001',
      tenantId: 't-mpos',
      locationId: 'loc-1',
      deviceId: 'dev-m1',
      payload: payload,
    );
    expect(localNum2, equals(localNum1));

    // 4. Verify stock reserved: 15 - 2 = 13
    final products = await local.products('t-mpos', 'loc-1');
    expect(products.first.stockQuantity, equals(13.0));

    // 5. Verify invoice record and aliases
    final invoice = await local.invoiceByRequest('req-mpos-001');
    expect(invoice, isNotNull);
    expect(invoice!.requestId, 'req-mpos-001');
    expect(invoice.localNumber, localNum1);
    expect(invoice.localInvoiceNumber, localNum1);
    expect(invoice.isPending, isTrue);
    expect(invoice.printRequested, isTrue);

    // 6. Test OfflineQueueSummary via summary()
    final summary = await local.summary('t-mpos', 'dev-m1');
    expect(summary, isA<OfflineQueueSummary>());
    expect(summary.pending, equals(1));
    expect(summary.needsAttention, equals(1));
    // Test backward compatible Map subscript syntax
    expect(summary['pending'], equals(1));
    expect(summary['conflict'], equals(0));

    // 7. Test fetchQueue
    final queueRecords = await local.fetchQueue(tenantId: 't-mpos', deviceId: 'dev-m1');
    expect(queueRecords.length, equals(1));
    expect(queueRecords.first.requestId, 'req-mpos-001');

    // 8. Mark synced with authoritative GST verification
    await local.markSyncing('req-mpos-001');
    final syncing = await local.invoice('req-mpos-001');
    expect(syncing!.isSyncing, isTrue);
    expect(syncing.attempts, equals(1));

    final serverResponse = {
      'ok': true,
      'status': 'synced',
      'authoritative_gst': true,
      'gst_snapshot_id': 'snap-mpos-1',
      'gst_journal_id': 'jour-mpos-1',
    };
    final verification = OfflineSyncVerifier.verify(serverResponse);
    expect(verification.isSuccess, isTrue);

    await local.markSynced('req-mpos-001', verification.rawResponse);
    final synced = await local.invoice('req-mpos-001');
    expect(synced!.isSynced, isTrue);
    expect(synced.serverResponse!['gst_snapshot_id'], 'snap-mpos-1');
  });

  test('Mobile POS conflict handling and cancellation reverts stock', () async {
    final local = MobilePosLocalStore.instance;
    await local.initialize();

    await local.replaceCatalogue(
      tenantId: 't-mpos',
      locationId: 'loc-1',
      products: [
        {
          'product_id': 'p-2',
          'variant_id': 'v-2',
          'product_name': 'Headphones',
          'sku': 'HP-01',
          'stock_quantity': 5.0,
          'selling_price': 500.0,
          'tax_rate': 18.0,
          'tracking_mode': 'none',
        }
      ],
      customers: [],
      serials: [],
      manifest: {},
    );

    final payload = <String, dynamic>{
      'customer_id': 'walk-in',
      'items': [
        {
          'variant_id': 'v-2',
          'product_name': 'Headphones',
          'sku': 'HP-01',
          'quantity': 2.0,
          'base_quantity': 2.0,
          'unit_price': 500.0,
        }
      ],
      'total': 1180.0,
    };

    await local.queueSale(
      requestId: 'req-mpos-conflict',
      tenantId: 't-mpos',
      locationId: 'loc-1',
      deviceId: 'dev-m1',
      payload: payload,
    );

    var products = await local.products('t-mpos', 'loc-1');
    expect(products.first.stockQuantity, equals(3.0)); // 5 - 2 = 3

    await local.markConflict(
      'req-mpos-conflict',
      code: OfflineConflictCodes.stockConflict,
      message: 'Stock unavailable on server',
    );

    final conflicted = await local.invoice('req-mpos-conflict');
    expect(conflicted!.isConflict, isTrue);
    expect(conflicted.conflictCode, OfflineConflictCodes.stockConflict);

    // Cancel and verify stock restored
    await local.cancel('req-mpos-conflict');
    final cancelled = await local.invoice('req-mpos-conflict');
    expect(cancelled!.isCancelled, isTrue);

    products = await local.products('t-mpos', 'loc-1');
    expect(products.first.stockQuantity, equals(5.0)); // Restored
  });
}
