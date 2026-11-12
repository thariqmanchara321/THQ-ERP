import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_core/erp_core.dart';

void main() {
  group('External Product Models & Catalogue Comparison', () {
    test('ExternalProductCandidate handles leading zeroes and json serialization', () {
      final candidate = ExternalProductCandidate(
        providerId: 'mock_provider',
        sourceName: 'Mock Provider',
        barcode: '0012345678905',
        format: SmartBarcodeFormat.upcA,
        productName: 'Heinz Tomato Ketchup 500g',
        brand: 'Heinz',
        manufacturer: 'Kraft Heinz',
        category: 'Condiments & Sauces',
        description: 'Classic rich tomato ketchup in squeezable bottle.',
        imageUrl: 'https://example.com/ketchup.jpg',
        specifications: const {'Weight': '500g', 'Package': 'Bottle'},
        matchConfidence: 0.95,
        isGs1Verified: false,
        fetchedAt: DateTime(2026, 11, 12, 10, 0),
        rawPayload: const {'status': 1},
      );

      expect(candidate.barcode, equals('0012345678905'));
      expect(candidate.hasBarcode('0012345678905'), isTrue);
      expect(candidate.hasBarcode('12345678905'), isTrue);
      expect(candidate.hasBarcode('9999999999999'), isFalse);
      expect(candidate.name, equals('Heinz Tomato Ketchup 500g'));

      final json = candidate.toJson();
      expect(json['barcode'], equals('0012345678905'));
      expect(json['isGs1Verified'], isFalse);

      final fromJson = ExternalProductCandidate.fromJson(json);
      expect(fromJson.name, equals('Heinz Tomato Ketchup 500g'));
      expect(fromJson.brand, equals('Heinz'));
      expect(fromJson.specifications['Weight'], equals('500g'));
    });

    test('CatalogueComparison flags conflicts and protects operational fields', () {
      final candidate = ExternalProductCandidate(
        providerId: 'open_product_facts',
        sourceName: 'Open Food Facts',
        barcode: '8901030383748',
        format: SmartBarcodeFormat.ean13,
        productName: 'Bru Gold Instant Coffee 100g Glass Jar',
        brand: 'Bru',
        manufacturer: 'Hindustan Unilever Ltd',
        category: 'Instant Coffee',
        description: 'Granulated instant coffee powder',
        imageUrl: 'https://images.openfoodfacts.org/bru.jpg',
        specifications: const {'Net Weight': '100g'},
        matchConfidence: 0.9,
        fetchedAt: DateTime(2026, 11, 12, 10, 0),
      );

      final existingProduct = {
        'id': 'prod-001',
        'name': 'Bru Instant Coffee 100g', // Conflict with external name
        'barcode': '8901030383748',
        'brand': 'Bru', // Match
        'category': null, // Missing in THQ, present in external
        'cost_price': 180.00, // PROTECTED
        'selling_price': 220.00, // PROTECTED
        'tax_rate': 18.0, // PROTECTED
        'reorder_level': 10, // PROTECTED
        'quantity': 45, // PROTECTED
      };

      final comparison = CatalogueComparison.build(
        existingProduct: existingProduct,
        candidate: candidate,
      );

      expect(comparison.hasConflicts, isTrue);
      expect(comparison.conflictCount, greaterThan(0));

      // Name is conflicting, so by default it should NOT be accepted without explicit user approval
      final nameField = comparison.fields.firstWhere((f) => f.fieldKey == 'productName');
      expect(nameField.isConflict, isTrue);
      expect(nameField.isAccepted, isFalse);

      // Brand is identical, so not conflicting
      final brandField = comparison.fields.firstWhere((f) => f.fieldKey == 'brand');
      expect(brandField.isConflict, isFalse);

      // Category is missing in THQ, so external value is accepted by default
      final categoryField = comparison.fields.firstWhere((f) => f.fieldKey == 'category');
      expect(categoryField.isConflict, isFalse);
      expect(categoryField.isAccepted, isTrue);

      // Operational fields MUST be protected
      final protectedKeys = ['costPrice', 'sellingPrice', 'stockQuantity'];
      for (final field in comparison.fields.where((f) => protectedKeys.contains(f.fieldKey))) {
        expect(field.isProtected, isTrue);
        expect(field.isAccepted, isFalse);
      }

      // User explicitly accepts external name
      comparison.setFieldAccepted('productName', true);
      expect(comparison.isFieldAccepted('productName'), isTrue);

      // Verify payload only takes accepted non-protected fields
      final payload = comparison.buildEnrichmentPayload();
      expect(payload['productName'], equals('Bru Gold Instant Coffee 100g Glass Jar'));
      expect(payload['category'], equals('Instant Coffee'));
      expect(payload.containsKey('costPrice'), isFalse);
      expect(payload.containsKey('sellingPrice'), isFalse);
      expect(payload.containsKey('stockQuantity'), isFalse);

      // Verify audit provenance metadata
      final provenance = comparison.buildAuditProvenance(approvedByUserId: 'user-admin-123');
      expect(provenance['source_provider_id'], equals('open_product_facts'));
      expect(provenance['approved_by_user_id'], equals('user-admin-123'));
      expect(provenance['accepted_fields'], contains('productName'));
      expect(provenance['accepted_fields'], contains('category'));
    });
  });

  group('Open Food Facts Provider', () {
    test('parses product information correctly from API response', () async {
      final mockHttp = MockProductIntelligenceHttpClient();
      mockHttp.setMockResponse(
        Uri.parse('https://world.openfoodfacts.org/api/v2/product/8901030383748.json'),
        statusCode: 200,
        body: jsonEncode({
          'status': 1,
          'code': '8901030383748',
          'product': {
            'product_name': 'Bru Gold Instant Coffee',
            'product_name_en': 'Bru Gold Instant Coffee',
            'generic_name': '100% Pure Coffee Granules',
            'brands': 'Bru, Hindustan Unilever',
            'manufacturers': 'Hindustan Unilever Limited',
            'categories': 'Beverages, Coffees, Instant Coffees',
            'image_front_url': 'https://images.openfoodfacts.org/images/products/890/103/038/3748/front_en.jpg',
            'quantity': '100 g',
            'packaging': 'Glass Jar'
          }
        }),
      );

      final provider = OpenProductFactsProvider(httpClient: mockHttp);
      final result = await provider.lookupBarcode('8901030383748');

      expect(result.status, equals(ExternalLookupStatus.success));
      expect(result.candidates.length, equals(1));

      final c = result.candidates.first;
      expect(c.barcode, equals('8901030383748'));
      expect(c.name, equals('Bru Gold Instant Coffee'));
      expect(c.brand, equals('Bru'));
      expect(c.manufacturer, equals('Hindustan Unilever Limited'));
      expect(c.category, equals('Beverages'));
      expect(c.imageUrl, equals('https://images.openfoodfacts.org/images/products/890/103/038/3748/front_en.jpg'));
      expect(c.specifications['Net Quantity'], equals('100 g'));
      expect(c.specifications['Packaging'], equals('Glass Jar'));
      expect(c.isGs1Verified, isFalse);
    });

    test('handles 404 / product not found gracefully', () async {
      final mockHttp = MockProductIntelligenceHttpClient();
      mockHttp.setMockResponse(
        Uri.parse('https://world.openfoodfacts.org/api/v2/product/9999999999999.json'),
        statusCode: 404,
        body: jsonEncode({'status': 0, 'status_verbose': 'product not found'}),
      );

      final provider = OpenProductFactsProvider(httpClient: mockHttp);
      final result = await provider.lookupBarcode('9999999999999');

      expect(result.status, equals(ExternalLookupStatus.noMatch));
      expect(result.candidates, isEmpty);
    });

    test('handles 429 rate limit with friendly message', () async {
      final mockHttp = MockProductIntelligenceHttpClient();
      mockHttp.setMockResponse(
        Uri.parse('https://world.openfoodfacts.org/api/v2/product/8901030383748.json'),
        statusCode: 429,
        body: 'Rate limit exceeded',
      );

      final provider = OpenProductFactsProvider(httpClient: mockHttp);
      final result = await provider.lookupBarcode('8901030383748');

      expect(result.status, equals(ExternalLookupStatus.rateLimited));
      expect(result.errorMessage, contains('rate limit'));
    });
  });

  group('GS1 Registry Platform Provider', () {
    test('validates barcode check digits mathematically', () async {
      final provider = Gs1RegistryProvider();

      // Valid EAN-13: 8901030383748 (Bru Coffee)
      final validEan = provider.validateBarcodeFormat('8901030383748');
      expect(validEan.isValid, isTrue);
      expect(validEan.format, equals(SmartBarcodeFormat.ean13));

      // Invalid check digit: 8901030383749 (ending with 9 instead of 8)
      final invalidEan = provider.validateBarcodeFormat('8901030383749');
      expect(invalidEan.isValid, isFalse);
      expect(invalidEan.rejectionReason, contains('check digit mismatch'));

      // Valid UPC-A: 012345678905
      final validUpc = provider.validateBarcodeFormat('012345678905');
      expect(validUpc.isValid, isTrue);
      expect(validUpc.format, equals(SmartBarcodeFormat.upcA));
    });

    test('returns unauthorized with informative message when GS1 credentials are not configured', () async {
      final provider = Gs1RegistryProvider(
        apiKey: null,
      );

      expect(provider.isConfigured, isFalse);

      final result = await provider.lookupBarcode('8901030383748');
      expect(result.status, equals(ExternalLookupStatus.unauthorized));
      expect(result.errorMessage, contains('GS1 Member Organization subscription'));
    });

    test('queries GS1 GRP endpoints when configured', () async {
      final mockHttp = MockProductIntelligenceHttpClient();
      mockHttp.setMockResponse(
        Uri.parse('https://api.gs1.org/grp/v3/products/08901030383748'),
        statusCode: 200,
        body: jsonEncode({
          'gtin': '08901030383748',
          'productDescription': 'Bru Gold Instant Coffee 100g',
          'brandName': 'Bru',
          'gpcCategoryName': 'Coffee / Coffee Substitutes',
          'companyName': 'Hindustan Unilever Limited',
          'licensingGln': '8901030000001',
          'countryOfOrigin': 'India',
          'status': 'ACTIVE',
        }),
      );

      final provider = Gs1RegistryProvider(
        apiKey: 'test-key',
        httpClient: mockHttp,
      );

      expect(provider.isConfigured, isTrue);

      final result = await provider.lookupBarcode('8901030383748');
      expect(result.status, equals(ExternalLookupStatus.success));
      expect(result.candidates.length, equals(1));

      final c = result.candidates.first;
      expect(c.name, equals('Bru Gold Instant Coffee 100g'));
      expect(c.brand, equals('Bru'));
      expect(c.manufacturer, equals('Hindustan Unilever Limited'));
      expect(c.isGs1Verified, isTrue);
      expect(c.specifications['Country of Origin'], equals('India'));
    });
  });

  group('Mock External Product Provider', () {
    test('contains pre-seeded building materials and retail products', () async {
      final provider = MockExternalProductProvider();

      // Cement lookup
      final cement = await provider.lookupBarcode('8901234567890');
      expect(cement.status, equals(ExternalLookupStatus.success));
      expect(cement.candidates.first.name, contains('UltraTech'));
      expect(cement.candidates.first.brand, equals('UltraTech'));
      expect(cement.candidates.first.specifications['Grade'], equals('PPC 53'));

      // Electrical item lookup
      final socket = await provider.lookupBarcode('0012345678905');
      expect(socket.status, equals(ExternalLookupStatus.success));
      expect(socket.candidates.first.brand, equals('Havells'));

      // Notebook lookup
      final notebook = await provider.lookupBarcode('8901234000001');
      expect(notebook.status, equals(ExternalLookupStatus.success));
      expect(notebook.candidates.first.brand, equals('Classmate'));
    });

    test('supports text-based search queries', () async {
      final provider = MockExternalProductProvider();
      final results = await provider.search(
        const ExternalLookupRequest(productName: 'cement'),
      );

      expect(results.status, equals(ExternalLookupStatus.success));
      expect(results.candidates.isNotEmpty, isTrue);
      expect(results.candidates.first.name, contains('Cement'));
    });
  });

  group('External Product Intelligence Engine (Orchestrator)', () {
    test('dispatches queries, caches results for 15 minutes, and deduplicates in-flight calls', () async {
      final mockProvider = MockExternalProductProvider();
      final engine = ExternalProductIntelligenceEngine(
        providers: [mockProvider],
        cacheTtl: const Duration(minutes: 15),
      );

      // First lookup - misses cache and fetches from provider
      final firstLookup = await engine.lookupBarcode('8901234567890');
      expect(firstLookup.isNotEmpty, isTrue);
      expect(firstLookup.first.name, contains('UltraTech'));

      // Second lookup - served instantly from cache
      final secondLookup = await engine.lookupBarcode('8901234567890');
      expect(secondLookup.isNotEmpty, isTrue);
      expect(identical(firstLookup.first, secondLookup.first), isTrue);

      // In-flight deduplication: trigger two concurrent lookups for uncached barcode
      final future1 = engine.lookupBarcode('0012345678905');
      final future2 = engine.lookupBarcode('0012345678905');
      final results = await Future.wait([future1, future2]);

      expect(results[0].length, equals(results[1].length));
      expect(results[0].first.name, equals(results[1].first.name));
    });

    test('clears cache on demand', () async {
      final mockProvider = MockExternalProductProvider();
      final engine = ExternalProductIntelligenceEngine(
        providers: [mockProvider],
      );

      await engine.lookupBarcode('8901234567890');
      expect(engine.clearCache(), equals(1));
      expect(engine.clearCache(), equals(0));
    });
  });
}
