import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/smart_inventory/smart_inventory_workspace_screen.dart';
import 'package:client_app/services/client_smart_inventory_service.dart';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientSmartInventoryService Tests', () {
    const tenantId = 'tenant-client-1';

    const testBusiness = ClientBusiness(
      id: tenantId,
      membershipId: 'mem-1',
      name: 'Smart Hardware Ltd',
      slug: 'smart-hardware',
      businessType: 'retail',
      status: 'active',
    );

    const authorizedSession = ClientSession(
      business: testBusiness,
      userId: 'user-owner',
      username: 'Alice Owner',
      modules: [
        ClientModule(
          key: 'inventory',
          name: 'Inventory',
          description: null,
          category: 'Inventory',
          sortOrder: 10,
        ),
      ],
      roles: {'owner'},
      permissions: {'inventory.view', 'inventory.manage'},
      currencyCode: 'INR',
      timezone: 'Asia/Kolkata',
      locale: 'en_IN',
    );

    const testProductMap = {
      'product_id': 'prod-cement-50',
      'variant_id': 'var-cement-50',
      'product_name': 'UltraTech Cement 50kg',
      'variant_name': 'PPC Bag',
      'sku': 'SKU-CEM-PPC',
      'barcode': '8901234567890',
      'part_number': 'UT-PPC-50',
      'brand_name': 'UltraTech',
      'category_name': 'Cement',
      'unit_code': 'BAG',
      'unit_name': 'Bags',
      'selling_price': 380.0,
      'cost_price': 310.0,
      'stock_quantity': 450.0,
      'identifiers': [
        {
          'identifier_id': 'id-1',
          'type': 'barcode',
          'code': '8901234567890',
          'is_primary': true,
          'active': true,
        },
      ],
      'search_codes': '8901234567890 SKU-CEM-PPC UT-PPC-50',
    };

    setUp(() {
      final service = ClientSmartInventoryService.instance;
      service.cancelBulkSession();
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          final code = params?['p_code']?.toString();
          if (code == '8901234567890' || code == 'SKU-CEM-PPC') {
            return testProductMap;
          }
          return null;
        }
        if (fn == 'inventory_list_products_v483') {
          return [testProductMap];
        }
        return null;
      });
    });

    test('identifyScan resolves barcode to ProductIdentificationMatch via RPC', () async {
      final service = ClientSmartInventoryService.instance;

      final scan = SmartScanResult.valid(
        rawValue: '8901234567890',
        format: SmartBarcodeFormat.ean13,
        source: ScannerSource.usb,
      );

      final result = await service.identifyScan(scan, session: authorizedSession);

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.productName, 'UltraTech Cement 50kg');
      expect(result.primaryMatch!.variantId, 'var-cement-50');
      expect(result.primaryMatch!.sellingPrice, 380.0);
      expect(service.recentActivity.isNotEmpty, isTrue);
      expect(service.recentActivity.first.rawCode, '8901234567890');
    });

    test('identifyCode returns noMatch for unknown barcode', () async {
      final service = ClientSmartInventoryService.instance;

      final result = await service.identifyCode('UNKNOWN-999', session: authorizedSession);

      expect(result.status, ProductIdentificationStatus.noMatch);
      expect(result.isNotFound, isTrue);
      expect(service.recentActivity.first.status, ProductIdentificationStatus.noMatch);
    });

    test('searchCatalog finds items by text query in search_codes', () async {
      final service = ClientSmartInventoryService.instance;

      final matches = await service.searchCatalog('UltraTech', session: authorizedSession);

      expect(matches, isNotEmpty);
      expect(matches.first.productName, 'UltraTech Cement 50kg');
    });

    test('Bulk scanning session accumulates repeated scans and updates quantities', () {
      final service = ClientSmartInventoryService.instance;

      final session = service.startBulkSession(
        session: authorizedSession,
        title: 'Morning Truck Unload',
      );

      expect(session.items, isEmpty);
      expect(service.activeBulkSession, isNotNull);

      final match = ProductIdentificationMatch.fromRpcMap(
        testProductMap,
        matchMethod: MatchMethod.exactBarcode,
        matchedCode: '8901234567890',
      );

      session.addOrIncrementMatch(match);
      expect(session.totalDistinctProducts, 1);
      expect(session.totalQuantity, 1.0);

      // Repeated scan of same item increments quantity
      session.addOrIncrementMatch(match);
      expect(session.totalDistinctProducts, 1);
      expect(session.totalQuantity, 2.0);

      // Unresolved scan added
      session.addUnresolved('999888777', ScannerSource.camera, 'Not in DB');
      expect(session.totalUnresolved, 1);

      // Finish session
      final finished = service.finishBulkSession();
      expect(finished, isNotNull);
      expect(finished!.isCompleted, isTrue);
      expect(service.activeBulkSession, isNull);
      expect(service.completedSessions.length, 1);
      expect(service.completedSessions.first.totalQuantity, 2.0);
    });
  });

  group('SmartInventoryWorkspaceScreen Widget Tests', () {
    const testBusiness = ClientBusiness(
      id: 'tenant-test-w',
      membershipId: 'mem-w',
      name: 'Widget Test Store',
      slug: 'widget-store',
      businessType: 'retail',
      status: 'active',
    );

    const standardSession = ClientSession(
      business: testBusiness,
      userId: 'user-clerk',
      username: 'Bob Clerk',
      modules: [
        ClientModule(
          key: 'inventory',
          name: 'Inventory',
          description: null,
          category: 'Inventory',
          sortOrder: 10,
        ),
      ],
      roles: {'staff'},
      permissions: {'inventory.view'},
      currencyCode: 'INR',
      timezone: 'Asia/Kolkata',
      locale: 'en_IN',
    );

    setUp(() {
      ClientSmartInventoryService.instance.setCustomRpc((fn, {params}) async => null);
    });

    testWidgets('SmartInventoryWorkspaceScreen renders header and all 6 tabs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartInventoryWorkspaceScreen(session: standardSession),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Smart Inventory'), findsWidgets);
      expect(find.widgetWithText(Tab, 'Overview'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Scan Center'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Product Lookup'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Bulk Scanning'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Scan History'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Product Import'), findsOneWidget);

      // Overview quick actions are present
      expect(find.text('Open Scan Center'), findsOneWidget);
      expect(find.text('Search Catalog'), findsOneWidget);
      expect(find.text('Start Bulk Scan'), findsOneWidget);
      expect(find.text('Import Products'), findsOneWidget);
    });

    testWidgets('Switching to Scan Center displays hardware wedge status and manual input', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartInventoryWorkspaceScreen(
              session: standardSession,
              initialTab: 1, // Scan Center
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('USB / Bluetooth Wedge Active'), findsOneWidget);
      expect(find.text('Manual Barcode / Identifier Entry'), findsOneWidget);
      expect(find.text('Identify'), findsOneWidget);
      expect(find.text('Awaiting Scan Input'), findsOneWidget);
    });
  });
}

