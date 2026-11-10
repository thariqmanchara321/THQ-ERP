import 'dart:async';

import 'identification_models.dart';

/// Generic RPC invoker signature enabling clean dependency injection across
/// Supabase, custom HTTP backends, or mock test harnesses without tying
/// `erp_core` to specific client libraries.
typedef RpcCaller = Future<dynamic> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

/// Core repository interface for finding products by barcode, QR, SKU, or custom identifiers.
abstract class ProductIdentificationRepository {
  /// Resolves an identifier string against the catalog within the given [tenantId] and [locationId].
  ///
  /// Returns a list of candidate matches. An empty list signifies that the identifier
  /// was not found in this repository.
  Future<List<ProductIdentificationMatch>> lookupIdentifier({
    required String tenantId,
    required String code,
    String? locationId,
    Set<String>? allowedTypes,
  });

  /// Direct lookup of a known variant by its primary UUID.
  Future<ProductIdentificationMatch?> lookupVariant({
    required String tenantId,
    required String variantId,
    String? locationId,
  });
}

/// Specialized repository contract for offline stores (e.g. SQLite / in-memory cache).
abstract class OfflineProductIdentificationRepository
    implements ProductIdentificationRepository {
  /// Checks whether local offline cache is populated and ready for queries.
  Future<bool> isOfflineDataAvailable({
    required String tenantId,
    String? locationId,
  });
}

/// Official Supabase RPC implementation of [ProductIdentificationRepository].
///
/// Calls the canonical `inventory_product_lookup_v482` PostgreSQL RPC function.
class RpcProductIdentificationRepository
    implements ProductIdentificationRepository {
  final RpcCaller _rpc;

  const RpcProductIdentificationRepository(this._rpc);

  @override
  Future<List<ProductIdentificationMatch>> lookupIdentifier({
    required String tenantId,
    required String code,
    String? locationId,
    Set<String>? allowedTypes,
  }) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return const [];

    try {
      final params = <String, dynamic>{
        'p_tenant_id': tenantId,
        'p_code': cleanCode,
      };
      if (locationId != null) {
        params['p_location_id'] = locationId;
      }

      final response = await _rpc(
        'inventory_product_lookup_v482',
        params: params,
      );

      if (response == null || response is! Map || response.isEmpty) {
        return const [];
      }

      final map = Map<String, dynamic>.from(response);
      final variantId = map['variant_id']?.toString() ??
          map['variantId']?.toString() ??
          '';

      if (variantId.isEmpty) {
        return const [];
      }

      // Determine the specific match method from the matched payload
      final matchMethod = _resolveMatchMethod(map, cleanCode);
      final match = ProductIdentificationMatch.fromRpcMap(
        map,
        matchMethod: matchMethod,
        matchedCode: cleanCode,
      );

      return [match];
    } catch (e) {
      // Allow caller/engine to classify technical failures vs not-found
      throw RepositoryException('RPC lookup failed for code "$code": $e', e);
    }
  }

  @override
  Future<ProductIdentificationMatch?> lookupVariant({
    required String tenantId,
    required String variantId,
    String? locationId,
  }) async {
    final matches = await lookupIdentifier(
      tenantId: tenantId,
      code: variantId,
      locationId: locationId,
    );
    return matches.isNotEmpty ? matches.first : null;
  }

  MatchMethod _resolveMatchMethod(Map<String, dynamic> map, String code) {
    final lowerCode = code.toLowerCase();
    final sku = map['sku']?.toString().toLowerCase().trim() ?? '';
    if (sku == lowerCode) return MatchMethod.exactSku;

    final barcode = map['barcode']?.toString().toLowerCase().trim() ?? '';
    if (barcode == lowerCode) return MatchMethod.exactBarcode;

    final partNumber =
        map['part_number']?.toString().toLowerCase().trim() ?? '';
    if (partNumber == lowerCode) return MatchMethod.exactManufacturer;

    final identifiers = map['identifiers'] as List? ?? const [];
    for (final item in identifiers) {
      if (item is Map) {
        final idCode = item['code']?.toString().toLowerCase().trim() ?? '';
        if (idCode == lowerCode) {
          final type = item['type']?.toString().toLowerCase() ??
              item['identifier_type']?.toString().toLowerCase();
          switch (type) {
            case 'barcode':
              return MatchMethod.exactBarcode;
            case 'qr':
              return MatchMethod.exactQr;
            case 'internal':
              return MatchMethod.exactInternal;
            case 'manufacturer':
              return MatchMethod.exactManufacturer;
            case 'supplier':
              return MatchMethod.exactSupplier;
            case 'alternate_sku':
              return MatchMethod.exactAlternateSku;
          }
        }
      }
    }

    if (code.startsWith('THQ:PRODUCT:')) return MatchMethod.exactQr;
    return MatchMethod.searchIndexMatch;
  }
}

