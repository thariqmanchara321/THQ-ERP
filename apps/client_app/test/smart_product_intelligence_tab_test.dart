import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_core/erp_core.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/smart_inventory/tabs/smart_product_intelligence_tab.dart';

void main() {
  group('SmartProductIntelligenceTab Widget Tests', () {
    const tenantId = 'tenant-client-1';

    const testBusiness = ClientBusiness(
      id: tenantId,
      membershipId: 'mem-1',
      name: 'Smart Hardware Ltd',
      slug: 'smart-hardware',
      businessType: 'retail',
      status: 'active',
    );

    const standardSession = ClientSession(
      business: testBusiness,
      userId: 'user-1',
      username: 'Alice Staff',
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
      permissions: {'inventory.view', 'inventory.manage'},
      currencyCode: 'INR',
      timezone: 'Asia/Kolkata',
      locale: 'en_IN',
    );

    testWidgets('renders search controls, quick chips, and provider options', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartProductIntelligenceTab(session: standardSession),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Search Intelligence'), findsOneWidget);
      expect(find.text('All Providers'), findsOneWidget);
      expect(find.text('External Product Intelligence & GS1 Lookup'), findsOneWidget);

      // Quick chips
      expect(find.textContaining('Bru Instant Coffee'), findsOneWidget);
      expect(find.textContaining('UltraTech Cement 50kg'), findsOneWidget);
      expect(find.textContaining('Havells 16A Socket'), findsOneWidget);
      expect(find.textContaining('Classmate Spiral Notebook'), findsOneWidget);
    });

    testWidgets('triggers lookup when quick chip is tapped and renders comparison view', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockProvider = MockExternalProductProvider();
      final engine = ExternalProductIntelligenceEngine(
        providers: [mockProvider],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartProductIntelligenceTab(
              session: standardSession,
              customEngine: engine,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap on Bru Instant Coffee quick chip
      final chip = find.textContaining('Bru Instant Coffee');
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Side-by-side comparison view should appear
      expect(find.byType(ThqCatalogueComparisonView), findsOneWidget);
      expect(find.textContaining('8901030382345'), findsWidgets);
      expect(find.textContaining('Protected Accounting Invariant'), findsOneWidget);
    });

    testWidgets('listens to wireless phone scanner and triggers automatic lookup', (tester) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockTransport = MockWirelessScannerTransport();
      final coordinator = WirelessScannerCoordinator(transport: mockTransport);
      final mockProvider = MockExternalProductProvider();
      final engine = ExternalProductIntelligenceEngine(
        providers: [mockProvider],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartProductIntelligenceTab(
              session: standardSession,
              wirelessCoordinator: coordinator,
              customEngine: engine,
            ),
          ),
        ),
      );
      await tester.pump();

      // Transmit scan from mock phone
      final scan = WirelessScanMessage.create(
        sessionId: 'session-test-1',
        tenantId: tenantId,
        senderDeviceId: 'phone-galaxy-s22',
        senderDeviceName: 'Galaxy S22 Assistant',
        rawCode: '8901234567890',
        format: SmartBarcodeFormat.ean13,
        handshakeSecret: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      );

      mockTransport.simulateIncomingScan(scan);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Discovered cement product comparison appears
      expect(find.byType(ThqCatalogueComparisonView), findsOneWidget);
      expect(find.textContaining('UltraTech'), findsWidgets);

      coordinator.dispose();
    });

    testWidgets('clears cache and shows notification when evict cache button is pressed', (tester) async {
      final mockProvider = MockExternalProductProvider();
      final engine = ExternalProductIntelligenceEngine(
        providers: [mockProvider],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartProductIntelligenceTab(
              session: standardSession,
              customEngine: engine,
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap evict cache button
      final evictButton = find.byIcon(Icons.cached);
      expect(evictButton, findsOneWidget);
      await tester.tap(evictButton);
      await tester.pump();

      expect(find.textContaining('Evicted 0 cached product intelligence records.'), findsOneWidget);
    });
  });
}
