import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pos/models/pos_session.dart';
import 'package:mobile_pos/screens/barcode_scanner_screen.dart';
import 'package:mobile_pos/screens/mobile_pos_home_screen.dart';
import 'package:mobile_pos/services/mobile_pos_local_store.dart';
import 'package:mobile_pos/services/mobile_pos_smart_inventory_service.dart';
import 'package:mobile_pos/widgets/mobile_pos_multiple_match_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = createDatabaseFactoryFfi(noIsolate: true);
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
        url: 'https://thq-mpos-test.invalid',
        publishableKey: 'sb_publishable_fixture',
        authOptions: const FlutterAuthClientOptions(persistSession: false),
      );
    } catch (_) {}
  });

  const tenantId = 'tenant-mpos-1';
  const locationId = 'loc-mpos-main';

  const testSession = PosSession(
    tenantId: tenantId,
    businessName: 'THQ Mobile Store',
    deviceId: 'dev-mpos-1',
    deviceCode: 'MOB-01',
    deviceName: 'Mobile Register 1',
    locationId: locationId,
    locationCode: 'MAIN',
    locationName: 'Main Store',
    currencyCode: 'INR',
    username: 'Cashier Mo',
    restaurantEnabled: false,
    release: ThqMobileReleaseStatus(
      status: 'up_to_date',
      latestVersion: '8.1.0',
      mandatory: false,
      releaseNotes: '',
      downloadUrl: null,
      backend: {},
    ),
    allowedModules: {'pos'},
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
    'base_unit_code': 'BAG',
    'selling_price': 380.0,
    'cost_price': 310.0,
    'stock_quantity': 150.0,
    'offline_available_quantity': 150.0,
    'item_type': 'stock',
    'tracking_mode': 'none',
    'tax_rate': 18.0,
    'sale_units': [
      {
        'unit_id': 'unit-bag',
        'code': 'BAG',
        'name': 'Bags',
        'conversion_to_base': 1.0,
        'sale_price': 380.0,
        'quantity_step': 1.0,
        'is_default_sale': true,
      }
    ],
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
    'base_unit_code': 'PCS',
    'selling_price': 450.0,
    'stock_quantity': 80.0,
    'offline_available_quantity': 80.0,
    'item_type': 'stock',
    'tracking_mode': 'none',
    'tax_rate': 18.0,
    'sale_units': [
      {
        'unit_id': 'unit-pcs',
        'code': 'PCS',
        'name': 'Pieces',
        'conversion_to_base': 1.0,
        'sale_price': 450.0,
        'quantity_step': 1.0,
        'is_default_sale': true,
      }
    ],
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
    'base_unit_code': 'PCS',
    'selling_price': 620.0,
    'stock_quantity': 45.0,
    'offline_available_quantity': 45.0,
    'item_type': 'stock',
    'tracking_mode': 'none',
    'tax_rate': 18.0,
    'sale_units': [
      {
        'unit_id': 'unit-pcs',
        'code': 'PCS',
        'name': 'Pieces',
        'conversion_to_base': 1.0,
        'sale_price': 620.0,
        'quantity_step': 1.0,
        'is_default_sale': true,
      }
    ],
    'identifiers': [],
    'search_codes': '8909998881112 SKU-TMT-12MM',
  };

  group('MobilePosSmartInventoryService Unit Tests', () {
    setUp(() {
      final service = MobilePosSmartInventoryService.instance;
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
      final service = MobilePosSmartInventoryService.instance;

      final scan = SmartScanResult.valid(
        rawValue: '0089012345678',
        format: SmartBarcodeFormat.ean13,
        source: ScannerSource.camera,
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
      final service = MobilePosSmartInventoryService.instance;

      final result = await service.identifyCode(
        'SKU-CEM-PPC',
        session: testSession,
        source: ScannerSource.manual,
      );

      expect(result.isExact, isTrue);
      expect(result.primaryMatch!.sku, 'SKU-CEM-PPC');
    });

    test('Unknown barcode returns clean noMatch', () async {
      final service = MobilePosSmartInventoryService.instance;

      final result = await service.identifyCode(
        'UNKNOWN-CODE-999',
        session: testSession,
      );

      expect(result.isNotFound, isTrue);
      expect(result.status, ProductIdentificationStatus.noMatch);
    });

    test('Offline fallback succeeds when online RPC fails', () async {
      final service = MobilePosSmartInventoryService.instance;

      service.setCustomRpc((fn, {params}) async {
        throw RepositoryException('Network offline');
      });

      final result = await service.identifyCode(
        '0089012345678',
        session: testSession,
      );

      expect(result.isExact, isTrue);
      expect(result.primaryMatch!.productName, 'UltraTech Cement 50kg');
    });

    test('resolveProduct maps match to MobileProduct correctly', () {
      final service = MobilePosSmartInventoryService.instance;

      final match = ProductIdentificationMatch.fromRpcMap(
        cementProductMap,
        matchMethod: MatchMethod.exactBarcode,
        matchedCode: '0089012345678',
      );

      final product = service.resolveProduct(match);

      expect(product, isNotNull);
      expect(product!.name, 'UltraTech Cement 50kg');
      expect(product.sku, 'SKU-CEM-PPC');
      expect(product.sellingPrice, 380.0);
      expect(product.stockQuantity, 150.0);
      expect(product.defaultUnit.code, 'BAG');
    });
  });

  group('MobilePosMultipleMatchDialog Widget Tests', () {
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
                    builder: (_) => MobilePosMultipleMatchDialog(
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
      expect(find.text('Variant: 10mm Rod'), findsOneWidget);
      expect(find.text('Variant: 12mm Rod'), findsOneWidget);
      expect(find.text('SKU: SKU-TMT-10MM'), findsOneWidget);
      expect(find.text('SKU: SKU-TMT-12MM'), findsOneWidget);
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

  group('BarcodeScannerScreen Widget Tests', () {
    testWidgets('Renders continuous mode, manual entry action and handles manual code', (tester) async {
      String? scannedCode;

      await tester.pumpWidget(
        MaterialApp(
          home: BarcodeScannerScreen(
            session: testSession,
            onScanCode: (code, {source = ScannerSource.camera}) async {
              scannedCode = code;
              return true;
            },
            initialContinuous: true,
            initialCartCount: 3,
          ),
        ),
      );
      await tester.pump();

      // Check header info
      expect(find.text('Scan Barcode / QR'), findsOneWidget);
      expect(find.text('Continuous Mode • 3 in cart'), findsOneWidget);

      // Tap manual entry icon button
      await tester.tap(find.byTooltip('Enter code manually'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Manual Code Entry'), findsOneWidget);

      // Enter code and submit
      await tester.enterText(find.byType(TextField), '0089012345678');
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(scannedCode, '0089012345678');
      expect(find.text('Scanned: 0089012345678'), findsOneWidget);

      ThqNotify.dismissAll();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('MobilePosHomeScreen Smart Inventory Integration Widget Tests', () {
    setUp(() async {
      MobilePosSmartInventoryService.instance.setCustomRpc((fn, {params}) async {
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
      MobilePosSmartInventoryService.instance.setCustomOfflineRepo(
        LocalProductIdentificationRepository.fromStatic([
          cementProductMap,
          steelProductMap1,
          steelProductMap2,
        ]),
      );

      final testCustomer = {
        'customer_id': 'cust-walkin',
        'customer_name': 'Walk-in Customer',
        'phone': '9999999999',
        'is_walk_in': true,
      };

      final localStore = MobilePosLocalStore.instance;
      await localStore.setMeta(
        'manual_offline:$tenantId:${testSession.deviceId}',
        true,
      );
      await localStore.replaceCatalogue(
        tenantId: tenantId,
        locationId: locationId,
        products: [cementProductMap, steelProductMap1, steelProductMap2],
        customers: [testCustomer],
        serials: [],
        manifest: {},
      );
    });

    tearDown(() {
      ThqNotify.dismissAll();
    });

    testWidgets('Exact barcode scan adds product to mobile cart and consolidates on second scan', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ThqNotificationHost(child: child!),
          home: const MobilePosHomeScreen(session: testSession),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      // Verify search field exists
      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText?.contains('barcode') == true,
      );
      expect(searchField, findsOneWidget);

      // Scan 1: Submit exact barcode via search
      await tester.enterText(searchField, '0089012345678');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Product added to cart
      expect(find.text('UltraTech Cement 50kg'), findsWidgets);
      expect(find.text('Added UltraTech Cement 50kg (SKU-CEM-PPC)'), findsOneWidget);

      // Scan 2: Submit same barcode again -> consolidates quantity
      await tester.enterText(searchField, '0089012345678');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Cart total count remains 1 distinct line with incremented quantity
      expect(find.text('Added UltraTech Cement 50kg (SKU-CEM-PPC)'), findsOneWidget);

      ThqNotify.dismissAll();
      ThqNotify.dismissAll();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Ambiguous barcode opens MobilePosMultipleMatchDialog and adds chosen candidate', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ThqNotificationHost(child: child!),
          home: const MobilePosHomeScreen(session: testSession),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText?.contains('barcode') == true,
      );

      // Submit ambiguous code shared by 10mm and 12mm rods
      await tester.enterText(searchField, '8909998881112');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Dialog opens
      expect(find.text('Multiple Variants Found (2)'), findsOneWidget);
      expect(find.text('Variant: 10mm Rod'), findsOneWidget);
      expect(find.text('Variant: 12mm Rod'), findsOneWidget);

      // Tap select on the 12mm variant
      final selectButtons = find.widgetWithText(ThqPrimaryButton, 'Select');
      expect(selectButtons, findsNWidgets(2));
      await tester.tap(selectButtons.at(1));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Dialog closed, 12mm variant added
      expect(find.text('Multiple Variants Found (2)'), findsNothing);
      expect(find.text('Added Tata Tiscon TMT Bar (SKU-TMT-12MM)'), findsOneWidget);

      ThqNotify.dismissAll();
      ThqNotify.dismissAll();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Unknown barcode displays not found message without modifying cart', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ThqNotificationHost(child: child!),
          home: const MobilePosHomeScreen(session: testSession),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText?.contains('barcode') == true,
      );

      await tester.enterText(searchField, 'UNKNOWN-MPOS-999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // Verify not found snackbar
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('UNKNOWN-MPOS-999') == true) &&
              (w.data?.contains('not found') == true),
        ),
        findsOneWidget,
      );

      ThqNotify.dismissAll();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
