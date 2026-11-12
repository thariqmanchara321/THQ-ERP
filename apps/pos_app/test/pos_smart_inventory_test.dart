import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/models/client_session.dart';
import 'package:pos_app/models/customer.dart';
import 'package:pos_app/models/inventory_product.dart';
import 'package:pos_app/screens/pos_screen.dart';
import 'package:pos_app/services/offline_pos_service.dart';
import 'package:pos_app/services/pos_smart_inventory_service.dart';
import 'package:pos_app/widgets/pos_multiple_match_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
    FlutterSecureStorage.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://thq-pos-test.invalid',
        publishableKey: 'sb_publishable_fixture',
        authOptions: const FlutterAuthClientOptions(persistSession: false),
      );
    } catch (_) {}
  });
  const tenantId = 'tenant-pos-1';
  const locationId = 'loc-main';

  const testBusiness = ClientBusiness(
    id: tenantId,
    membershipId: 'mem-pos',
    name: 'THQ POS Mart',
    slug: 'thq-pos-mart',
    businessType: 'retail',
    status: 'active',
  );

  const testDevice = ClientDeviceContext(
    deviceId: 'dev-pos-1',
    deviceCode: 'REG-01',
    deviceName: 'Register 1',
    locationId: locationId,
    locationName: 'Main Store',
    locationCode: 'MAIN',
    allowedModules: {'pos'},
  );

  const testSession = ClientSession(
    business: testBusiness,
    device: testDevice,
    userId: 'user-cashier',
    username: 'John Cashier',
    modules: [],
    roles: {'staff'},
    permissions: {'pos.use'},
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
  );

  const cementProductMap = {
    'product_id': 'prod-cement-50',
    'variant_id': 'var-cement-ppc',
    'product_name': 'UltraTech Cement 50kg',
    'variant_name': 'PPC Bag',
    'sku': 'SKU-CEM-PPC',
    'barcode': '0089012345678', // with leading zero
    'part_number': 'UT-PPC-50',
    'brand_name': 'UltraTech',
    'category_name': 'Cement',
    'unit_name': 'Bags',
    'unit_code': 'BAG',
    'selling_price': 380.0,
    'cost_price': 310.0,
    'stock_quantity': 150.0,
    'identifiers': [
      {
        'identifier_id': 'id-cem-1',
        'type': 'barcode',
        'code': '0089012345678',
        'is_primary': true,
        'active': true,
      },
    ],
    'search_codes': '0089012345678 SKU-CEM-PPC UT-PPC-50',
  };

  const steelProductMap1 = {
    'product_id': 'prod-steel-bar',
    'variant_id': 'var-steel-10mm',
    'product_name': 'Tata Tiscon TMT Bar',
    'variant_name': '10mm Rod',
    'sku': 'SKU-TMT-10MM',
    'barcode': '8909998881112',
    'unit_name': 'Pieces',
    'unit_code': 'PCS',
    'selling_price': 450.0,
    'stock_quantity': 80.0,
    'identifiers': [],
    'search_codes': '8909998881112 SKU-TMT-10MM',
  };

  const steelProductMap2 = {
    'product_id': 'prod-steel-bar',
    'variant_id': 'var-steel-12mm',
    'product_name': 'Tata Tiscon TMT Bar',
    'variant_name': '12mm Rod',
    'sku': 'SKU-TMT-12MM',
    'barcode': '8909998881112', // same master barcode -> ambiguous
    'unit_name': 'Pieces',
    'unit_code': 'PCS',
    'selling_price': 620.0,
    'stock_quantity': 45.0,
    'identifiers': [],
    'search_codes': '8909998881112 SKU-TMT-12MM',
  };

  group('PosSmartInventoryService Unit Tests', () {
    setUp(() {
      final service = PosSmartInventoryService.instance;
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          final code = params?['p_code']?.toString();
          if (code == '0089012345678' || code == 'SKU-CEM-PPC') {
            return cementProductMap;
          }
          if (code == '8909998881112') {
            return [steelProductMap1, steelProductMap2];
          }
        }
        return null;
      });
      service.setCustomOfflineRepo(
        LocalProductIdentificationRepository.fromStatic([cementProductMap]),
      );
    });

    test('Exact barcode scan identifies product and preserves leading zeros', () async {
      final service = PosSmartInventoryService.instance;

      final scan = SmartScanResult.valid(
        rawValue: '0089012345678',
        format: SmartBarcodeFormat.ean13,
        source: ScannerSource.usb,
      );

      final result = await service.identifyScan(scan, session: testSession);

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.isExact, isTrue);
      expect(result.primaryMatch!.productName, 'UltraTech Cement 50kg');
      expect(result.primaryMatch!.variantId, 'var-cement-ppc');
      expect(result.primaryMatch!.barcode, '0089012345678');
      expect(result.primaryMatch!.sellingPrice, 380.0);
    });

    test('Exact SKU manual entry resolves correctly', () async {
      final service = PosSmartInventoryService.instance;

      final result = await service.identifyCode(
        'SKU-CEM-PPC',
        session: testSession,
        source: ScannerSource.manual,
      );

      expect(result.isExact, isTrue);
      expect(result.primaryMatch!.sku, 'SKU-CEM-PPC');
    });

    test('Unknown barcode returns clean noMatch', () async {
      final service = PosSmartInventoryService.instance;

      final result = await service.identifyCode('UNKNOWN-CODE-999', session: testSession);

      expect(result.isNotFound, isTrue);
      expect(result.status, ProductIdentificationStatus.noMatch);
    });

    test('Offline fallback succeeds when online RPC fails', () async {
      final service = PosSmartInventoryService.instance;

      // Simulate network / RPC failure
      service.setCustomRpc((fn, {params}) async {
        throw RepositoryException('Network connection refused');
      });

      final result = await service.identifyCode('0089012345678', session: testSession);

      expect(result.isExact, isTrue);
      expect(result.primaryMatch!.productName, 'UltraTech Cement 50kg');
    });

    test('resolveProduct maps match to InventoryProduct correctly', () {
      final service = PosSmartInventoryService.instance;

      final match = ProductIdentificationMatch.fromRpcMap(
        cementProductMap,
        matchMethod: MatchMethod.exactBarcode,
        matchedCode: '0089012345678',
      );

      final product = service.resolveProduct(match);

      expect(product, isNotNull);
      expect(product!.productName, 'UltraTech Cement 50kg');
      expect(product.sku, 'SKU-CEM-PPC');
      expect(product.sellingPrice, 380.0);
      expect(product.stockQuantity, 150.0);
    });
  });

  group('PosMultipleMatchDialog Widget Tests', () {
    testWidgets('Renders all matching candidates and returns selected match', (tester) async {
      final matches = [
        ProductIdentificationMatch.fromRpcMap(
          steelProductMap1,
          matchMethod: MatchMethod.exactBarcode,
          matchedCode: '8909998881112',
        ),
        ProductIdentificationMatch.fromRpcMap(
          steelProductMap2,
          matchMethod: MatchMethod.exactBarcode,
          matchedCode: '8909998881112',
        ),
      ];

      ProductIdentificationMatch? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selected = await showDialog<ProductIdentificationMatch>(
                    context: context,
                    builder: (_) => PosMultipleMatchDialog(
                      rawCode: '8909998881112',
                      matches: matches,
                      currencyCode: 'INR',
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Multiple Variants Found (2)'), findsOneWidget);
      expect(find.text('Variant: 10mm Rod • SKU: SKU-TMT-10MM • Stock: 80.0 PCS'), findsOneWidget);
      expect(find.text('Variant: 12mm Rod • SKU: SKU-TMT-12MM • Stock: 45.0 PCS'), findsOneWidget);
      expect(find.text('₹450.00'), findsOneWidget);
      expect(find.text('₹620.00'), findsOneWidget);

      // Tap 'Select' on the second item (12mm)
      final selectButtons = find.widgetWithText(ThqPrimaryButton, 'Select');
      expect(selectButtons, findsNWidgets(2));
      await tester.tap(selectButtons.at(1));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.sku, 'SKU-TMT-12MM');
      expect(selected!.sellingPrice, 620.0);
    });
  });

  group('PosScreen Smart Inventory Integration Widget Tests', () {
    setUp(() async {
      PosSmartInventoryService.instance.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          final code = params?['p_code']?.toString();
          if (code == '0089012345678' || code == 'SKU-CEM-PPC') {
            return cementProductMap;
          }
          if (code == '8909998881112') {
            return [steelProductMap1, steelProductMap2];
          }
        }
        return null;
      });
      PosSmartInventoryService.instance.setCustomOfflineRepo(
        LocalProductIdentificationRepository.fromStatic([
          cementProductMap,
          steelProductMap1,
          steelProductMap2,
        ]),
      );

      final cementProduct = InventoryProduct.fromMap(cementProductMap);
      final steelProduct1 = InventoryProduct.fromMap(steelProductMap1);
      final steelProduct2 = InventoryProduct.fromMap(steelProductMap2);
      final testCustomer = Customer.fromMap({
        'customer_id': 'cust-walkin',
        'customer_name': 'Walk-in Customer',
        'is_walk_in': true,
        'status': 'active',
      });
      final offline = OfflinePosService.instance;
      await offline.initialize();
      await offline.replaceCatalogue(
        tenantId: tenantId,
        locationId: locationId,
        products: [cementProduct, steelProduct1, steelProduct2],
        customers: [testCustomer],
        serials: [],
        manifest: {},
      );
    });

    testWidgets('PosScreen renders camera scanner toggle button and search bar scanner icon', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PosScreen(session: testSession),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Camera scanner toggle in header
      expect(find.byTooltip('Open camera scanner'), findsOneWidget);
      // Barcode focus / search icon
      expect(find.byTooltip('Focus barcode / product search'), findsOneWidget);

      // Tapping camera toggle opens camera view
      await tester.tap(find.byTooltip('Open camera scanner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byTooltip('Close camera scanner'), findsOneWidget);
      expect(find.byType(ThqSmartScannerView), findsOneWidget);
    });

    testWidgets('Exact barcode scan adds product to cart and updates feedback banner', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PosScreen(session: testSession),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Locate search / barcode textfield
      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText?.contains('barcode') == true,
      );
      expect(searchField, findsOneWidget);

      // Submit exact barcode
      await tester.enterText(searchField, '0089012345678');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify product added to cart and scan feedback shown
      expect(find.text('Added UltraTech Cement 50kg (SKU-CEM-PPC)'), findsOneWidget);
      expect(find.text('UltraTech Cement 50kg'), findsWidgets);
    });

    testWidgets('Repeated scan of exact barcode consolidates quantity to 2', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PosScreen(session: testSession),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText?.contains('barcode') == true,
      );

      // Scan 1
      await tester.enterText(searchField, '0089012345678');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Scan 2 (same barcode)
      await tester.enterText(searchField, '0089012345678');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Added UltraTech Cement 50kg (SKU-CEM-PPC)'), findsOneWidget);
      // Cart should display quantity 2
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('Ambiguous barcode scan opens PosMultipleMatchDialog and adds chosen variant', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PosScreen(session: testSession),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText?.contains('barcode') == true,
      );

      // Enter ambiguous barcode shared by 10mm and 12mm rods
      await tester.enterText(searchField, '8909998881112');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog should be displayed
      expect(find.text('Multiple Variants Found (2)'), findsOneWidget);
      expect(find.text('Variant: 10mm Rod • SKU: SKU-TMT-10MM • Stock: 80.0 PCS'), findsOneWidget);
      expect(find.text('Variant: 12mm Rod • SKU: SKU-TMT-12MM • Stock: 45.0 PCS'), findsOneWidget);

      // Select the 12mm variant (index 1)
      final selectButtons = find.widgetWithText(ThqPrimaryButton, 'Select');
      expect(selectButtons, findsNWidgets(2));
      await tester.tap(selectButtons.at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify dialog is closed and item added to cart
      expect(find.text('Multiple Variants Found (2)'), findsNothing);
      expect(find.text('Added Tata Tiscon TMT Bar (SKU-TMT-12MM)'), findsOneWidget);
    });

    testWidgets('Unknown barcode displays not found feedback without affecting cart', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PosScreen(session: testSession),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText?.contains('barcode') == true,
      );

      // Submit unknown barcode
      await tester.enterText(searchField, 'UNKNOWN-BARCODE-999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify feedback banner indicates not found (either online noMatch or offline cache miss)
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('UNKNOWN-BARCODE-999') == true) &&
              (w.data?.contains('not found') == true),
        ),
        findsOneWidget,
      );
      // Cart remains empty
      expect(find.text('Scan, search or tap a product'), findsOneWidget);
      expect(find.text('UltraTech Cement 50kg'), findsNothing);
    });

    testWidgets('Wireless Phone-to-PC scan adds product to cart and acknowledges phone', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockTransport = MockWirelessScannerTransport();
      final coordinator = WirelessScannerCoordinator(transport: mockTransport);
      addTearDown(() {
        coordinator.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosScreen(
              session: testSession,
              wirelessCoordinator: coordinator,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 1. Verify phone scanner button exists in header
      expect(find.byIcon(Icons.phone_android_rounded), findsOneWidget);

      // 2. Tap to open pairing dialog
      await tester.tap(find.byIcon(Icons.phone_android_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Phone-to-PC Wireless Scanner'), findsOneWidget);
      expect(find.byType(ThqPairingQrView), findsOneWidget);

      // Close pairing dialog
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // 3. Connect mock phone
      final payload = coordinator.currentPayload!;
      await mockTransport.joinSession(
        payload: payload,
        phoneDeviceId: 'phone-galaxy-s22',
        phoneDeviceName: 'Galaxy S22 (Store Assistant)',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 4. Send scan for cement barcode from paired phone
      final scan = WirelessScanMessage.create(
        sessionId: payload.sessionId,
        tenantId: tenantId,
        senderDeviceId: 'phone-galaxy-s22',
        senderDeviceName: 'Galaxy S22 (Store Assistant)',
        rawCode: '0089012345678',
        format: SmartBarcodeFormat.ean13,
        handshakeSecret: payload.handshakeSecret,
      );

      mockTransport.simulateIncomingScan(scan);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // 5. Product should be added to active cart!
      expect(find.text('UltraTech Cement 50kg'), findsWidgets);

      coordinator.dispose();
    });
  });
}