/// Offline / in-memory implementation that queries local product collections,
/// such as those cached in SQLite (`offline_products`) by POS or Mobile POS.
class LocalProductIdentificationRepository
    implements OfflineProductIdentificationRepository {
  /// Provider callback fetching raw cached product payloads for a location.
  final FutureOr<List<Map<String, dynamic>>> Function(
    String tenantId,
    String? locationId,
  ) _productProvider;

  const LocalProductIdentificationRepository(this._productProvider);

  /// Helper factory using a static in-memory list of product payloads.
  factory LocalProductIdentificationRepository.fromStatic(
    List<Map<String, dynamic>> products,
  ) {
    return LocalProductIdentificationRepository((_, _) => products);
  }

  @override
  Future<bool> isOfflineDataAvailable({
    required String tenantId,
    String? locationId,
  }) async {
    try {
      final list = await _productProvider(tenantId, locationId);
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<ProductIdentificationMatch>> lookupIdentifier({
    required String tenantId,
    required String code,
    String? locationId,
    Set<String>? allowedTypes,
  }) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return const [];
    final lowerCode = cleanCode.toLowerCase();

    final products = await _productProvider(tenantId, locationId);
    final results = <ProductIdentificationMatch>[];

    for (final raw in products) {
      final map = Map<String, dynamic>.from(raw);
      MatchMethod? matchMethod;
      String? matchedType;

      // 1. Direct SKU check
      final sku = map['sku']?.toString().trim() ?? '';
      if (sku.toLowerCase() == lowerCode) {
        matchMethod = MatchMethod.exactSku;
        matchedType = 'sku';
      }

      // 2. Direct Barcode check
      if (matchMethod == null) {
        final barcode = map['barcode']?.toString().trim() ?? '';
        if (barcode.toLowerCase() == lowerCode) {
          matchMethod = MatchMethod.exactBarcode;
          matchedType = 'barcode';
        }
      }

      // 3. Direct Part Number / Manufacturer check
      if (matchMethod == null) {
        final partNumber = (map['part_number'] ?? map['partNumber'])
            ?.toString()
            .trim() ??
            '';
        if (partNumber.toLowerCase() == lowerCode) {
          matchMethod = MatchMethod.exactManufacturer;
          matchedType = 'manufacturer';
        }
      }

      // 4. Identifiers array check
      if (matchMethod == null) {
        final idList = map['identifiers'] as List? ?? const [];
        for (final item in idList) {
          if (item is Map) {
            final active = item['active'] != false;
            final itemCode = item['code']?.toString().trim() ?? '';
            if (active && itemCode.toLowerCase() == lowerCode) {
              final type = (item['type'] ?? item['identifier_type'])
                  ?.toString()
                  .toLowerCase()
                  .trim();
              matchedType = type;
              switch (type) {
                case 'barcode':
                  matchMethod = MatchMethod.exactBarcode;
                  break;
                case 'qr':
                  matchMethod = MatchMethod.exactQr;
                  break;
                case 'internal':
                  matchMethod = MatchMethod.exactInternal;
                  break;
                case 'manufacturer':
                  matchMethod = MatchMethod.exactManufacturer;
                  break;
                case 'supplier':
                  matchMethod = MatchMethod.exactSupplier;
                  break;
                case 'alternate_sku':
                  matchMethod = MatchMethod.exactAlternateSku;
                  break;
                default:
                  matchMethod = MatchMethod.searchIndexMatch;
              }
              break;
            }
          }
        }
      }

      // 5. Search codes check
      if (matchMethod == null) {
        final searchCodes = map['search_codes']?.toString() ?? '';
        if (searchCodes.isNotEmpty) {
          final tokens = searchCodes.split(' ');
          if (tokens.any((t) => t.trim().toLowerCase() == lowerCode)) {
            matchMethod = MatchMethod.searchIndexMatch;
          }
        }
      }

      if (matchMethod != null) {
        results.add(
          ProductIdentificationMatch.fromRpcMap(
            map,
            matchMethod: matchMethod,
            matchedCode: cleanCode,
            matchedIdentifierType: matchedType,
          ),
        );
      }
    }

    return results;
  }

  @override
  Future<ProductIdentificationMatch?> lookupVariant({
    required String tenantId,
    required String variantId,
    String? locationId,
  }) async {
    final products = await _productProvider(tenantId, locationId);
    for (final raw in products) {
      final map = Map<String, dynamic>.from(raw);
      final id = map['variant_id']?.toString() ??
          map['variantId']?.toString() ??
          '';
      if (id == variantId) {
        return ProductIdentificationMatch.fromRpcMap(
          map,
          matchMethod: MatchMethod.exactInternal,
          matchedCode: variantId,
        );
      }
    }
    return null;
  }
}

/// Fallback orchestrator that balances online server queries and offline local cache.
class CompositeProductIdentificationRepository
    implements ProductIdentificationRepository {
  final ProductIdentificationRepository onlineRepository;
  final OfflineProductIdentificationRepository offlineRepository;
  final bool preferOnline;

  const CompositeProductIdentificationRepository({
    required this.onlineRepository,
    required this.offlineRepository,
    this.preferOnline = true,
  });

  @override
  Future<List<ProductIdentificationMatch>> lookupIdentifier({
    required String tenantId,
    required String code,
    String? locationId,
    Set<String>? allowedTypes,
  }) async {
    if (preferOnline) {
      try {
        final onlineMatches = await onlineRepository.lookupIdentifier(
          tenantId: tenantId,
          code: code,
          locationId: locationId,
          allowedTypes: allowedTypes,
        );
        if (onlineMatches.isNotEmpty) {
          return onlineMatches;
        }
      } catch (onlineError) {
        // Fall back to offline store if online query encounters a network/RPC failure
        if (await offlineRepository.isOfflineDataAvailable(
          tenantId: tenantId,
          locationId: locationId,
        )) {
          return offlineRepository.lookupIdentifier(
            tenantId: tenantId,
            code: code,
            locationId: locationId,
            allowedTypes: allowedTypes,
          );
        }
        rethrow;
      }

      // If online lookup succeeded with empty result, also check offline before concluding
      return offlineRepository.lookupIdentifier(
        tenantId: tenantId,
        code: code,
        locationId: locationId,
        allowedTypes: allowedTypes,
      );
    } else {
      // Offline first strategy
      final offlineMatches = await offlineRepository.lookupIdentifier(
        tenantId: tenantId,
        code: code,
        locationId: locationId,
        allowedTypes: allowedTypes,
      );
      if (offlineMatches.isNotEmpty) {
        return offlineMatches;
      }
      return onlineRepository.lookupIdentifier(
        tenantId: tenantId,
        code: code,
        locationId: locationId,
        allowedTypes: allowedTypes,
      );
    }
  }

  @override
  Future<ProductIdentificationMatch?> lookupVariant({
    required String tenantId,
    required String variantId,
    String? locationId,
  }) async {
    if (preferOnline) {
      try {
        final result = await onlineRepository.lookupVariant(
          tenantId: tenantId,
          variantId: variantId,
          locationId: locationId,
        );
        if (result != null) return result;
      } catch (_) {
        return offlineRepository.lookupVariant(
          tenantId: tenantId,
          variantId: variantId,
          locationId: locationId,
        );
      }
      return offlineRepository.lookupVariant(
        tenantId: tenantId,
        variantId: variantId,
        locationId: locationId,
      );
    } else {
      final offlineResult = await offlineRepository.lookupVariant(
        tenantId: tenantId,
        variantId: variantId,
        locationId: locationId,
      );
      if (offlineResult != null) return offlineResult;
      return onlineRepository.lookupVariant(
        tenantId: tenantId,
        variantId: variantId,
        locationId: locationId,
      );
    }
  }
}

/// Generic exception thrown when a repository encounters an infrastructure or network fault.
class RepositoryException implements Exception {
  final String message;
  final Object? cause;

  const RepositoryException(this.message, [this.cause]);

  @override
  String toString() => 'RepositoryException: $message';
}
