import 'package:flutter/foundation.dart';

import '../scanner/scanner_models.dart';

/// Operational outcome status of an external product intelligence query.
enum ExternalLookupStatus {
  /// Matching candidate(s) successfully returned from external source.
  success,

  /// External source searched successfully, but no matching product was found.
  noMatch,

  /// External API request rate-limit or quota exceeded (e.g. HTTP 429).
  rateLimited,

  /// Technical failure or network error communicating with external provider.
  providerError,

  /// System is offline or device network connection is unavailable.
  offline,

  /// External provider requires paid or registered API credentials that are not configured.
  unauthorized;

  String get label => switch (this) {
        ExternalLookupStatus.success => 'Product Found',
        ExternalLookupStatus.noMatch => 'No External Match',
        ExternalLookupStatus.rateLimited => 'Rate Limit Exceeded',
        ExternalLookupStatus.providerError => 'Provider Error',
        ExternalLookupStatus.offline => 'Network Offline',
        ExternalLookupStatus.unauthorized => 'Credentials Required',
      };
}

/// A product candidate discovered from an external catalogue or GS1 registry.
@immutable
class ExternalProductCandidate {
  /// Unique identifier of the provider that returned this candidate (e.g. 'open_food_facts', 'gs1_grp').
  final String providerId;

  /// Human-friendly name of the external data source (e.g. 'Open Food Facts (Public ODbL)', 'Verified by GS1').
  final String sourceName;

  /// The exact barcode string, preserving all leading zeros.
  final String barcode;

  /// Inferred or validated barcode symbology.
  final SmartBarcodeFormat format;

  /// Discovered product title / name.
  final String productName;

  /// User-friendly alias for productName.
  String get name => productName;

  /// Checks if candidate matches the given barcode, tolerating leading zeros.
  bool hasBarcode(String code) {
    final clean = code.trim();
    if (clean.isEmpty) return false;
    if (barcode == clean) return true;
    final b1 = barcode.replaceFirst(RegExp(r'^0+'), '');
    final b2 = clean.replaceFirst(RegExp(r'^0+'), '');
    return b1.isNotEmpty && b1 == b2;
  }

  /// Discovered brand or commercial trade name.
  final String? brand;

  /// Discovered manufacturer or legal entity name.
  final String? manufacturer;

  /// Model number or manufacturer part number (MPN).
  final String? modelOrPartNumber;

  /// Primary category, global product classification (GPC), or taxonomy.
  final String? category;

  /// Detailed marketing, packaging, or product description.
  final String? description;

  /// Legitimately hosted public product image URL, if available.
  final String? imageUrl;

  /// Key-value product specifications (e.g. weight, volume, ingredients, packaging, dimensions).
  final Map<String, String> specifications;

  /// Confidence score between 0.0 and 1.0 indicating match certainty.
  /// 1.0 represents an exact GTIN barcode match; 0.5-0.9 represents fuzzy text/brand matches.
  final double matchConfidence;

  /// Whether this product record was validated directly against official GS1 registry records.
  final bool isGs1Verified;

  /// Timestamp when this candidate was retrieved.
  final DateTime fetchedAt;

  /// Raw JSON payload received from the external provider for provenance and audit trails.
  final Map<String, dynamic> rawPayload;

