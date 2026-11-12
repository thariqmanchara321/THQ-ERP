import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../scanner/barcode_accuracy_verifier.dart';
import '../scanner/scanner_models.dart';
import 'external_product_intelligence_provider.dart';
import 'external_product_models.dart';
import 'product_intelligence_http_client.dart';

/// Provider for official GS1 Registry Platform (GRP) / Verified by GS1 API.
///
/// **Crucial GS1 Architecture & Licensing Distinctions:**
/// 1. **Format Validation != Identity Verification:** A mathematically valid EAN-13 or UPC-A Modulo 10
///    check digit proves only that the digits conform to GS1 encoding rules. It does **not** prove product
///    ownership, active GTIN license status, or authentic manufacturer identity.
/// 2. **Authentication Requirements:** Querying the official GS1 Registry Platform (api.gs1.org)
///    requires a licensed GS1 Member Organization subscription, client ID, and OAuth2 bearer token.
/// 3. **Data Provenance:** Records returned by this provider are marked with `isGs1Verified: true`,
///    strictly distinguishing official GS1 allocation records from third-party or crowdsourced catalogues.
class Gs1RegistryProvider implements ExternalProductIntelligenceProvider {
  final ProductIntelligenceHttpClient _httpClient;
  final String? apiKey;
  final String endpointUrl;

  Gs1RegistryProvider({
    ProductIntelligenceHttpClient? httpClient,
    this.apiKey,
    this.endpointUrl = 'https://api.gs1.org/grp/v3/products',
  }) : _httpClient = httpClient ?? DefaultProductIntelligenceHttpClient();

  @override
  String get id => 'gs1_registry';

  @override
  String get displayName => 'Verified by GS1 (GS1 Registry Platform)';

  @override
  String get description =>
      'Official global registry verifying GTIN licensing, brand ownership, and manufacturer company prefix directly with GS1.';

  @override
  bool get requiresCredentials => true;

  @override
  bool get isConfigured => apiKey != null && apiKey!.trim().isNotEmpty;

  /// Validates GTIN format and check digit locally without making network calls.
  BarcodeAccuracyResult validateBarcodeFormat(String rawBarcode) {
    return BarcodeAccuracyVerifier.verify(rawValue: rawBarcode);
  }

  @override
  bool get isOfficialGs1 => true;

  @override
  Future<ExternalLookupResult> lookupBarcode(
    String barcode, {
    String? tenantId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) {
      return ExternalLookupResult.noMatch(providerId: id);
    }

    // 1. Barcode Symbology & Check Digit Verification
    final accuracy = BarcodeAccuracyVerifier.verify(rawValue: trimmed);
    if (!accuracy.isValid) {
      return ExternalLookupResult.error(
        providerId: id,
        message: 'Invalid GTIN barcode: ${accuracy.rejectionReason}',
      );
    }

    // 2. Credential Verification Check
    if (!isConfigured) {
      return ExternalLookupResult.unauthorized(
        providerId: id,
        message:
            'Verified by GS1 lookup requires an active GS1 Member Organization subscription and API key. '
            'Barcode "$trimmed" passed Modulo 10 format validation, but live GS1 Registry Platform access is unconfigured.',
      );
    }

    final stopwatch = Stopwatch()..start();
    // Normalized 14-digit GTIN per GS1 specifications (padded with leading zeros if 12 or 13 digits)
    final gtin14 = trimmed.padLeft(14, '0');
    final uri = Uri.parse('$endpointUrl/$gtin14');

    try {
      final jsonStr = await _httpClient.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${apiKey!.trim()}',
          'API-Key': apiKey!.trim(),
        },
        timeout: timeout,
      );
      stopwatch.stop();

      if (jsonStr.isEmpty) {
        return ExternalLookupResult.noMatch(
          providerId: id,
          barcode: trimmed,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }

      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        return ExternalLookupResult.noMatch(
          providerId: id,
          barcode: trimmed,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }

      final candidate = _parseGs1Payload(decoded, trimmed, accuracy.format);
      return ExternalLookupResult.success(
        providerId: id,
        candidates: [candidate],
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } on HttpException catch (he) {
      stopwatch.stop();
      if (he.message.contains('401') || he.message.contains('403')) {
        return ExternalLookupResult.unauthorized(
          providerId: id,
          message: 'GS1 Registry Platform rejected API credentials: ${he.message}',
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      } else if (he.message.contains('429')) {
        return ExternalLookupResult.rateLimited(
          providerId: id,
          message: 'GS1 Registry Platform rate limit exceeded.',
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }
      return ExternalLookupResult.error(
        providerId: id,
        message: 'GS1 Registry Platform error: ${he.message}',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ExternalLookupResult.error(
        providerId: id,
        message: 'Failed to query GS1 Registry: $e',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  @override
  Future<ExternalLookupResult> search(ExternalLookupRequest request) async {
    // Official GS1 Registry Platform operates primarily on GTIN key lookups
    if (request.barcode != null && request.barcode!.trim().isNotEmpty) {
      return lookupBarcode(
        request.barcode!,
        tenantId: request.tenantId,
        timeout: request.timeout,
      );
    }

    return ExternalLookupResult.noMatch(
      providerId: id,
      barcode: request.productName,
    );
  }

  ExternalProductCandidate _parseGs1Payload(
    Map<String, dynamic> data,
    String barcode,
    SmartBarcodeFormat format,
  ) {
    final productName = data['productDescription']?.toString() ??
        data['tradeItemDescription']?.toString() ??
        data['name']?.toString() ??
        'GS1 Item ($barcode)';

    final brand = data['brandName']?.toString();
    final manufacturer = data['companyName']?.toString() ?? data['licensingCompany']?.toString();
    final category = data['gpcCategoryName']?.toString() ?? data['category']?.toString();
    final description = data['description']?.toString() ?? data['functionalName']?.toString();
    final imageUrl = data['tradeItemImageUrl']?.toString() ?? data['imageUrl']?.toString();

    final specs = <String, String>{
      'GS1 Status': data['status']?.toString() ?? 'Active',
      'GTIN-14': barcode.padLeft(14, '0'),
    };

    if (data['netContent'] != null) {
      specs['Net Content'] = data['netContent'].toString();
    }
    if (data['countryOfOrigin'] != null) {
      specs['Country of Origin'] = data['countryOfOrigin'].toString();
    }
    if (data['licensingGln'] != null) {
      specs['Licensing GLN'] = data['licensingGln'].toString();
    }

    return ExternalProductCandidate(
      providerId: id,
      sourceName: displayName,
      barcode: barcode,
      format: format,
      productName: productName.trim(),
      brand: brand?.isNotEmpty == true ? brand : null,
      manufacturer: manufacturer?.isNotEmpty == true ? manufacturer : null,
      category: category?.isNotEmpty == true ? category : null,
      description: description?.isNotEmpty == true ? description : null,
      imageUrl: imageUrl?.isNotEmpty == true ? imageUrl : null,
      specifications: specs,
      matchConfidence: 1.0,
      isGs1Verified: true, // Direct GS1 registry provenance
      fetchedAt: DateTime.now(),
      rawPayload: data,
    );
  }
}
