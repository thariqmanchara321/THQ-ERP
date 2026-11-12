import 'external_product_models.dart';

/// Provider-independent contract for external product catalogue and intelligence lookup services.
abstract class ExternalProductIntelligenceProvider {
  /// Unique machine-readable identifier for this provider (e.g. 'open_food_facts', 'gs1_grp').
  String get id;

  /// User-friendly display title.
  String get displayName;

  /// Detailed description of the source data, licensing, and coverage.
  String get description;

  /// True if this provider requires paid or registered API credentials to function.
  bool get requiresCredentials;

  /// True if the provider is properly configured with any required credentials.
  bool get isConfigured;

  /// True if this provider queries official GS1 Registry Platform (GRP) data directly.
  bool get isOfficialGs1;

  /// Looks up a product candidate by exact barcode / GTIN.
  Future<ExternalLookupResult> lookupBarcode(
    String barcode, {
    String? tenantId,
    Duration timeout = const Duration(seconds: 8),
  });

  /// Searches for matching candidates by text query (name, brand, part number).
  Future<ExternalLookupResult> search(
    ExternalLookupRequest request,
  );
}
