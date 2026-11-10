import 'package:flutter/foundation.dart';

import '../pricing.dart';
import '../scanner/scanner_models.dart';

/// The final outcome of a product identification lookup.
enum ProductIdentificationStatus {
  /// Exactly one matching product/variant was positively identified.
  exactMatch,

  /// More than one product/variant matched the query; requires user disambiguation.
  multipleMatches,

  /// No matching product or variant was found in the catalog.
  noMatch,

  /// The input code failed structural validation (e.g. empty or illegal format).
  invalidIdentifier,

  /// The lookup was conducted offline and the requested identifier is not in cache.
  offlineMiss,

  /// The lookup failed due to network, database, or repository exceptions.
  error,
}

/// The specific mechanism or identifier category through which the match was established.
enum MatchMethod {
  exactBarcode,
  exactQr,
  exactInternal,
  exactSku,
  exactManufacturer,
  exactSupplier,
  exactAlternateSku,
  legacyBarcodeFallback,
  searchIndexMatch,
  unknown,
}

/// Incoming request to identify a product from a scanned code or manual entry.
@immutable
class ProductIdentificationRequest {
  /// The raw, unmutated string exactly as received from scanner or input.
  final String rawIdentifier;

  /// Authenticated tenant/business identifier. Required for tenant isolation.
  final String tenantId;

  /// Optional specific store or warehouse location.
  final String? locationId;

  /// Optional identifier type hint if known ahead of time.
  final String? identifierTypeHint;

  /// The physical or logical origin of the scan.
  final ScannerSource scannerSource;

  /// The symbology format of the barcode if recognized by the scanner.
  final SmartBarcodeFormat barcodeFormat;

  /// Optional hardware or terminal device identifier.
  final String? deviceId;

  /// If true, the engine bypasses remote network calls and checks offline cache only.
  final bool forceOffline;

  /// Timestamp when the request was initiated.
  final DateTime timestamp;

  /// Optional arbitrary metadata passed along from scanner.
  final Map<String, dynamic> metadata;

