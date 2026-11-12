import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../scanner/barcode_accuracy_verifier.dart';
import '../scanner/scanner_models.dart';
import 'external_product_intelligence_provider.dart';
import 'external_product_models.dart';
import 'product_intelligence_http_client.dart';

/// Legitimate external provider connecting to Open Food Facts / Open Products Facts (ODbL license).
///
/// Provides global public access to over 3 million consumer, food, grocery, and packaged products.
/// - Requires zero API keys or commercial subscriptions for standard application queries.
/// - Strict adherence to Open Database License (ODbL) and official API guidelines.
/// - Mandatory user-agent identification sent on all HTTP calls.
class OpenProductFactsProvider implements ExternalProductIntelligenceProvider {
  final ProductIntelligenceHttpClient _httpClient;
  final String baseUrl;

  OpenProductFactsProvider({
    ProductIntelligenceHttpClient? httpClient,
    this.baseUrl = 'https://world.openfoodfacts.org',
  }) : _httpClient = httpClient ?? DefaultProductIntelligenceHttpClient();

  @override
  String get id => 'open_food_facts';

  @override
  String get displayName => 'Open Food Facts (Public ODbL)';

  @override
  String get description =>
      'Global crowdsourced open database of consumer and grocery products under the Open Database License (ODbL).';

  @override
  bool get requiresCredentials => false;

  @override
  bool get isConfigured => true;

  @override
  bool get isOfficialGs1 => false;

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

    // Verify format compliance (EAN-13, UPC-A, etc.)
    final accuracy = BarcodeAccuracyVerifier.verify(rawValue: trimmed);

    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$baseUrl/api/v2/product/$trimmed.json');