  const ExternalProductCandidate({
    required this.providerId,
    required this.sourceName,
    required this.barcode,
    required this.format,
    required this.productName,
    this.brand,
    this.manufacturer,
    this.modelOrPartNumber,
    this.category,
    this.description,
    this.imageUrl,
    this.specifications = const <String, String>{},
    this.matchConfidence = 1.0,
    this.isGs1Verified = false,
    required this.fetchedAt,
    this.rawPayload = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'sourceName': sourceName,
        'barcode': barcode,
        'format': format.name,
        'productName': productName,
        'brand': brand,
        'manufacturer': manufacturer,
        'modelOrPartNumber': modelOrPartNumber,
        'category': category,
        'description': description,
        'imageUrl': imageUrl,
        'specifications': specifications,
        'matchConfidence': matchConfidence,
        'isGs1Verified': isGs1Verified,
        'fetchedAt': fetchedAt.toIso8601String(),
        'rawPayload': rawPayload,
      };

  factory ExternalProductCandidate.fromJson(Map<String, dynamic> map) {
    return ExternalProductCandidate(
      providerId: map['providerId']?.toString() ?? 'unknown',
      sourceName: map['sourceName']?.toString() ?? 'External Source',
      barcode: map['barcode']?.toString() ?? '',
      format: SmartBarcodeFormat.fromRawName(map['format']?.toString() ?? ''),
      productName: map['productName']?.toString() ?? '',
      brand: map['brand']?.toString(),
      manufacturer: map['manufacturer']?.toString(),
      modelOrPartNumber: map['modelOrPartNumber']?.toString(),
      category: map['category']?.toString(),
      description: map['description']?.toString(),
      imageUrl: map['imageUrl']?.toString(),
      specifications: Map<String, String>.from(
        (map['specifications'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
      ),
      matchConfidence: (map['matchConfidence'] as num?)?.toDouble() ?? 1.0,
      isGs1Verified: map['isGs1Verified'] == true,
      fetchedAt: DateTime.tryParse(map['fetchedAt']?.toString() ?? '') ?? DateTime.now(),
      rawPayload: Map<String, dynamic>.from((map['rawPayload'] as Map?) ?? {}),
    );
  }

  @override
  String toString() =>
      'ExternalProductCandidate(barcode: $barcode, name: $productName, brand: $brand, source: $sourceName, conf: $matchConfidence, gs1: $isGs1Verified)';
}

/// Request parameters for looking up or searching external product intelligence.
@immutable
class ExternalLookupRequest {
  /// Barcode or GTIN (e.g. '8901234567890').
  final String? barcode;

  /// Optional text query to search by product name.
  final String? productName;

  /// Optional filter by brand.
  final String? brand;

  /// Optional filter by manufacturer part number.
  final String? partNumber;

  /// Active tenant business ID for isolation.
  final String tenantId;

  /// Optional store or warehouse location ID.
  final String? locationId;

  /// Specific provider IDs to query, or null to query all enabled providers.
  final List<String>? preferredProviders;

  /// Maximum network timeout duration.
  final Duration timeout;

  const ExternalLookupRequest({
    this.barcode,
    this.productName,
    this.brand,
    this.partNumber,
    this.tenantId = '',
    this.locationId,
    this.preferredProviders,
    this.timeout = const Duration(seconds: 8),
  });

  /// Factory for a strict barcode query.
  factory ExternalLookupRequest.byBarcode({
    required String barcode,
    String tenantId = '',
    String? locationId,
    Duration timeout = const Duration(seconds: 8),
  }) {
    return ExternalLookupRequest(
      barcode: barcode.trim(),
      tenantId: tenantId,
      locationId: locationId,
      timeout: timeout,
    );
  }
}

/// Aggregated or single-provider result from an external lookup operation.
@immutable
class ExternalLookupResult {
  /// Outcome status.
  final ExternalLookupStatus status;

  /// Discovered external product candidates, ordered by match confidence.
  final List<ExternalProductCandidate> candidates;

  /// Informative error or diagnostic message if query was not successful.
  final String? errorMessage;

  /// Identifier of the provider that produced this result.
  final String providerId;

  /// Wall-clock elapsed duration in milliseconds.
  final int elapsedMs;

  const ExternalLookupResult({
    required this.status,
    this.candidates = const <ExternalProductCandidate>[],
    this.errorMessage,
    required this.providerId,
    this.elapsedMs = 0,
  });

  bool get isSuccess => status == ExternalLookupStatus.success && candidates.isNotEmpty;
  bool get isNotFound => status == ExternalLookupStatus.noMatch;
  bool get hasError => status == ExternalLookupStatus.providerError || status == ExternalLookupStatus.rateLimited;
  bool get isUnauthorized => status == ExternalLookupStatus.unauthorized;

  ExternalProductCandidate? get primaryCandidate => candidates.isNotEmpty ? candidates.first : null;

  factory ExternalLookupResult.success({
    required String providerId,
    required List<ExternalProductCandidate> candidates,
    int elapsedMs = 0,
  }) {
    return ExternalLookupResult(
      status: ExternalLookupStatus.success,
      candidates: candidates,
      providerId: providerId,
      elapsedMs: elapsedMs,
    );
  }

  factory ExternalLookupResult.noMatch({
    required String providerId,
    String? barcode,
    int elapsedMs = 0,
  }) {
    return ExternalLookupResult(
      status: ExternalLookupStatus.noMatch,
      errorMessage: barcode != null ? 'No external product found for barcode $barcode.' : 'No matching external products found.',
      providerId: providerId,
      elapsedMs: elapsedMs,
    );
  }

  factory ExternalLookupResult.rateLimited({
    required String providerId,
    String? message,
    int elapsedMs = 0,
  }) {
    return ExternalLookupResult(
      status: ExternalLookupStatus.rateLimited,
      errorMessage: message ?? 'External provider request quota exceeded. Please try again later.',
      providerId: providerId,
      elapsedMs: elapsedMs,
    );
  }

  factory ExternalLookupResult.error({
    required String providerId,
    required String message,
    int elapsedMs = 0,
  }) {
    return ExternalLookupResult(
      status: ExternalLookupStatus.providerError,
      errorMessage: message,
      providerId: providerId,
      elapsedMs: elapsedMs,
    );
  }

  factory ExternalLookupResult.unauthorized({
    required String providerId,
    String? message,
    int elapsedMs = 0,
  }) {
    return ExternalLookupResult(
      status: ExternalLookupStatus.unauthorized,
      errorMessage: message ?? 'External provider requires credentials or subscription that is not configured.',
      providerId: providerId,
      elapsedMs: elapsedMs,
    );
  }

  factory ExternalLookupResult.offline({
    required String providerId,
    int elapsedMs = 0,
  }) {
    return ExternalLookupResult(
      status: ExternalLookupStatus.offline,
      errorMessage: 'Device is offline or external provider is unreachable.',
      providerId: providerId,
      elapsedMs: elapsedMs,
    );
  }
}

/// Represents an individual catalogue field compared between THQ ERP and external intelligence.
class CatalogueComparisonField {
  /// Standard field identifier (e.g. 'productName', 'brand', 'category', 'description').
  final String fieldKey;

  /// User-friendly display label (e.g. 'Product Name').
  final String fieldLabel;

  /// Existing value currently stored in THQ ERP (null or empty if new product).
  final String? currentValue;

  /// Value suggested by external intelligence.
  final String? externalValue;

  /// True if existing value is non-empty and differs meaningfully from the external suggestion.
  final bool isConflict;

  /// Whether the user has explicitly selected/approved this external value to enrich the catalogue.
  bool isAccepted;

  /// True if this field is protected against external modification (e.g. stock, cost price, selling price, tax).
  final bool isProtected;

  CatalogueComparisonField({
    required this.fieldKey,
    required this.fieldLabel,
    this.currentValue,
    this.externalValue,
    required this.isConflict,
    this.isAccepted = false,
    this.isProtected = false,
  });

  @override
  String toString() =>
      'ComparisonField($fieldKey: cur="$currentValue", ext="$externalValue", conflict=$isConflict, accepted=$isAccepted, protected=$isProtected)';
}

/// Side-by-side comparison between an existing THQ product record (or empty draft)
/// and a discovered [ExternalProductCandidate].
class CatalogueComparison {
  /// Existing THQ variant ID if this is an update, or null if creating a new product.
  final String? existingVariantId;

  /// Existing THQ product ID if available.
  final String? existingProductId;

  /// Existing THQ product name.
  final String? existingProductName;

  /// The external intelligence candidate chosen for comparison.
  final ExternalProductCandidate candidate;

  /// List of field-by-field comparisons.
  final List<CatalogueComparisonField> fields;

  CatalogueComparison({
    this.existingVariantId,
    this.existingProductId,
    this.existingProductName,
    required this.candidate,
    required this.fields,
  });

  /// True if this comparison corresponds to an existing product already in the THQ catalogue.
  bool get isExistingProduct => existingVariantId != null && existingVariantId!.isNotEmpty;

  /// True if any field exhibits a value conflict between existing data and external suggestions.
  bool get hasConflicts => fields.any((f) => f.isConflict);

  /// Total count of conflicting fields.
  int get conflictCount => fields.where((f) => f.isConflict).length;

  /// Total count of external fields accepted by the user.
  int get acceptedFieldsCount => fields.where((f) => f.isAccepted && !f.isProtected).length;

  /// Factory constructor to build a comparison between an existing product map and an external candidate.
  factory CatalogueComparison.build({
    Map<String, dynamic>? existingProduct,
    required ExternalProductCandidate candidate,
  }) {
    final curName = existingProduct?['name']?.toString() ?? existingProduct?['product_name']?.toString();
    final curBrand = existingProduct?['brand_name']?.toString() ?? existingProduct?['brand']?.toString();
    final curManufacturer = existingProduct?['manufacturer']?.toString();
    final curCategory = existingProduct?['category_name']?.toString() ?? existingProduct?['category']?.toString();
    final curPartNumber = existingProduct?['part_number']?.toString();
    final curDescription = existingProduct?['description']?.toString();
    final curBarcode = existingProduct?['barcode']?.toString();

    bool checkConflict(String? cur, String? ext) {
      if (cur == null || cur.trim().isEmpty) return false;
      if (ext == null || ext.trim().isEmpty) return false;
      return cur.trim().toLowerCase() != ext.trim().toLowerCase();
    }

    final fields = <CatalogueComparisonField>[
      CatalogueComparisonField(
        fieldKey: 'productName',
        fieldLabel: 'Product Name',
        currentValue: curName,
        externalValue: candidate.productName,
        isConflict: checkConflict(curName, candidate.productName),
        // If current is empty, default accept; if conflict, default reject until user approves
        isAccepted: (curName == null || curName.trim().isEmpty) && candidate.productName.trim().isNotEmpty,
      ),
      CatalogueComparisonField(
        fieldKey: 'brand',
        fieldLabel: 'Brand',
        currentValue: curBrand,
        externalValue: candidate.brand,
        isConflict: checkConflict(curBrand, candidate.brand),
        isAccepted: (curBrand == null || curBrand.trim().isEmpty) && (candidate.brand?.trim().isNotEmpty ?? false),
      ),
      CatalogueComparisonField(
        fieldKey: 'manufacturer',
        fieldLabel: 'Manufacturer',
        currentValue: curManufacturer,
        externalValue: candidate.manufacturer,
        isConflict: checkConflict(curManufacturer, candidate.manufacturer),
        isAccepted: (curManufacturer == null || curManufacturer.trim().isEmpty) && (candidate.manufacturer?.trim().isNotEmpty ?? false),
      ),
      CatalogueComparisonField(
        fieldKey: 'category',
        fieldLabel: 'Category',
        currentValue: curCategory,
        externalValue: candidate.category,
        isConflict: checkConflict(curCategory, candidate.category),
        isAccepted: (curCategory == null || curCategory.trim().isEmpty) && (candidate.category?.trim().isNotEmpty ?? false),
      ),
      CatalogueComparisonField(
        fieldKey: 'partNumber',
        fieldLabel: 'Model / Part Number',
        currentValue: curPartNumber,
        externalValue: candidate.modelOrPartNumber,
        isConflict: checkConflict(curPartNumber, candidate.modelOrPartNumber),
        isAccepted: (curPartNumber == null || curPartNumber.trim().isEmpty) && (candidate.modelOrPartNumber?.trim().isNotEmpty ?? false),
      ),
      CatalogueComparisonField(
        fieldKey: 'description',
        fieldLabel: 'Description',
        currentValue: curDescription,
        externalValue: candidate.description,
        isConflict: checkConflict(curDescription, candidate.description),
        isAccepted: (curDescription == null || curDescription.trim().isEmpty) && (candidate.description?.trim().isNotEmpty ?? false),
      ),
      CatalogueComparisonField(
        fieldKey: 'barcode',
        fieldLabel: 'Barcode / GTIN',
        currentValue: curBarcode,
        externalValue: candidate.barcode,
        isConflict: checkConflict(curBarcode, candidate.barcode),
        isAccepted: (curBarcode == null || curBarcode.trim().isEmpty) && candidate.barcode.trim().isNotEmpty,
      ),
      // Protected operational accounting invariants: explicitly flagged as protected
      CatalogueComparisonField(
        fieldKey: 'sellingPrice',
        fieldLabel: 'Selling Price',
        currentValue: existingProduct?['selling_price']?.toString(),
        externalValue: null,
        isConflict: false,
        isAccepted: false,
        isProtected: true,
      ),
      CatalogueComparisonField(
        fieldKey: 'costPrice',
        fieldLabel: 'Purchase / Cost Price',
        currentValue: existingProduct?['cost_price']?.toString(),
        externalValue: null,
        isConflict: false,
        isAccepted: false,
        isProtected: true,
      ),
      CatalogueComparisonField(
        fieldKey: 'stockQuantity',
        fieldLabel: 'Stock Quantity',
        currentValue: existingProduct?['quantity']?.toString() ?? existingProduct?['stock_on_hand']?.toString(),
        externalValue: null,
        isConflict: false,
        isAccepted: false,
        isProtected: true,
      ),
    ];

    return CatalogueComparison(
      existingVariantId: existingProduct?['variant_id']?.toString() ?? existingProduct?['id']?.toString(),
      existingProductId: existingProduct?['product_id']?.toString(),
      existingProductName: curName,
      candidate: candidate,
      fields: fields,
    );
  }

  /// Extracts the dictionary of user-accepted field modifications for updating or creating a product.
  Map<String, String?> buildEnrichmentPayload() {
    final payload = <String, String?>{};
    for (final field in fields) {
      if (field.isProtected) continue; // Never enrich protected fields
      if (field.isAccepted && field.externalValue != null && field.externalValue!.trim().isNotEmpty) {
        payload[field.fieldKey] = field.externalValue!.trim();
      }
    }
    return payload;
  }

  /// Checks whether a specific field key is currently accepted.
  bool isFieldAccepted(String fieldKey) {
    return fields.any((f) => f.fieldKey == fieldKey && f.isAccepted);
  }

  /// Sets user acceptance for a specific field key (no-op if field is protected).
  void setFieldAccepted(String fieldKey, bool accepted) {
    final idx = fields.indexWhere((f) => f.fieldKey == fieldKey);
    if (idx != -1 && !fields[idx].isProtected) {
      fields[idx].isAccepted = accepted;
    }
  }

  /// Builds provenance metadata suitable for storing in `custom_fields['external_provenance']`.
  Map<String, dynamic> buildAuditProvenance({required String approvedByUserId}) {
    return {
      'source_provider_id': candidate.providerId,
      'source_name': candidate.sourceName,
      'is_gs1_verified': candidate.isGs1Verified,
      'external_barcode': candidate.barcode,
      'approved_by_user_id': approvedByUserId,
      'enriched_at': DateTime.now().toIso8601String(),
      'accepted_fields': fields.where((f) => f.isAccepted && !f.isProtected).map((f) => f.fieldKey).toList(),
      'raw_source_payload': candidate.rawPayload,
    };
  }
}
