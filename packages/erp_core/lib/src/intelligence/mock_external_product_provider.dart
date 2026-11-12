import '../scanner/scanner_models.dart';
import 'external_product_intelligence_provider.dart';
import 'external_product_models.dart';

/// In-memory mock external intelligence provider for hermetic testing, offline development,
/// and automated verification of catalogue enrichment workflows.
class MockExternalProductProvider implements ExternalProductIntelligenceProvider {
  final Map<String, ExternalProductCandidate> _catalogue = {};

  bool simulateNetworkError = false;
  bool simulateRateLimit = false;
  Duration simulatedDelay = Duration.zero;

  MockExternalProductProvider() {
    _seedDefaultCatalogue();
  }

  @override
  String get id => 'mock_provider';

  @override
  String get displayName => 'Mock Product Intelligence (Offline Testing)';

  @override
  String get description => 'Pre-seeded local test catalogue simulating external product databases.';

  @override
  bool get requiresCredentials => false;

  @override
  bool get isConfigured => true;

  @override
  bool get isOfficialGs1 => false;

  void seedProduct(ExternalProductCandidate candidate) {
    _catalogue[candidate.barcode] = candidate;
  }

  void _seedDefaultCatalogue() {
    final now = DateTime.now();

    seedProduct(
      ExternalProductCandidate(
        providerId: id,
        sourceName: displayName,
        barcode: '8901234567890',
        format: SmartBarcodeFormat.ean13,
        productName: 'UltraTech Super Cement 50kg',
        brand: 'UltraTech',
        manufacturer: 'Aditya Birla Group',
        category: 'Building Materials / Cement',
        modelOrPartNumber: 'UT-CEM-50KG',
        description: 'Premium grade Portland Pozzolana Cement engineered for high compressive strength.',
        imageUrl: 'https://images.thqerp.com/products/ultratech_50kg.png',
        specifications: const {
          'Net Weight': '50 kg',
          'Grade': 'PPC 53',
          'Packaging': 'HDPE Laminated Bag',
          'IS Standard': 'IS 1489 Part 1',
        },
        matchConfidence: 1.0,
        isGs1Verified: false,
        fetchedAt: now,
      ),
    );

    seedProduct(
      ExternalProductCandidate(
        providerId: id,
        sourceName: displayName,
        barcode: '8901030382345',
        format: SmartBarcodeFormat.ean13,
        productName: 'Bru Instant Coffee 100g Jar',
        brand: 'Bru',
        manufacturer: 'Hindustan Unilever Limited',
        category: 'Groceries / Beverages',
        modelOrPartNumber: 'BRU-INST-100G',
        description: 'Roasted blend of 70% coffee and 30% chicory granules for authentic aroma.',
        specifications: const {
          'Net Content': '100 g',
          'Packaging': 'Glass Jar',
          'Shelf Life': '24 Months',
        },
        matchConfidence: 1.0,
        isGs1Verified: false,
        fetchedAt: now,
      ),
    );

    seedProduct(
      ExternalProductCandidate(
        providerId: id,
        sourceName: displayName,
        barcode: '0012345678905',
        format: SmartBarcodeFormat.upcA,
        productName: 'Havells 16A Modular Switch Socket White',
        brand: 'Havells',
        manufacturer: 'Havells India Ltd',
        category: 'Electricals / Switches',
        modelOrPartNumber: 'AH-MOD-16A',
        description: '16A 240V heavy-duty shuttered modular socket with flame-retardant polycarbonate casing.',
        specifications: const {
          'Voltage': '240V AC',
          'Current Rating': '16A',
          'Color': 'Glossy White',
          'Standard': 'IS 1293',
        },
        matchConfidence: 1.0,
        isGs1Verified: false,
        fetchedAt: now,
      ),
    );

    seedProduct(
      ExternalProductCandidate(
        providerId: id,
        sourceName: displayName,
        barcode: '8901234000001',
        format: SmartBarcodeFormat.ean13,
        productName: 'Classmate Pulse Spiral Notebook 180 Pages',
        brand: 'Classmate',
        manufacturer: 'ITC Limited',
        category: 'Stationery / Notebooks',
        modelOrPartNumber: 'ITC-CM-180P',
        description: 'Single line ruled spiral bound notebook with micro-perforated pages.',
        specifications: const {
          'Pages': '180',
          'Ruling': 'Single Line',
          'Size': 'A4 (29.7cm x 21cm)',
        },
        matchConfidence: 1.0,
        isGs1Verified: false,
        fetchedAt: now,
      ),
    );
  }

  @override
  Future<ExternalLookupResult> lookupBarcode(
    String barcode, {
    String? tenantId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }

    if (simulateNetworkError) {
      return ExternalLookupResult.error(
        providerId: id,
        message: 'Simulated network connection failure.',
      );
    }

    if (simulateRateLimit) {
      return ExternalLookupResult.rateLimited(
        providerId: id,
        message: 'Simulated rate limit exceeded.',
      );
    }

    final trimmed = barcode.trim();
    if (_catalogue.containsKey(trimmed)) {
      return ExternalLookupResult.success(
        providerId: id,
        candidates: [_catalogue[trimmed]!],
      );
    }

    return ExternalLookupResult.noMatch(
      providerId: id,
      barcode: trimmed,
    );
  }

  @override
  Future<ExternalLookupResult> search(ExternalLookupRequest request) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }

    if (simulateNetworkError) {
      return ExternalLookupResult.error(
        providerId: id,
        message: 'Simulated network connection failure.',
      );
    }

    if (request.barcode != null && request.barcode!.trim().isNotEmpty) {
      return lookupBarcode(
        request.barcode!,
        tenantId: request.tenantId,
        timeout: request.timeout,
      );
    }

    final query = (request.productName ?? request.brand ?? request.partNumber ?? '').trim().toLowerCase();
    if (query.isEmpty) {
      return ExternalLookupResult.noMatch(providerId: id);
    }

    final matches = _catalogue.values.where((c) {
      final name = c.productName.toLowerCase();
      final brand = (c.brand ?? '').toLowerCase();
      final cat = (c.category ?? '').toLowerCase();
      final part = (c.modelOrPartNumber ?? '').toLowerCase();
      return name.contains(query) || brand.contains(query) || cat.contains(query) || part.contains(query);
    }).toList();

    if (matches.isEmpty) {
      return ExternalLookupResult.noMatch(providerId: id);
    }

    return ExternalLookupResult.success(
      providerId: id,
      candidates: matches,
    );
  }
}
