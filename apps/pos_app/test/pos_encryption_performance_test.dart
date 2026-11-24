// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/models/customer.dart';
import 'package:pos_app/models/inventory_product.dart';
import 'package:pos_app/services/offline_pos_service.dart';
import 'package:pos_app/services/pos_database_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String encDbPath;
  late InMemoryPosDatabaseKeyStore keyStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thq_perf_test_');
    encDbPath = p.join(tempDir.path, 'enc.sqlite');
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

  test('Benchmark: database open, catalog lookup, sale queue, and sync summary', () async {
    final service = OfflinePosService.instance;

    // 1. Measure Encrypted Open Time
    final swOpen = Stopwatch()..start();
    await service.initialize(customDatabasePath: encDbPath, keyStore: keyStore);
    swOpen.stop();
    final encOpenMs = swOpen.elapsedMicroseconds / 1000.0;

    // Seed 100 products
    final products = List.generate(
      100,
      (i) => InventoryProduct.fromMap({
        'product_id': 'prod_$i',
        'variant_id': 'var_$i',
        'product_name': 'Item $i Grade A',
        'selling_price': 100.0 + i,
        'stock_quantity': 500.0,
        'search_codes': ['SKU$i', 'BAR$i'],
      }),
    );
    await service.replaceCatalogue(
      tenantId: 't-perf',
      locationId: 'loc-perf',
      products: products,
      customers: [
        Customer.fromMap({'customer_id': 'c-1', 'customer_name': 'Acme', 'is_walk_in': false, 'status': 'active'}),
      ],
      serials: [],
    );

    // 2. Measure Product Lookup
    final swLookup = Stopwatch()..start();
    for (int i = 0; i < 10; i++) {
      await service.cachedProducts(tenantId: 't-perf', locationId: 'loc-perf');
    }
    swLookup.stop();
    final avgLookupMs = (swLookup.elapsedMicroseconds / 1000.0) / 10.0;

    // 3. Measure Queue Sale (Transaction write + stock decrement + WAL commit)
    final swSale = Stopwatch()..start();
    for (int i = 0; i < 20; i++) {
      await service.queueSale(
        requestId: 'req-perf-$i',
        tenantId: 't-perf',
        locationId: 'loc-perf',
        deviceId: 'dev-perf',
        payload: {
          'items': [
            {'variant_id': 'var_${i % 100}', 'quantity': 1.0, 'base_quantity': 1.0, 'price': 150.0}
          ],
          'total': 150.0,
        },
        printRequested: false,
      );
    }
    swSale.stop();
    final avgSaleMs = (swSale.elapsedMicroseconds / 1000.0) / 20.0;

    // 4. Measure Sync Queue Access & Summary
    final swQueue = Stopwatch()..start();
    for (int i = 0; i < 10; i++) {
      await service.queue(tenantId: 't-perf', deviceId: 'dev-perf');
      await service.summary(tenantId: 't-perf', deviceId: 'dev-perf');
    }
    swQueue.stop();
    final avgQueueSummaryMs = (swQueue.elapsedMicroseconds / 1000.0) / 10.0;

    print('=== THQ POS Database Encryption Performance Metrics ===');
    print('Encrypted Database Open: ${encOpenMs.toStringAsFixed(2)} ms');
    print('Product Catalog Lookup (100 items): ${avgLookupMs.toStringAsFixed(2)} ms');
    print('Transaction Save (Billing + Stock Reservation): ${avgSaleMs.toStringAsFixed(2)} ms');
    print('Queue & Summary Access: ${avgQueueSummaryMs.toStringAsFixed(2)} ms');
    print('========================================================');

    expect(encOpenMs, lessThan(300.0)); // well under 300ms on cold initialization
    expect(avgLookupMs, lessThan(50.0)); // well under 50ms
    expect(avgSaleMs, lessThan(50.0)); // fast billing latency
    expect(avgQueueSummaryMs, lessThan(30.0));

    await service.close();
  });
}
