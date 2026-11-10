import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductIdentificationEngine Tests', () {
    const tenantId = 'tenant-test-111';
    const locationId = 'loc-test-222';

    final sampleProductMap = <String, dynamic>{
      'product_id': 'prod-001',
      'variant_id': 'var-001',
      'product_name': 'Steel Rebar 12mm',
      'variant_name': '12mm x 12m',
      'sku': 'SKU-REBAR-12',
      'barcode': '8901234567890',
      'part_number': 'MFG-ST-12',
      'brand_name': 'Tata Tiscon',
      'category_name': 'Steel',
      'unit_code': 'TON',
      'unit_name': 'Metric Tonne',
      'selling_price': 54000.0,
      'cost_price': 48000.0,
      'stock_quantity': 18.5,
      'identifiers': [
        {
          'identifier_id': 'id-1',
          'type': 'barcode',
          'code': '8901234567890',
          'label': 'EAN-13 Primary',
          'is_primary': true,
          'active': true,
        },
        {
          'identifier_id': 'id-2',
          'type': 'qr',
          'code': 'THQ:PRODUCT:rebar12:00000001',
          'label': 'THQ QR Matrix',
          'is_primary': false,
          'active': true,
        },
        {
          'identifier_id': 'id-3',
          'type': 'internal',
          'code': 'INT-STEEL-12MM',
          'label': 'Yard Bin Tag',
          'is_primary': false,
          'active': true,
        },
        {
          'identifier_id': 'id-4',
          'type': 'supplier',
          'code': 'SUP-TATA-R12',
          'supplier_id': 'sup-1',
          'label': 'Tata Mill Code',
          'is_primary': false,
          'active': true,
        },
        {
          'identifier_id': 'id-5',
          'type': 'alternate_sku',
          'code': 'ALT-REB-12',
          'label': 'Legacy ERP code',
          'is_primary': false,
          'active': true,
        },
      ],
      'search_codes': '8901234567890 SKU-REBAR-12 INT-STEEL-12MM MFG-ST-12',
    };

    final zeroPaddedProductMap = <String, dynamic>{
      'product_id': 'prod-002',
      'variant_id': 'var-002',
      'product_name': 'Precision Ball Bearing',
      'variant_name': 'Standard',
      'sku': 'SKU-BRG-002',
      'barcode': '0012345678905',
      'part_number': '000-MFG-99',
      'selling_price': 450.0,
      'stock_quantity': 120.0,
      'identifiers': [
        {
          'identifier_id': 'id-zp-1',
          'type': 'barcode',
          'code': '0012345678905',
          'is_primary': true,
          'active': true,
        },
      ],
    };

    test('Exact barcode match resolves product and variant with MatchMethod.exactBarcode', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '8901234567890',
          tenantId: tenantId,
          locationId: locationId,
          scannerSource: ScannerSource.usb,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.isExact, isTrue);
      expect(result.primaryMatch, isNotNull);
      expect(result.primaryMatch!.variantId, 'var-001');
      expect(result.primaryMatch!.productName, 'Steel Rebar 12mm');
      expect(result.primaryMatch!.matchMethod, MatchMethod.exactBarcode);
      expect(result.primaryMatch!.matchedCode, '8901234567890');
      expect(result.primaryMatch!.sellingPrice, 54000.0);
    });

    test('Exact QR code match resolves with MatchMethod.exactQr', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'THQ:PRODUCT:rebar12:00000001',
          tenantId: tenantId,
          scannerSource: ScannerSource.camera,
          barcodeFormat: SmartBarcodeFormat.qrCode,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.matchMethod, MatchMethod.exactQr);
      expect(result.primaryMatch!.sku, 'SKU-REBAR-12');
    });

    test('Exact SKU match resolves with MatchMethod.exactSku', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'SKU-REBAR-12',
          tenantId: tenantId,
          scannerSource: ScannerSource.manual,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.matchMethod, MatchMethod.exactSku);
      expect(result.primaryMatch!.variantId, 'var-001');
    });

    test('Exact Manufacturer part number resolves with MatchMethod.exactManufacturer', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'MFG-ST-12',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.matchMethod, MatchMethod.exactManufacturer);
    });

    test('Exact Internal yard tag resolves with MatchMethod.exactInternal', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'INT-STEEL-12MM',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.matchMethod, MatchMethod.exactInternal);
    });

    test('Exact Supplier code resolves with MatchMethod.exactSupplier', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'SUP-TATA-R12',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.matchMethod, MatchMethod.exactSupplier);
    });

    test('Exact Alternate SKU resolves with MatchMethod.exactAlternateSku', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'ALT-REB-12',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.matchMethod, MatchMethod.exactAlternateSku);
    });

    test('Leading zeros are strictly preserved and never stripped or numeric-parsed', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([zeroPaddedProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      const zeroCode = '0012345678905';
      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: zeroCode,
          tenantId: tenantId,
          scannerSource: ScannerSource.usb,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.matchedCode, zeroCode);
      expect(result.primaryMatch!.barcode, zeroCode);
      expect(result.primaryMatch!.barcode!.startsWith('00'), isTrue);
    });

    test('Case-insensitivity is supported while raw casing is preserved', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'sku-rebar-12', // Lowercase search for uppercase SKU
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.sku, 'SKU-REBAR-12');
      expect(result.request.rawIdentifier, 'sku-rebar-12');
    });

    test('Whitespace is safely trimmed while preserving raw identifier', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '   8901234567890 \r\n',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.request.rawIdentifier, '   8901234567890 \r\n');
      expect(result.primaryMatch!.matchedCode, '8901234567890');
    });

    test('Invalid input rejection on empty or whitespace strings', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final emptyResult = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '',
          tenantId: tenantId,
        ),
      );
      expect(emptyResult.status, ProductIdentificationStatus.invalidIdentifier);
      expect(emptyResult.errorMessage, contains('cannot be empty'));

      final spaceResult = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '    ',
          tenantId: tenantId,
        ),
      );
      expect(spaceResult.status, ProductIdentificationStatus.invalidIdentifier);
      expect(spaceResult.errorMessage, contains('only whitespace'));
    });

    test('No match returned when code is absent from catalog', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'NON-EXISTENT-CODE-999',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.noMatch);
      expect(result.isNotFound, isTrue);
      expect(result.matches, isEmpty);
    });

    test('Multiple matches returned when code is ambiguous across variants without auto-picking', () async {
      final conflictingProduct1 = {
        'product_id': 'prod-A',
        'variant_id': 'var-A',
        'product_name': 'Cement 50kg Grade A',
        'sku': 'SKU-CEM-A',
        'search_codes': 'SHARED-CODE',
      };
      final conflictingProduct2 = {
        'product_id': 'prod-B',
        'variant_id': 'var-B',
        'product_name': 'Cement 50kg Grade B',
        'sku': 'SKU-CEM-B',
        'search_codes': 'SHARED-CODE',
      };

      final repo = LocalProductIdentificationRepository.fromStatic([
        conflictingProduct1,
        conflictingProduct2,
      ]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'SHARED-CODE',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.multipleMatches);
      expect(result.isAmbiguous, isTrue);
      expect(result.matches.length, 2);
      expect(result.primaryMatch, isNull); // Never auto-selects first on ambiguity
    });

    test('Priority hierarchy resolves exact barcode over conflicting search code', () async {
      final barcodeProduct = {
        'product_id': 'prod-P1',
        'variant_id': 'var-P1',
        'product_name': 'Target Product',
        'sku': 'SKU-TARGET',
        'barcode': '111222333',
      };
      final tokenProduct = {
        'product_id': 'prod-P2',
        'variant_id': 'var-P2',
        'product_name': 'Collateral Product',
        'sku': 'SKU-OTHER',
        'search_codes': '111222333',
      };

      final repo = LocalProductIdentificationRepository.fromStatic([
        barcodeProduct,
        tokenProduct,
      ]);
      final engine = ProductIdentificationEngine(repository: repo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '111222333',
          tenantId: tenantId,
        ),
      );

      // Exact barcode (rank 1) wins over search index token (rank 9)
      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.variantId, 'var-P1');
      expect(result.primaryMatch!.matchMethod, MatchMethod.exactBarcode);
    });

    test('Offline lookup returns offlineMiss when item is missing from cache', () async {
      final offlineRepo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(
        repository: LocalProductIdentificationRepository.fromStatic([]),
        offlineRepository: offlineRepo,
      );

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: 'ABSENT-OFFLINE-CODE',
          tenantId: tenantId,
          forceOffline: true,
        ),
      );

      expect(result.status, ProductIdentificationStatus.offlineMiss);
      expect(result.isNotFound, isTrue);
    });

    test('Offline lookup returns offlineMiss when local store is unpopulated', () async {
      final emptyOfflineRepo = LocalProductIdentificationRepository.fromStatic([]);
      final engine = ProductIdentificationEngine(
        repository: emptyOfflineRepo,
        offlineRepository: emptyOfflineRepo,
      );

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '8901234567890',
          tenantId: tenantId,
          forceOffline: true,
        ),
      );

      expect(result.status, ProductIdentificationStatus.offlineMiss);
      expect(result.diagnostics['reason'], contains('unpopulated or empty'));
    });

    test('Phase 1 SmartScanResult seamlessly bridges into identifyScan with source preserved', () async {
      final repo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);
      final engine = ProductIdentificationEngine(repository: repo);

      final scanResult = SmartScanResult.valid(
        rawValue: '8901234567890',
        format: SmartBarcodeFormat.ean13,
        source: ScannerSource.camera,
        deviceId: 'term-pos-01',
      );

      final idResult = await engine.identifyScan(
        scanResult,
        tenantId: tenantId,
        locationId: locationId,
      );

      expect(idResult.status, ProductIdentificationStatus.exactMatch);
      expect(idResult.request.scannerSource, ScannerSource.camera);
      expect(idResult.request.barcodeFormat, SmartBarcodeFormat.ean13);
      expect(idResult.request.deviceId, 'term-pos-01');
      expect(idResult.primaryMatch!.sku, 'SKU-REBAR-12');
    });

    test('RpcProductIdentificationRepository maps inventory_product_lookup_v482 parameters correctly', () async {
      String? calledFunction;
      Map<String, dynamic>? calledParams;

      final rpcRepo = RpcProductIdentificationRepository(
        (fn, {params}) async {
          calledFunction = fn;
          calledParams = params;
          return sampleProductMap;
        },
      );

      final engine = ProductIdentificationEngine(repository: rpcRepo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '8901234567890',
          tenantId: tenantId,
          locationId: locationId,
        ),
      );

      expect(calledFunction, 'inventory_product_lookup_v482');
      expect(calledParams!['p_tenant_id'], tenantId);
      expect(calledParams!['p_code'], '8901234567890');
      expect(calledParams!['p_location_id'], locationId);
      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.variantId, 'var-001');
    });

    test('RepositoryException is preserved and marked as status: error (not silent noMatch)', () async {
      final brokenRepo = RpcProductIdentificationRepository(
        (fn, {params}) async {
          throw Exception('PostgreSQL connection timeout: 504 Gateway');
        },
      );

      final engine = ProductIdentificationEngine(repository: brokenRepo);

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '8901234567890',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.error);
      expect(result.hasError, isTrue);
      expect(result.errorMessage, contains('PostgreSQL connection timeout'));
    });

    test('Composite repository falls back to offline cache on online RPC failure', () async {
      final brokenOnlineRepo = RpcProductIdentificationRepository(
        (fn, {params}) async => throw Exception('Network unreachable'),
      );
      final healthyOfflineRepo = LocalProductIdentificationRepository.fromStatic([sampleProductMap]);

      final composite = CompositeProductIdentificationRepository(
        onlineRepository: brokenOnlineRepo,
        offlineRepository: healthyOfflineRepo,
        preferOnline: true,
      );

      final engine = ProductIdentificationEngine(
        repository: composite,
        offlineRepository: healthyOfflineRepo,
      );

      final result = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: '8901234567890',
          tenantId: tenantId,
        ),
      );

      expect(result.status, ProductIdentificationStatus.exactMatch);
      expect(result.primaryMatch!.variantId, 'var-001');
    });
  });
}