    try {
      final jsonStr = await _httpClient.get(uri, timeout: timeout);
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

      final status = (decoded['status'] as num?)?.toInt() ?? 0;
      if (status != 1 || decoded['product'] is! Map) {
        return ExternalLookupResult.noMatch(
          providerId: id,
          barcode: trimmed,
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }

      final p = Map<String, dynamic>.from(decoded['product'] as Map);
      final candidate = _parseProductPayload(p, trimmed, accuracy.format);

      return ExternalLookupResult.success(
        providerId: id,
        candidates: [candidate],
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      stopwatch.stop();
      return ExternalLookupResult.error(
        providerId: id,
        message: 'Open Food Facts query timed out (${timeout.inSeconds}s).',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } on HttpException catch (he) {
      stopwatch.stop();
      if (he.message.contains('429')) {
        return ExternalLookupResult.rateLimited(
          providerId: id,
          message: 'Open Food Facts rate limit reached. Please wait a moment before trying again.',
          elapsedMs: stopwatch.elapsedMilliseconds,
        );
      }
      return ExternalLookupResult.error(
        providerId: id,
        message: 'Open Food Facts error: ${he.message}',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ExternalLookupResult.error(
        providerId: id,
        message: 'Failed to query Open Food Facts: $e',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  @override
  Future<ExternalLookupResult> search(ExternalLookupRequest request) async {
    // If a barcode is provided, always prefer direct barcode lookup
    if (request.barcode != null && request.barcode!.trim().isNotEmpty) {
      return lookupBarcode(
        request.barcode!,
        tenantId: request.tenantId,
        timeout: request.timeout,
      );
    }

    // Text search via Open Food Facts search API
    final query = (request.productName ?? request.brand ?? request.partNumber ?? '').trim();
    if (query.isEmpty) {
      return ExternalLookupResult.noMatch(providerId: id);
    }

    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$baseUrl/cgi/search.pl?search_terms=${Uri.encodeComponent(query)}&search_simple=1&action=process&json=1&page_size=10');

    try {
      final jsonStr = await _httpClient.get(uri, timeout: request.timeout);
      stopwatch.stop();

      if (jsonStr.isEmpty) {
        return ExternalLookupResult.noMatch(providerId: id, elapsedMs: stopwatch.elapsedMilliseconds);
      }

      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        return ExternalLookupResult.noMatch(providerId: id, elapsedMs: stopwatch.elapsedMilliseconds);
      }

      final products = decoded['products'] as List? ?? const [];
      final candidates = <ExternalProductCandidate>[];

      for (final rawProd in products) {
        if (rawProd is Map) {
          final p = Map<String, dynamic>.from(rawProd);
          final code = p['code']?.toString() ?? '';
          if (code.isNotEmpty) {
            candidates.add(_parseProductPayload(p, code, SmartBarcodeFormat.ean13, confidence: 0.85));
          }
        }
      }

      if (candidates.isEmpty) {
        return ExternalLookupResult.noMatch(providerId: id, elapsedMs: stopwatch.elapsedMilliseconds);
      }

      return ExternalLookupResult.success(
        providerId: id,
        candidates: candidates,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } on HttpException catch (he) {
      stopwatch.stop();
      if (he.message.contains('429')) {
        return ExternalLookupResult.rateLimited(providerId: id, elapsedMs: stopwatch.elapsedMilliseconds);
      }
      return ExternalLookupResult.error(providerId: id, message: he.message, elapsedMs: stopwatch.elapsedMilliseconds);
    } catch (e) {
      stopwatch.stop();
      return ExternalLookupResult.error(providerId: id, message: e.toString(), elapsedMs: stopwatch.elapsedMilliseconds);
    }
  }

  ExternalProductCandidate _parseProductPayload(
    Map<String, dynamic> p,
    String barcode,
    SmartBarcodeFormat format, {
    double confidence = 1.0,
  }) {
    final name = p['product_name']?.toString() ??
        p['product_name_en']?.toString() ??
        p['generic_name']?.toString() ??
        'Unknown Product ($barcode)';

    final rawBrands = p['brands']?.toString();
    final brand = (rawBrands != null && rawBrands.isNotEmpty)
        ? rawBrands.split(',').first.trim()
        : null;

    final rawMfrs = p['manufacturers']?.toString();
    final manufacturer = (rawMfrs != null && rawMfrs.isNotEmpty)
        ? rawMfrs.split(',').first.trim()
        : null;

    final rawCats = p['categories']?.toString();
    final category = (rawCats != null && rawCats.isNotEmpty)
        ? rawCats.split(',').first.trim()
        : null;
    final description = p['generic_name']?.toString() ?? p['ingredients_text']?.toString();
    final imageUrl = p['image_front_url']?.toString() ?? p['image_url']?.toString();

    final specs = <String, String>{};
    if (p['quantity'] != null && p['quantity'].toString().isNotEmpty) {
      specs['Net Quantity'] = p['quantity'].toString();
    }
    if (p['packaging'] != null && p['packaging'].toString().isNotEmpty) {
      specs['Packaging'] = p['packaging'].toString();
    }
    if (p['nutriscore_grade'] != null && p['nutriscore_grade'].toString().isNotEmpty) {
      specs['Nutri-Score'] = p['nutriscore_grade'].toString().toUpperCase();
    }
    if (p['serving_size'] != null && p['serving_size'].toString().isNotEmpty) {
      specs['Serving Size'] = p['serving_size'].toString();
    }

    return ExternalProductCandidate(
      providerId: id,
      sourceName: displayName,
      barcode: barcode,
      format: format,
      productName: name.trim(),
      brand: brand?.isNotEmpty == true ? brand : null,
      manufacturer: manufacturer?.isNotEmpty == true ? manufacturer : null,
      category: category?.isNotEmpty == true ? category : null,
      description: description?.isNotEmpty == true ? description : null,
      imageUrl: imageUrl?.isNotEmpty == true ? imageUrl : null,
      specifications: specs,
      matchConfidence: confidence,
      isGs1Verified: false, // OFF is crowdsourced ODbL, not official GS1 registry
      fetchedAt: DateTime.now(),
      rawPayload: p,
    );
  }
}
