import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 13: Permissions, Security & Hardening Tests', () {
    test('CatalogueComparison masks costPrice when canViewCostPrice is false', () {
      final candidate = ExternalProductCandidate(
        providerId: 'open_product_facts',
        sourceName: 'Open Food Facts',
        barcode: '8901030000000',
        format: SmartBarcodeFormat.ean13,
        productName: 'Sample Product External',
        fetchedAt: DateTime.now(),
      );

      final existing = <String, dynamic>{
        'variant_id': 'var-123',
        'product_name': 'Sample Product Existing',
        'cost_price': 150.0,
        'selling_price': 200.0,
      };

      // 1. Authorized user (e.g. owner, admin, inventory manager)
      final authorizedComparison = CatalogueComparison.build(
        existingProduct: existing,
        candidate: candidate,
        canViewCostPrice: true,
      );
      final costFieldAuth = authorizedComparison.fields.firstWhere((f) => f.fieldKey == 'costPrice');
      expect(costFieldAuth.currentValue, '150.0');
      expect(costFieldAuth.isProtected, isTrue);

      // 2. Unauthorized user (cashier/viewer)
      final restrictedComparison = CatalogueComparison.build(
        existingProduct: existing,
        candidate: candidate,
        canViewCostPrice: false,
      );
      final costFieldRestricted = restrictedComparison.fields.firstWhere((f) => f.fieldKey == 'costPrice');
      expect(costFieldRestricted.currentValue, '[Restricted]');
      expect(costFieldRestricted.isProtected, isTrue);

      // Invariant protection: payload must never contain costPrice
      final payload = restrictedComparison.buildEnrichmentPayload();
      expect(payload.containsKey('costPrice'), isFalse);
    });

    test('Wireless scanner rejects cross-tenant pairing', () async {
      final mockTransport = MockWirelessScannerTransport();
      final coordinator = WirelessScannerCoordinator(transport: mockTransport);

      final payload = await coordinator.startHosting(
        tenantId: 'tenant-alpha',
        locationId: 'loc-warehouse',
        hostDeviceName: 'Desktop-1',
      );

      // Attempt join from phone belonging to tenant-beta
      final joinResult = await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'phone-123',
        deviceName: 'Android Phone',
        currentTenantId: 'tenant-beta', // MISMATCH!
        currentLocationId: 'loc-warehouse',
      );

      expect(joinResult, isFalse);
      expect(coordinator.state, isNot(WirelessScannerState.connected));
    });

    test('Wireless scanner rejects cross-location pairing', () async {
      final mockTransport = MockWirelessScannerTransport();
      final coordinator = WirelessScannerCoordinator(transport: mockTransport);

      final payload = await coordinator.startHosting(
        tenantId: 'tenant-alpha',
        locationId: 'loc-store-1',
        hostDeviceName: 'Desktop-1',
      );

      // Attempt join from phone assigned to loc-store-2
      final joinResult = await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'phone-123',
        deviceName: 'Android Phone',
        currentTenantId: 'tenant-alpha',
        currentLocationId: 'loc-store-2', // MISMATCH!
      );

      expect(joinResult, isFalse);
      expect(coordinator.state, isNot(WirelessScannerState.connected));
    });

    test('Wireless scanner accepts matching tenant and location', () async {
      final mockTransport = MockWirelessScannerTransport();
      final coordinator = WirelessScannerCoordinator(transport: mockTransport);

      final payload = await coordinator.startHosting(
        tenantId: 'tenant-alpha',
        locationId: 'loc-store-1',
        hostDeviceName: 'Desktop-1',
      );

      // Matching credentials
      final joinResult = await coordinator.joinAsScanner(
        payload: payload,
        deviceId: 'phone-123',
        deviceName: 'Android Phone',
        currentTenantId: 'tenant-alpha',
        currentLocationId: 'loc-store-1',
      );

      expect(joinResult, isTrue);
      expect(coordinator.state, WirelessScannerState.connected);
    });
  });
}
