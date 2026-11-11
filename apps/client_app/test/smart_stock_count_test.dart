import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/smart_inventory/tabs/smart_stock_count_tab.dart';
import 'package:client_app/services/client_smart_inventory_service.dart';
import 'package:client_app/services/stock_counting_service.dart';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tenantId = 'tenant-test-01';
  const locationId = 'loc-wh-01';

  const testBusiness = ClientBusiness(
    id: tenantId,
    membershipId: 'mem-1',
    name: 'THQ Test Warehouse',
    slug: 'thq-wh',
    businessType: 'wholesale',
    status: 'active',
  );

  const managerSession = ClientSession(
    business: testBusiness,
    userId: 'user-manager',
    username: 'Bob Manager',
    modules: [
      ClientModule(
        key: 'inventory',
        name: 'Inventory',
        description: null,
        category: 'Inventory',
        sortOrder: 10,
      ),
    ],
    roles: {'manager'},
    permissions: {'inventory.view', 'inventory.manage', 'inventory.stock_count'},
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
  );

  final sampleSnapshotRows = [
    {
      'product_id': 'prod-001',
      'variant_id': 'var-001',
      'product_name': 'Steel Rebar 12mm',
      'variant_name': 'Standard 12m',
      'sku': 'SKU-REBAR-12',
      'barcode': '8901234567001',
      'unit_name': 'MTR',
      'tracking_mode': 'none',
      'system_quantity': 100.0,
      'reserved_quantity': 5.0,
      'damaged_quantity': 0.0,
      'quarantine_quantity': 0.0,
      'available_quantity': 95.0,
    },
    {
      'product_id': 'prod-002',
      'variant_id': 'var-002',
      'product_name': 'Cement 50kg OPC',
      'variant_name': 'Bag',
      'sku': 'SKU-CEM-50',
      'barcode': '8901234567002',
      'unit_name': 'BAG',
      'tracking_mode': 'none',
      'system_quantity': 50.0,
      'reserved_quantity': 0.0,
      'damaged_quantity': 0.0,
      'quarantine_quantity': 0.0,
      'available_quantity': 50.0,
    },
    {
      'product_id': 'prod-003',
      'variant_id': 'var-003',
      'product_name': 'Paint Primer 20L',
      'variant_name': 'White',
      'sku': 'SKU-PAINT-20',
      'barcode': '8901234567003',
      'unit_name': 'CAN',
      'tracking_mode': 'none',
      'system_quantity': 20.0,
      'reserved_quantity': 0.0,
      'damaged_quantity': 0.0,
      'quarantine_quantity': 0.0,
      'available_quantity': 20.0,
    },
  ];

  final sampleAuditRows = [
    {
      'id': 'cnt-001',
      'count_number': 'CNT-261111-000001',
      'tenant_id': tenantId,
      'location_id': locationId,
      'location_name': 'Main Warehouse',
      'status': 'posted',
      'reconciliation_status': 'reconciled',
      'notes': 'Quarterly audit',
      'line_count': 3,
      'total_system_quantity': 170.0,
      'total_counted_quantity': 168.0,
      'total_variance': -2.0,
      'created_at': '2026-11-11T10:00:00Z',
      'posted_at': '2026-11-11T10:30:00Z',
    },
  ];

  StockCountSession createTestSession({
    required String sessionName,
    List<StockCountItem>? items,
  }) {
    return StockCountSession(
      id: 'cnt-local-test',
      countNumber: 'CNT-LOCAL-001',
      tenantId: tenantId,
      locationId: locationId,
      locationName: 'Main Warehouse',
      sessionName: sessionName,
      requestId: 'req-test-uuid',
      items: items ?? [],
    );
  }

  setUp(() {
    // Mock StockCountingService
    final stockService = StockCountingService.instance;
    stockService.setCustomRpc((fn, {params}) async {
      if (fn == 'inventory_stock_count_snapshot_v485') {
        return sampleSnapshotRows;
      }
      if (fn == 'stock_counts_list_v485') {
        return sampleAuditRows;
      }
      if (fn == 'inventory_stock_count_post_v485') {
        return {
          'count_id': 'cnt-999',
          'count_number': 'CNT-261111-999999',
          'status': 'posted',
          'adjusted_items_count': 2,
          'idempotency_replayed': false,
        };
      }
      return null;
    });

    // Mock ClientSmartInventoryService
    final identService = ClientSmartInventoryService.instance;
    identService.setCustomRpc((fn, {params}) async {
      if (fn == 'inventory_product_lookup_v482') {
        final code = params?['p_code']?.toString();
        for (final row in sampleSnapshotRows) {
          if (row['barcode'] == code || row['sku'] == code) {
            return {
              'product_id': row['product_id'],
              'variant_id': row['variant_id'],
              'product_name': row['product_name'],
              'variant_name': row['variant_name'],
              'sku': row['sku'],
              'barcode': row['barcode'],
              'part_number': '',
              'brand_name': '',
              'category_name': 'General',
              'unit_code': row['unit_name'],
              'unit_name': row['unit_name'],
              'selling_price': 100.0,
              'cost_price': 80.0,
              'stock_quantity': row['system_quantity'],
              'identifiers': [
                {
                  'identifier_id': 'id-mock',
                  'type': 'barcode',
                  'code': row['barcode'],
                  'is_primary': true,
                  'active': true,
                }
              ],
            };
          }
        }
      }
      return null;
    });
  });

  group('StockCountingService Unit Tests', () {
    test('fetchSnapshot calls RPC and returns mapped items', () async {
      final service = StockCountingService.instance;
      final items = await service.fetchSnapshot(
        tenantId: tenantId,
        locationId: locationId,
      );

      expect(items.length, 3);
      expect(items.first.productName, 'Steel Rebar 12mm');
      expect(items.first.systemQuantity, 100.0);
      expect(items.first.countedQuantity, 0.0);
      expect(items.first.isCounted, false);
      expect(items.first.varianceType, StockCountVarianceType.notCounted);
    });

    test('postStockCount sends correct items payload and request_id', () async {
      final service = StockCountingService.instance;
      final session = createTestSession(
        sessionName: 'Midday Count',
        items: sampleSnapshotRows.map((r) => StockCountItem.fromSnapshotMap(r)).toList(),
      );

      // Count item 1 with match (100)
      session.recordScanMatch(
        ProductIdentificationMatch(
          productId: 'prod-001',
          variantId: 'var-001',
          productName: 'Steel Rebar 12mm',
          sku: 'SKU-REBAR-12',
          barcode: '8901234567001',
          unitCode: 'MTR',
          stockQuantity: 100.0,
          sellingPrice: 100.0,
          matchMethod: MatchMethod.exactBarcode,
          matchedCode: '8901234567001',
        ),
      );

      final result = await service.postStockCount(
        tenantId: session.tenantId,
        locationId: session.locationId,
        items: session.toPostPayload(),
        notes: 'Full verification',
        requestId: 'req-001',
      );

      expect(result['status'], 'posted');
      expect(result['count_number'], 'CNT-261111-999999');
    });

    test('listPastCounts parses audit records correctly', () async {
      final service = StockCountingService.instance;
      final list = await service.listPastCounts(
        tenantId: tenantId,
        locationId: locationId,
      );

      expect(list.length, 1);
      expect(list.first.countNumber, 'CNT-261111-000001');
      expect(list.first.status, 'posted');
      expect(list.first.totalVariance, -2.0);
    });
  });

  group('SmartInventoryStockCountTab Widget Tests', () {
    testWidgets('Renders empty count session setup view initially with audit history', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartInventoryStockCountTab(session: managerSession),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Physical Stock Count & Reconciliation'), findsOneWidget);
      expect(find.text('Start New Stock Count'), findsOneWidget);
      expect(find.text('Historical Stock Counts & Audits'), findsOneWidget);
      expect(find.text('CNT-261111-000001'), findsOneWidget);
    });

    testWidgets('Active counting session displays metric summary badges and products list', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final items = sampleSnapshotRows.map((r) => StockCountItem.fromSnapshotMap(r)).toList();
      final activeSession = createTestSession(
        sessionName: 'Annual Physical Count',
        items: items,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartInventoryStockCountTab(
              session: managerSession,
              initialSession: activeSession,
            ),
          ),
        ),
      );
      await tester.pump();

      // Metric tiles
      expect(find.text('Annual Physical Count'), findsOneWidget);
      expect(find.textContaining('Expected'), findsWidgets);
      expect(find.textContaining('Counted'), findsWidgets);
      expect(find.textContaining('Matched'), findsWidgets);
      expect(find.textContaining('Shortages'), findsWidgets);
      expect(find.textContaining('Excess'), findsWidgets);

      // Product rows rendered
      expect(find.text('Steel Rebar 12mm'), findsOneWidget);
      expect(find.text('Cement 50kg OPC'), findsOneWidget);
      expect(find.text('Paint Primer 20L'), findsOneWidget);
    });

    testWidgets('Quick match button sets counted quantity equal to snapshot system quantity', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final items = sampleSnapshotRows.map((r) => StockCountItem.fromSnapshotMap(r)).toList();
      final activeSession = createTestSession(
        sessionName: 'Quick Count',
        items: items,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartInventoryStockCountTab(
              session: managerSession,
              initialSession: activeSession,
            ),
          ),
        ),
      );
      await tester.pump();

      // Find "Match" TextButtons for the items
      final matchButtons = find.widgetWithText(TextButton, 'Match');
      expect(matchButtons, findsWidgets);

      // Tap the first "Match" button
      await tester.tap(matchButtons.first);
      await tester.pump();

      // Item 1 (Steel Rebar 12mm) should now have countedQuantity == 100.0, variance == 0
      final item = activeSession.items.first;
      expect(item.isCounted, true);
      expect(item.countedQuantity, 100.0);
      expect(item.variance, 0.0);
      expect(item.varianceType, StockCountVarianceType.matched);
    });

    testWidgets('Stepper increment and decrement adjusts count accurately', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final items = sampleSnapshotRows.map((r) => StockCountItem.fromSnapshotMap(r)).toList();
      final activeSession = createTestSession(
        sessionName: 'Stepper Test',
        items: items,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartInventoryStockCountTab(
              session: managerSession,
              initialSession: activeSession,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap '+' icon on the first product row
      final plusIcons = find.byIcon(Icons.add);
      expect(plusIcons, findsWidgets);

      await tester.tap(plusIcons.first);
      await tester.pump();

      expect(activeSession.items.first.countedQuantity, 1.0);
      expect(activeSession.items.first.isCounted, true);
      expect(activeSession.items.first.variance, -99.0); // 1 - 100 = -99 (shortage)
      expect(activeSession.items.first.varianceType, StockCountVarianceType.shortage);
    });

    testWidgets('Manual barcode entry increments scan count and variance', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final items = sampleSnapshotRows.map((r) => StockCountItem.fromSnapshotMap(r)).toList();
      final activeSession = createTestSession(
        sessionName: 'Scanner Test',
        items: items,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartInventoryStockCountTab(
              session: managerSession,
              initialSession: activeSession,
            ),
          ),
        ),
      );
      await tester.pump();

      // Enter barcode into manual entry text field
      final inputField = find.widgetWithText(TextField, 'Scan or enter SKU / Barcode / Name...');
      expect(inputField, findsOneWidget);

      await tester.enterText(inputField, '8901234567002');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Item 2 (Cement 50kg OPC) should have countedQuantity == 1.0
      final cementItem = activeSession.items.firstWhere((i) => i.barcode == '8901234567002');
      expect(cementItem.isCounted, true);
      expect(cementItem.countedQuantity, 1.0);
      expect(cementItem.scanCount, 1);

      // Drain SnackBar dismissal timer
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Review and post flow displays discrepancy dialog and confirms posting', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final items = sampleSnapshotRows.map((r) => StockCountItem.fromSnapshotMap(r)).toList();
      // Count first item as matched (100)
      items[0].setCounted(100.0);
      // Count second item with shortage (45 vs 50 expected)
      items[1].setCounted(45.0);
      // Count third item with excess (22 vs 20 expected)
      items[2].setCounted(22.0);

      final activeSession = createTestSession(
        sessionName: 'Full Count Reconcile',
        items: items,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartInventoryStockCountTab(
              session: managerSession,
              initialSession: activeSession,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap "Review & Post"
      final reviewButton = find.widgetWithText(FilledButton, 'Review & Post');
      expect(reviewButton, findsOneWidget);
      await tester.tap(reviewButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Review dialog appears
      expect(find.text('Review & Approve Stock Count'), findsOneWidget);
      expect(find.text('Matched'), findsWidgets);
      expect(find.text('Shortages'), findsWidgets);
      expect(find.text('Excess'), findsWidgets);

      // Check confirmation checkbox
      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pump();

      // Tap "Post Adjustments"
      final confirmButton = find.widgetWithText(FilledButton, 'Post Adjustments');
      expect(confirmButton, findsOneWidget);
      await tester.tap(confirmButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Post success dialog appears
      expect(find.text('Stock Count Posted'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();

      expect(find.text('Stock Count Posted'), findsNothing);

      // Drain any background device-profile timeout timers
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
