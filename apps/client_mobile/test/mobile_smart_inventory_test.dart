import 'dart:io';

import 'package:client_mobile/models/mobile_session.dart';
import 'package:client_mobile/screens/smart_inventory/mobile_smart_inventory_workspace_screen.dart';
import 'package:client_mobile/services/mobile_smart_inventory_service.dart';
import 'package:client_mobile/widgets/mobile_smart_inventory_dialogs.dart';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MobileSession makeSession({
  Set<String> roles = const {'cashier'},
  Set<String> permissions = const {},
}) {
  return MobileSession(
    tenantId: 'tenant-test-01',
    businessName: 'Tenzo Retail & Quarry',
    deviceId: 'dev-mob-101',
    deviceCode: 'MOB-101',
    deviceName: 'Warehouse Mobile Terminal',
    locationId: 'loc-main-yard',
    locationCode: 'YARD-01',
    locationName: 'Main Yard & Warehouse',
    currencyCode: 'INR',
    username: 'rahul_stock',
    canViewAllLocations: true,
    canApprove: true,
    canReceiveCustomerPayment: true,
    canViewNotifications: true,
    canViewAudit: true,
    canViewTraceability: true,
    canViewWarranty: true,
    locations: const [
      MobileLocation(
        id: 'loc-main-yard',
        code: 'YARD-01',
        name: 'Main Yard & Warehouse',
        accessLevel: 'full',
      ),
      MobileLocation(
        id: 'loc-depot-north',
        code: 'DEP-02',
        name: 'North Stock Depot',
        accessLevel: 'full',
      ),
    ],
    release: ThqMobileReleaseStatus.unknown(),
    roles: roles,
    permissions: permissions,
  );
}

Map<String, dynamic> sampleProductRpcRow({
  String productId = 'prod-100',
  String variantId = 'var-100',
  String productName = 'UltraTech Cement 50kg',
  String variantName = 'Standard Grade 53',
  String sku = 'SKU-CEM-50',
  String? barcode = '8901030382910',
  double sellingPrice = 380.0,
  double costPrice = 310.0,
  double stockQty = 120.0,
  String unitCode = 'BAG',
}) {
  return {
    'product_id': productId,
    'variant_id': variantId,
    'product_name': productName,
    'variant_name': variantName,
    'sku': sku,
    'barcode': barcode,
    'selling_price': sellingPrice,
    'cost_price': costPrice,
    'stock_quantity': stockQty,
    'unit_code': unitCode,
    'is_active': true,
  };
}