  ProductIdentificationRequest({
    required this.rawIdentifier,
    required this.tenantId,
    this.locationId,
    this.identifierTypeHint,
    this.scannerSource = ScannerSource.manual,
    this.barcodeFormat = SmartBarcodeFormat.unknown,
    this.deviceId,
    this.forceOffline = false,
    DateTime? timestamp,
    this.metadata = const <String, dynamic>{},
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates an identification request directly from a Phase 1 [SmartScanResult].
  factory ProductIdentificationRequest.fromScanResult(
    SmartScanResult scan, {
    required String tenantId,
    String? locationId,
    bool forceOffline = false,
  }) {
    return ProductIdentificationRequest(
      rawIdentifier: scan.rawValue,
      tenantId: tenantId,
      locationId: locationId,
      scannerSource: scan.source,
      barcodeFormat: scan.format,
      deviceId: scan.deviceId,
      forceOffline: forceOffline,
      timestamp: scan.timestamp,
      metadata: {
        if (scan.sessionId != null) 'session_id': scan.sessionId!,
        'normalized_value': scan.normalizedValue,
      },
    );
  }

  /// Clones the request with optional field replacements.
  ProductIdentificationRequest copyWith({
    String? rawIdentifier,
    String? tenantId,
    String? locationId,
    String? identifierTypeHint,
    ScannerSource? scannerSource,
    SmartBarcodeFormat? barcodeFormat,
    String? deviceId,
    bool? forceOffline,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return ProductIdentificationRequest(
      rawIdentifier: rawIdentifier ?? this.rawIdentifier,
      tenantId: tenantId ?? this.tenantId,
      locationId: locationId ?? this.locationId,
      identifierTypeHint: identifierTypeHint ?? this.identifierTypeHint,
      scannerSource: scannerSource ?? this.scannerSource,
      barcodeFormat: barcodeFormat ?? this.barcodeFormat,
      deviceId: deviceId ?? this.deviceId,
      forceOffline: forceOffline ?? this.forceOffline,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'raw_identifier': rawIdentifier,
      'tenant_id': tenantId,
      'scanner_source': scannerSource.name,
      'barcode_format': barcodeFormat.name,
      'force_offline': forceOffline,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
    if (locationId != null) map['location_id'] = locationId!;
    if (identifierTypeHint != null) {
      map['identifier_type_hint'] = identifierTypeHint!;
    }
    if (deviceId != null) map['device_id'] = deviceId!;
    return map;
  }

  @override
  String toString() =>
      'ProductIdentificationRequest(rawIdentifier: $rawIdentifier, tenant: $tenantId, source: ${scannerSource.name})';
}

/// An individual matched product and variant candidate resolved by the identification engine.
@immutable
class ProductIdentificationMatch {
  final String productId;
  final String variantId;
  final String productName;
  final String variantName;
  final String sku;
  final String? barcode;
  final String? partNumber;
  final String? brandName;
  final String? categoryName;
  final String unitCode;
  final String unitName;
  final double sellingPrice;
  final double? costPrice;
  final double stockQuantity;
  final MatchMethod matchMethod;
  final String matchedCode;
  final String? matchedIdentifierType;
  final double confidence;
  final List<ProductIdentifier> identifiers;
  final Map<String, dynamic> rawPayload;

  const ProductIdentificationMatch({
    required this.productId,
    required this.variantId,
    required this.productName,
    this.variantName = '',
    required this.sku,
    this.barcode,
    this.partNumber,
    this.brandName,
    this.categoryName,
    this.unitCode = 'PCS',
    this.unitName = 'Pieces',
    this.sellingPrice = 0.0,
    this.costPrice,
    this.stockQuantity = 0.0,
    required this.matchMethod,
    required this.matchedCode,
    this.matchedIdentifierType,
    this.confidence = 1.0,
    this.identifiers = const <ProductIdentifier>[],
    this.rawPayload = const <String, dynamic>{},
  });

  /// Instantiates a match from the payload format returned by THQ RPCs
  /// (`inventory_product_lookup_v482` / `inventory_list_products_v482`).
  factory ProductIdentificationMatch.fromRpcMap(
    Map<String, dynamic> map, {
    required MatchMethod matchMethod,
    required String matchedCode,
    String? matchedIdentifierType,
    double confidence = 1.0,
  }) {
    final identifiersList = (map['identifiers'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => ProductIdentifier.fromMap(Map<String, dynamic>.from(e)))
        .toList();

    double parseNum(dynamic value, [double fallback = 0.0]) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    return ProductIdentificationMatch(
      productId: map['product_id']?.toString() ??
          map['id']?.toString() ??
          map['productId']?.toString() ??
          '',
      variantId: map['variant_id']?.toString() ??
          map['variantId']?.toString() ??
          map['id']?.toString() ??
          '',
      productName: map['product_name']?.toString() ??
          map['name']?.toString() ??
          map['productName']?.toString() ??
          '',
      variantName: map['variant_name']?.toString() ??
          map['variantName']?.toString() ??
          '',
      sku: map['sku']?.toString() ?? '',
      barcode: map['barcode']?.toString(),
      partNumber: map['part_number']?.toString() ?? map['partNumber']?.toString(),
      brandName: map['brand_name']?.toString() ??
          map['brand']?.toString() ??
          map['brandName']?.toString(),
      categoryName: map['category_name']?.toString() ??
          map['category']?.toString() ??
          map['categoryName']?.toString(),
      unitCode: map['unit_code']?.toString() ??
          map['base_unit_code']?.toString() ??
          'PCS',
      unitName: map['unit_name']?.toString() ??
          map['base_unit_name']?.toString() ??
          'Pieces',
      sellingPrice: parseNum(map['selling_price'] ?? map['sale_price']),
      costPrice: map['cost_price'] != null || map['purchase_cost'] != null
          ? parseNum(map['cost_price'] ?? map['purchase_cost'])
          : null,
      stockQuantity: parseNum(map['stock_quantity'] ?? map['available_qty']),
      matchMethod: matchMethod,
      matchedCode: matchedCode,
      matchedIdentifierType: matchedIdentifierType,
      confidence: confidence,
      identifiers: identifiersList,
      rawPayload: Map<String, dynamic>.unmodifiable(map),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'product_id': productId,
      'variant_id': variantId,
      'product_name': productName,
      'variant_name': variantName,
      'sku': sku,
      'unit_code': unitCode,
      'unit_name': unitName,
      'selling_price': sellingPrice,
      'stock_quantity': stockQuantity,
      'match_method': matchMethod.name,
      'matched_code': matchedCode,
      'confidence': confidence,
    };
    if (barcode != null) map['barcode'] = barcode!;
    if (partNumber != null) map['part_number'] = partNumber!;
    if (brandName != null) map['brand_name'] = brandName!;
    if (categoryName != null) map['category_name'] = categoryName!;
    if (costPrice != null) map['cost_price'] = costPrice!;
    if (matchedIdentifierType != null) {
      map['matched_identifier_type'] = matchedIdentifierType!;
    }
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductIdentificationMatch &&
          runtimeType == other.runtimeType &&
          productId == other.productId &&
          variantId == other.variantId &&
          matchedCode == other.matchedCode;

  @override
  int get hashCode =>
      productId.hashCode ^ variantId.hashCode ^ matchedCode.hashCode;

  @override
  String toString() =>
      'ProductIdentificationMatch($productName [$sku], variant: $variantId, via: ${matchMethod.name})';
}

/// Comprehensive result emitted by [ProductIdentificationEngine].
@immutable
class ProductIdentificationResult {
  /// The operational outcome status.
  final ProductIdentificationStatus status;

  /// The request that produced this result.
  final ProductIdentificationRequest request;

  /// All identified candidates matching the query.
  final List<ProductIdentificationMatch> matches;

  /// Optional error or diagnostic message when status is [ProductIdentificationStatus.error].
  final String? errorMessage;

  /// Diagnostic telemetry (latency, repositories checked, timestamps).
  final Map<String, dynamic> diagnostics;

  const ProductIdentificationResult({
    required this.status,
    required this.request,
    this.matches = const <ProductIdentificationMatch>[],
    this.errorMessage,
    this.diagnostics = const <String, dynamic>{},
  });

  /// Convenience helper to access the single resolved match when [isExact] is true.
  ProductIdentificationMatch? get primaryMatch =>
      status == ProductIdentificationStatus.exactMatch && matches.isNotEmpty
          ? matches.first
          : null;

  /// True if a single definitive product was identified.
  bool get isExact => status == ProductIdentificationStatus.exactMatch;

  /// True if multiple products matched and operator selection is required.
  bool get isAmbiguous =>
      status == ProductIdentificationStatus.multipleMatches;

  /// True if no product was found in any consulted repository.
  bool get isNotFound =>
      status == ProductIdentificationStatus.noMatch ||
      status == ProductIdentificationStatus.offlineMiss;

  /// True if an error occurred during lookup.
  bool get hasError => status == ProductIdentificationStatus.error;

  /// Convenience factory for exact match.
  factory ProductIdentificationResult.exactMatch({
    required ProductIdentificationRequest request,
    required ProductIdentificationMatch match,
    Map<String, dynamic> diagnostics = const {},
  }) {
    return ProductIdentificationResult(
      status: ProductIdentificationStatus.exactMatch,
      request: request,
      matches: [match],
      diagnostics: diagnostics,
    );
  }

  /// Convenience factory for ambiguous / multiple matches.
  factory ProductIdentificationResult.multipleMatches({
    required ProductIdentificationRequest request,
    required List<ProductIdentificationMatch> matches,
    Map<String, dynamic> diagnostics = const {},
  }) {
    return ProductIdentificationResult(
      status: ProductIdentificationStatus.multipleMatches,
      request: request,
      matches: matches,
      diagnostics: diagnostics,
    );
  }

  /// Convenience factory for not found.
  factory ProductIdentificationResult.noMatch({
    required ProductIdentificationRequest request,
    Map<String, dynamic> diagnostics = const {},
  }) {
    return ProductIdentificationResult(
      status: ProductIdentificationStatus.noMatch,
      request: request,
      matches: const [],
      diagnostics: diagnostics,
    );
  }

  /// Convenience factory for offline cache miss.
  factory ProductIdentificationResult.offlineMiss({
    required ProductIdentificationRequest request,
    Map<String, dynamic> diagnostics = const {},
  }) {
    return ProductIdentificationResult(
      status: ProductIdentificationStatus.offlineMiss,
      request: request,
      matches: const [],
      diagnostics: diagnostics,
    );
  }

  /// Convenience factory for validation error on the identifier.
  factory ProductIdentificationResult.invalidIdentifier({
    required ProductIdentificationRequest request,
    required String reason,
    Map<String, dynamic> diagnostics = const {},
  }) {
    return ProductIdentificationResult(
      status: ProductIdentificationStatus.invalidIdentifier,
      request: request,
      matches: const [],
      errorMessage: reason,
      diagnostics: diagnostics,
    );
  }

  /// Convenience factory for technical or network error.
  factory ProductIdentificationResult.error({
    required ProductIdentificationRequest request,
    required String message,
    Map<String, dynamic> diagnostics = const {},
  }) {
    return ProductIdentificationResult(
      status: ProductIdentificationStatus.error,
      request: request,
      matches: const [],
      errorMessage: message,
      diagnostics: diagnostics,
    );
  }

  @override
  String toString() =>
      'ProductIdentificationResult(status: ${status.name}, matches: ${matches.length}, error: $errorMessage)';
}

/// Configuration settings controlling lookup rules, priorities, and fallback strategies.
@immutable
class ProductIdentificationConfiguration {
  /// Ordered list of identifier types to search against.
  /// Standard THQ types: barcode, qr, internal, sku, manufacturer, supplier, alternate_sku.
  final List<String> lookupPriority;

  /// Whether to trim outer whitespace before looking up codes. (Defaults to true).
  final bool trimWhitespace;

  /// If false, partial or fuzzy text matching is strictly disabled.
  /// Billing and inventory operations should always keep this false.
  final bool allowFuzzyMatching;

  /// If multiple matches occur, require the caller to perform disambiguation.
  final bool requireSelectionOnAmbiguity;

  /// Prefer online database lookup if connection is available.
  final bool preferOnline;

  /// Minimum code length to attempt resolution.
  final int minCodeLength;

  const ProductIdentificationConfiguration({
    this.lookupPriority = const <String>[
      'barcode',
      'qr',
      'internal',
      'sku',
      'manufacturer',
      'supplier',
      'alternate_sku',
    ],
    this.trimWhitespace = true,
    this.allowFuzzyMatching = false,
    this.requireSelectionOnAmbiguity = true,
    this.preferOnline = true,
    this.minCodeLength = 1,
  });

  /// Default production configuration ensuring exact, safe lookups.
  static const ProductIdentificationConfiguration standard =
      ProductIdentificationConfiguration();

  ProductIdentificationConfiguration copyWith({
    List<String>? lookupPriority,
    bool? trimWhitespace,
    bool? allowFuzzyMatching,
    bool? requireSelectionOnAmbiguity,
    bool? preferOnline,
    int? minCodeLength,
  }) {
    return ProductIdentificationConfiguration(
      lookupPriority: lookupPriority ?? this.lookupPriority,
      trimWhitespace: trimWhitespace ?? this.trimWhitespace,
      allowFuzzyMatching: allowFuzzyMatching ?? this.allowFuzzyMatching,
      requireSelectionOnAmbiguity:
          requireSelectionOnAmbiguity ?? this.requireSelectionOnAmbiguity,
      preferOnline: preferOnline ?? this.preferOnline,
      minCodeLength: minCodeLength ?? this.minCodeLength,
    );
  }
}
