import 'package:client_mobile/models/mobile_session.dart';
import 'package:client_mobile/screens/workspace/mobile_modules_catalog_page.dart';
import 'package:client_mobile/services/mobile_client_service.dart';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockMobileClientService extends MobileClientService {
  @override
  Future<List<ThqNavigationNode>> loadNavigation(
    String tenantId, [
    String appScope = 'client_mobile',
  ]) async {
    return [
      const ThqNavigationNode(
        id: 'node_sales',
        nodeType: 'module',
        nodeKey: 'sales',
        label: 'Sales Register',
        iconKey: 'receipt_long',
        sortOrder: 10,
        metadata: {'category': 'Operations'},
      ),
      const ThqNavigationNode(
        id: 'node_purchases',
        nodeType: 'module',
        nodeKey: 'purchases',
        label: 'Purchases & Inward',
        iconKey: 'shopping_cart',
        sortOrder: 20,
        metadata: {'category': 'Operations'},
      ),
      const ThqNavigationNode(
        id: 'node_yard',
        nodeType: 'module',
        nodeKey: 'material_yard',
        label: 'Material Yard / Quarry',
        iconKey: 'local_shipping',
        sortOrder: 30,
        metadata: {'category': 'Logistics & Quarry'},
      ),
      const ThqNavigationNode(
        id: 'node_staff',
        nodeType: 'module',
        nodeKey: 'staff',
        label: 'Staff & Attendance',
        iconKey: 'badge',
        sortOrder: 40,
        metadata: {'category': 'Workforce & HR'},
      ),
      const ThqNavigationNode(
        id: 'node_accounting',
        nodeType: 'module',
        nodeKey: 'accounting',
        label: 'Financial Accounting',
        iconKey: 'account_balance',
        sortOrder: 50,
        metadata: {'category': 'Accounting & Finance'},
      ),
      const ThqNavigationNode(
        id: 'node_reports',
        nodeType: 'module',
        nodeKey: 'reports',
        label: 'Reports Center',
        iconKey: 'analytics',
        sortOrder: 60,
        metadata: {'category': 'Reports & Settings'},
      ),
    ];
  }

  @override
  Future<ThqUserUiPreferences> loadUserPreferences([
    String appScope = 'client_mobile',
  ]) async {
    return ThqUserUiPreferences.defaults(appScope);
  }
}

void main() {
  MobileSession buildSession({
    String currencyCode = 'INR',
    bool canViewAllLocations = true,
  }) {
    return MobileSession(
      tenantId: 'biz_001',
      businessName: 'THQ Test Enterprises',
      deviceId: 'dev_01',
      deviceCode: 'DEV-01',
      deviceName: 'Office Tablet',
      locationId: 'loc_1',
      locationCode: 'MAIN',
      locationName: 'Main Store',
      currencyCode: currencyCode,
      username: 'admin',
      canViewAllLocations: canViewAllLocations,
      canApprove: true,
      canReceiveCustomerPayment: true,
      canViewNotifications: true,
      canViewAudit: true,
      canViewTraceability: true,
      canViewWarranty: true,
      locations: const [
        MobileLocation(id: 'loc_1', code: 'MAIN', name: 'Main Store', accessLevel: 'full'),
        MobileLocation(id: 'loc_2', code: 'SEC', name: 'Secondary Store', accessLevel: 'read'),
      ],
      release: const ThqMobileReleaseStatus.unknown(),
    );
  }

  group('MobileSession & Currency tests', () {
    test('session currency fallback and getter work accurately', () {
      final session = buildSession(currencyCode: 'INR');

      expect(session.currency, 'INR');
      expect(session.currencyCode, 'INR');
      expect(session.locations.length, 2);
      expect(session.canViewAllLocations, isTrue);
    });
  });

  group('MobileModulesCatalogPage Widget Tests', () {
    final session = buildSession();
    final service = MockMobileClientService();

    testWidgets('catalog renders search field, categories and module items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileModulesCatalogPage(
              session: session,
              service: service,
              locationId: 'loc_1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify search input
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      // Verify category chips
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Operations'), findsOneWidget);
      expect(find.text('Logistics & Quarry'), findsOneWidget);

      // Verify modules are present
      expect(find.text('Sales Register'), findsOneWidget);
      expect(find.text('Purchases & Inward'), findsOneWidget);
      expect(find.text('Material Yard / Quarry'), findsOneWidget);
      expect(find.text('Staff & Attendance'), findsOneWidget);
      expect(find.text('Financial Accounting'), findsOneWidget);
      expect(find.text('Reports Center'), findsOneWidget);
    });

    testWidgets('catalog search filters items accurately', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileModulesCatalogPage(
              session: session,
              service: service,
              locationId: 'loc_1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter search term 'Quarry'
      await tester.enterText(find.byType(TextField), 'Quarry');
      await tester.pumpAndSettle();

      // Material yard should be visible, Purchases should not
      expect(find.text('Material Yard / Quarry'), findsOneWidget);
      expect(find.text('Purchases & Inward'), findsNothing);
    });

    testWidgets('category filtering works properly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileModulesCatalogPage(
              session: session,
              service: service,
              locationId: 'loc_1',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'Logistics & Quarry' which is in the visible horizontal viewport
      await tester.tap(find.text('Logistics & Quarry'));
      await tester.pumpAndSettle();

      // Material Yard should be present, Sales Register should not
      expect(find.text('Material Yard / Quarry'), findsOneWidget);
      expect(find.text('Sales Register'), findsNothing);
    });
  });

  group('Module Customization Preferences Tests', () {
    test('user preferences serialization with pinned favorites and density', () {
      final prefs = ThqUserUiPreferences(
        appScope: ThqAppScope.mobileErp.key,
        favorites: const {'purchases', 'transfers', 'material_yard'},
        hiddenNodes: const {'legacy_sync'},
        defaultLandingModule: 'material_yard',
        tableDensity: 'compact',
      );

      final map = prefs.toMap();
      expect(map['app_scope'], 'client_mobile');
      expect((map['favorites'] as List).contains('purchases'), isTrue);
      expect(map['default_landing_module'], 'material_yard');
      expect(map['table_density'], 'compact');

      final reconstructed = ThqUserUiPreferences.fromMap(map);
      expect(reconstructed.appScope, ThqAppScope.mobileErp.key);
      expect(reconstructed.favorites, prefs.favorites);
      expect(reconstructed.defaultLandingModule, 'material_yard');
      expect(reconstructed.tableDensity, 'compact');
    });
  });
}