void main() {
  group('MobileSmartInventoryService — Unit Tests', () {
    late MobileSmartInventoryService service;
    late MobileSession session;

    setUp(() {
      service = MobileSmartInventoryService.instance;
      session = makeSession();
      service.clearActivity();
      service.cancelBulkSession();
      service.clearCompletedSessions();
    });

    test('Exact barcode lookup resolves primary match and logs activity', () async {
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          return {
            'status': 'exact_match',
            'match_method': 'barcode_exact',
            'product': sampleProductRpcRow(),
          };
        }
        return null;
      });

      final result = await service.identifyCode(
        '8901030382910',
        session: session,
        source: ScannerSource.camera,
      );

      expect(result.isExact, isTrue);
      expect(result.primaryMatch, isNotNull);
      expect(result.primaryMatch!.productName, 'UltraTech Cement 50kg');
      expect(result.primaryMatch!.sku, 'SKU-CEM-50');
      expect(result.primaryMatch!.sellingPrice, 380.0);

      // Verify activity feed logging
      expect(service.recentActivity.length, 1);
      final log = service.recentActivity.first;
      expect(log.rawCode, '8901030382910');
      expect(log.isSuccess, isTrue);
      expect(log.productName, 'UltraTech Cement 50kg');
    });

    test('Ambiguous scan returns multiple candidates', () async {
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          return {
            'status': 'multiple_matches',
            'match_method': 'barcode_exact',
            'matches': [
              sampleProductRpcRow(
                variantId: 'var-101',
                variantName: '50kg Standard Red',
                sellingPrice: 380.0,
              ),
              sampleProductRpcRow(
                variantId: 'var-102',
                variantName: '50kg Weather Plus Blue',
                sellingPrice: 420.0,
              ),
            ],
          };
        }
        return null;
      });

      final result = await service.identifyCode('AMBIG-BC-01', session: session);

      expect(result.isAmbiguous, isTrue);
      expect(result.matches.length, 2);
      expect(result.matches[0].variantName, '50kg Standard Red');
      expect(result.matches[1].variantName, '50kg Weather Plus Blue');
    });

    test('Unregistered code returns not found cleanly without throwing', () async {
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          return {
            'status': 'not_found',
            'matches': [],
          };
        }
        return null;
      });

      final result = await service.identifyCode('UNKNOWN-999', session: session);

      expect(result.isNotFound, isTrue);
      expect(result.primaryMatch, isNull);
      expect(service.recentActivity.first.isSuccess, isFalse);
    });

    test('Network error returns offline unavailable result with descriptive message', () async {
      service.setCustomRpc((fn, {params}) async {
        throw const SocketException('Network unreachable');
      });

      final result = await service.identifyCode('8901030382910', session: session);

      expect(result.hasError, isTrue);
      expect(result.errorMessage, contains('Network unreachable'));
    });

    test('Catalog search queries multi-field product list', () async {
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          return {'status': 'not_found', 'matches': []};
        }
        if (fn == 'inventory_list_products_v483') {
          return [
            sampleProductRpcRow(productName: 'TMT Steel 12mm', sku: 'SKU-TMT-12'),
            sampleProductRpcRow(productName: 'TMT Steel 16mm', sku: 'SKU-TMT-16'),
            sampleProductRpcRow(productName: 'Tenzo Sand M-Sand', sku: 'SKU-SAND-01'),
          ];
        }
        return null;
      });

      final results = await service.searchCatalog('Steel', session: session);

      expect(results.length, 2);
      expect(results.every((r) => r.productName.contains('Steel')), isTrue);
    });

    test('Bulk session lifecycle: start, consolidate, unresolved retry, finish without stock mutation', () {
      final bulk = service.startBulkSession(
        session: session,
        title: 'Morning Truck Audit',
      );

      expect(service.activeBulkSession, isNotNull);
      expect(bulk.title, 'Morning Truck Audit');
      expect(bulk.operatorName, 'rahul_stock');
      expect(bulk.totalDistinctProducts, 0);

      // Add match 1
      final match1 = ProductIdentificationMatch.fromRpcMap(
        sampleProductRpcRow(),
        matchMethod: MatchMethod.exactBarcode,
        matchedCode: '8901030382910',
      );
      bulk.addOrIncrementMatch(match1, 1.0);
      expect(bulk.totalDistinctProducts, 1);
      expect(bulk.totalQuantity, 1.0);

      // Consolidate quantity on re-scan
      bulk.addOrIncrementMatch(match1, 2.0);
      expect(bulk.totalDistinctProducts, 1);
      expect(bulk.totalQuantity, 3.0);
      expect(bulk.items.first.scanCount, 2);

      // Add unresolved scan
      bulk.addUnresolved('DAMAGED-BARCODE', ScannerSource.camera, 'Label torn');
      expect(bulk.totalUnresolved, 1);

      // Finish session
      final finished = service.finishBulkSession();
      expect(finished, isNotNull);
      expect(finished!.isCompleted, isTrue);
      expect(service.activeBulkSession, isNull);
      expect(service.completedSessions.length, 1);
      expect(service.completedSessions.first.title, 'Morning Truck Audit');
    });
  });

  group('MobileSmartInventoryWorkspaceScreen — Widget Tests', () {
    late MobileSmartInventoryService service;
    late MobileSession nonManagerSession;
    late MobileSession managerSession;

    setUp(() {
      service = MobileSmartInventoryService.instance;
      nonManagerSession = makeSession(roles: {'cashier'}, permissions: {});
      managerSession = makeSession(roles: {'manager'}, permissions: {'inventory.manage'});
      service.clearActivity();
      service.cancelBulkSession();
      service.clearCompletedSessions();

      service.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          final id = params?['p_code']?.toString() ??
              params?['p_identifier']?.toString() ??
              '';
          if (id == '8901030382910') {
            return {
              'status': 'exact_match',
              'match_method': 'barcode_exact',
              'product': sampleProductRpcRow(),
            };
          }
          if (id == 'AMBIGUOUS-BARCODE') {
            return {
              'status': 'multiple_matches',
              'match_method': 'barcode_exact',
              'matches': [
                sampleProductRpcRow(
                  variantId: 'var-101',
                  variantName: 'Standard 53 Red',
                ),
                sampleProductRpcRow(
                  variantId: 'var-102',
                  variantName: 'Weather Plus Blue',
                ),
              ],
            };
          }
          return {'status': 'not_found', 'matches': []};
        }
        if (fn == 'inventory_list_products_v483') {
          return [
            sampleProductRpcRow(productName: 'UltraTech Cement 50kg', sku: 'SKU-CEM-50'),
            sampleProductRpcRow(productName: 'Tenzo M-Sand', sku: 'SKU-SAND-01'),
          ];
        }
        return null;
      });
    });

    testWidgets('Renders Smart Inventory workspace with 5 navigation tabs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MobileSmartInventoryWorkspaceScreen(
            session: nonManagerSession,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Smart Inventory'), findsOneWidget);
      expect(find.text('Main Yard & Warehouse'), findsWidgets);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Lookup'), findsOneWidget);
      expect(find.text('Bulk'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);

      // Switches between tabs without error
      await tester.tap(find.widgetWithText(Tab, 'Scan'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Continuous scan'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Lookup'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Search product name, SKU, barcode, brand...'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Bulk'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('No Active Bulk Session'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'History'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('No Completed Sessions'), findsOneWidget);
    });

    testWidgets('Manual Code Entry Dialog identifies product and renders feedback card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MobileSmartInventoryWorkspaceScreen(
            session: nonManagerSession,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap manual entry button in AppBar
      await tester.tap(find.byIcon(Icons.keyboard_outlined).first);
      await tester.pumpAndSettle();

      expect(find.text('Enter Product Code'), findsOneWidget);

      // Enter known barcode
      await tester.enterText(find.byType(TextFormField), '8901030382910');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lookup'));
      await tester.pumpAndSettle();

      // Switch to Scan tab to verify feedback card
      await tester.tap(find.widgetWithText(Tab, 'Scan'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Identified Product'), findsOneWidget);
      expect(find.text('UltraTech Cement 50kg'), findsOneWidget);
      expect(find.text('SKU: SKU-CEM-50'), findsOneWidget);

      // Drain ThqNotify auto-dismiss timer
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Disambiguation Dialog renders when ambiguous code is entered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MobileSmartInventoryWorkspaceScreen(
            session: nonManagerSession,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open manual entry and type ambiguous code
      await tester.tap(find.byIcon(Icons.keyboard_outlined).first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'AMBIGUOUS-BARCODE');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lookup'));
      await tester.pumpAndSettle();

      // Disambiguation dialog should pop up
      expect(find.text('Multiple Variants Found (2)'), findsOneWidget);
      expect(find.text('Standard 53 Red'), findsOneWidget);
      expect(find.text('Weather Plus Blue'), findsOneWidget);

      // Tap one candidate
      await tester.tap(find.text('Weather Plus Blue'));
      await tester.pumpAndSettle();

      // Dialog dismissed
      expect(find.text('Multiple Variants Found (2)'), findsNothing);

      // Drain ThqNotify auto-dismiss timer
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Cost price is restricted for non-manager and visible for manager', (tester) async {
      final match = ProductIdentificationMatch.fromRpcMap(
        sampleProductRpcRow(costPrice: 310.0),
        matchMethod: MatchMethod.exactBarcode,
        matchedCode: '8901030382910',
      );

      // 1. Non-manager session
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileProductDetailModal(
              match: match,
              session: nonManagerSession,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Restricted (Requires inventory.manage permission)'), findsOneWidget);
      expect(find.text('INR 310.00'), findsNothing);

      // 2. Manager session
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileProductDetailModal(
              match: match,
              session: managerSession,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('INR 310.00'), findsOneWidget);
      expect(find.text('Restricted (Requires inventory.manage permission)'), findsNothing);
    });

    testWidgets('Bulk session flow: start, add item, finish to history', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MobileSmartInventoryWorkspaceScreen(
            session: nonManagerSession,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to Bulk tab
      await tester.tap(find.widgetWithText(Tab, 'Bulk'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Start bulk session
      await tester.tap(find.text('Start Bulk Session'));
      await tester.pumpAndSettle();

      expect(find.text('Staging only. Bulk scanning verifies codes without altering live stock.'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);

      // Add item via manual lookup while bulk session is active
      await tester.tap(find.byIcon(Icons.keyboard_outlined).first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '8901030382910');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lookup'));
      await tester.pumpAndSettle();

      // Verify item appears in bulk staging list
      await tester.tap(find.widgetWithText(Tab, 'Bulk'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Staged Products (1)'), findsOneWidget);
      expect(find.text('UltraTech Cement 50kg'), findsOneWidget);

      // Finish session
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      // Should automatically navigate to History tab
      expect(find.text('No Completed Sessions'), findsNothing);
      expect(find.textContaining('1 products • 1.0 units'), findsWidgets);

      // Drain ThqNotify auto-dismiss timer
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
