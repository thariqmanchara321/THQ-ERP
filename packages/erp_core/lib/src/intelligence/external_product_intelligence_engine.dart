import 'dart:async';

import '../scanner/barcode_accuracy_verifier.dart';
import 'external_product_intelligence_provider.dart';
import 'external_product_models.dart';
import 'gs1_registry_provider.dart';
import 'mock_external_product_provider.dart';
import 'open_product_facts_provider.dart';

class _CachedLookup {
  final List<ExternalProductCandidate> candidates;
  final DateTime cachedAt;
  final Duration ttl;

  _CachedLookup({
    required this.candidates,
    required this.cachedAt,
    this.ttl = const Duration(minutes: 15),
  });

  bool get isExpired => DateTime.now().difference(cachedAt) > ttl;
}

/// Central orchestrator for External Product Intelligence and GS1 barcode lookups.
///
/// Key Capabilities:
/// 1. **Provider-Independent Routing:** Dispatches queries across configured providers in parallel or priority order.
/// 2. **In-Flight Request Deduplication:** Prevents redundant concurrent requests when multiple scans arrive rapidly.
/// 3. **Time-Based Cache Layer:** Caches external candidate responses in-memory (default 15 minutes) to protect provider rate limits and ensure snappy local UX.
/// 4. **Side-by-Side Catalogue Comparison:** Compares external data against existing THQ records, highlighting conflicts and requiring explicit user field approval.
/// 5. **Catalogue Protection Guardrails:** Strictly prevents modification of inventory stock quantities, purchase/cost prices, selling prices, tax rates, or accounting ledger history.
class ExternalProductIntelligenceEngine {
  final List<ExternalProductIntelligenceProvider> _providers;
  final Map<String, _CachedLookup> _cache = {};
  final Map<String, Future<List<ExternalProductCandidate>>> _inFlight = {};
  final Duration defaultTimeout;
  final Duration cacheTtl;

  ExternalProductIntelligenceEngine({
    List<ExternalProductIntelligenceProvider>? providers,
    this.defaultTimeout = const Duration(seconds: 8),
    this.cacheTtl = const Duration(minutes: 15),
  }) : _providers = providers ??
            <ExternalProductIntelligenceProvider>[
              OpenProductFactsProvider(),
              Gs1RegistryProvider(),
            ];

  /// Standard factory pre-configured with default global open providers.
  factory ExternalProductIntelligenceEngine.standard() {
    return ExternalProductIntelligenceEngine(
      providers: [
        OpenProductFactsProvider(),
        Gs1RegistryProvider(),
      ],
    );
  }

  /// Hermetic testing factory pre-configured with the in-memory mock provider.
  factory ExternalProductIntelligenceEngine.mock({MockExternalProductProvider? mockProvider}) {
    return ExternalProductIntelligenceEngine(
      providers: [
        mockProvider ?? MockExternalProductProvider(),
        Gs1RegistryProvider(),
      ],
    );
  }

  /// Unmodifiable view of currently registered providers.
  List<ExternalProductIntelligenceProvider> get providers => List.unmodifiable(_providers);

  /// Current number of cached barcode lookups.
  int get cacheSize => _cache.length;

  /// Registers an additional product intelligence provider.
  void registerProvider(ExternalProductIntelligenceProvider provider) {
    if (!_providers.any((p) => p.id == provider.id)) {
      _providers.add(provider);
    }
  }

  /// Removes a provider by ID.
  void unregisterProvider(String providerId) {
    _providers.removeWhere((p) => p.id == providerId);
  }

  /// Clears in-memory lookup cache, returning the number of evicted items.
  int clearCache() {
    final count = _cache.length;
    _cache.clear();
    return count;
  }

  /// Looks up a product across all registered providers using its exact barcode string.
  ///
  /// Guarantees:
  /// - Exact string preservation (never parses barcode into integer).
  /// - Check digit validation performed before external queries.
  /// - Automatic caching and in-flight request coalescing.
  Future<List<ExternalProductCandidate>> lookupBarcode(
    String barcode, {
    String tenantId = '',
    String? locationId,
    Duration? timeout,
    bool bypassCache = false,
  }) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return const [];

    // 1. Format & check digit sanity verification
    final accuracy = BarcodeAccuracyVerifier.verify(rawValue: trimmed);
    if (!accuracy.isValid) {
      return const [];
    }

    final cacheKey = '$tenantId:$trimmed';

    // 2. Check local memory cache
    if (!bypassCache && _cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (!cached.isExpired) {
        return cached.candidates;
      } else {
        _cache.remove(cacheKey);
      }
    }

    // 3. In-flight request deduplication
    if (_inFlight.containsKey(cacheKey)) {
      return _inFlight[cacheKey]!;
    }

    final effectiveTimeout = timeout ?? defaultTimeout;

    final future = _executeMultiProviderLookup(
      trimmed,
      tenantId: tenantId,
      timeout: effectiveTimeout,
    );

    _inFlight[cacheKey] = future;

    try {
      final results = await future;
      _cache[cacheKey] = _CachedLookup(
        candidates: results,
        cachedAt: DateTime.now(),
        ttl: cacheTtl,
      );
      return results;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<List<ExternalProductCandidate>> _executeMultiProviderLookup(
    String barcode, {
    required String tenantId,
    required Duration timeout,
  }) async {
    final allCandidates = <ExternalProductCandidate>[];

    // Query active providers concurrently with timeout protection
    final futures = _providers.map((provider) async {
      try {
        final result = await provider.lookupBarcode(
          barcode,
          tenantId: tenantId,
          timeout: timeout,
        );
        if (result.isSuccess) {
          return result.candidates;
        }
      } catch (_) {
        // Individual provider technical errors should not fail entire pipeline
      }
      return <ExternalProductCandidate>[];
    });

    final providerResults = await Future.wait(futures);
    for (final list in providerResults) {
      allCandidates.addAll(list);
    }

    // Sort candidates: official GS1 verified records first, then by match confidence descending
    allCandidates.sort((a, b) {
      if (a.isGs1Verified != b.isGs1Verified) {
        return a.isGs1Verified ? -1 : 1;
      }
      return b.matchConfidence.compareTo(a.matchConfidence);
    });

    return allCandidates;
  }

  /// Searches for external products matching a text-based query (product name, brand, part number).
  Future<List<ExternalProductCandidate>> search(ExternalLookupRequest request) async {
    final allCandidates = <ExternalProductCandidate>[];

    final providersToQuery = request.preferredProviders != null
        ? _providers.where((p) => request.preferredProviders!.contains(p.id))
        : _providers;

    final futures = providersToQuery.map((p) async {
      try {
        final result = await p.search(request);
        if (result.isSuccess) {
          return result.candidates;
        }
      } catch (_) {}
      return <ExternalProductCandidate>[];
    });

    final results = await Future.wait(futures);
    for (final list in results) {
      allCandidates.addAll(list);
    }

    allCandidates.sort((a, b) => b.matchConfidence.compareTo(a.matchConfidence));
    return allCandidates;
  }

  /// Builds a [CatalogueComparison] comparing an external candidate against an existing THQ product map.
  CatalogueComparison compareWithCatalogue({
    required ExternalProductCandidate candidate,
    Map<String, dynamic>? existingProduct,
  }) {
    return CatalogueComparison.build(
      existingProduct: existingProduct,
      candidate: candidate,
    );
  }

  /// Builds an audit provenance metadata record for accepted external enrichment.
  ///
  /// This record is stored in `product_variants.custom_fields['external_provenance']`
  /// providing transparent traceability of where descriptive data originated.
  Map<String, dynamic> buildProvenanceRecord(
    ExternalProductCandidate candidate,
    Map<String, String?> acceptedFields,
  ) {
    return {
      'provider_id': candidate.providerId,
      'source_name': candidate.sourceName,
      'is_gs1_verified': candidate.isGs1Verified,
      'enriched_at': DateTime.now().toIso8601String(),
      'barcode': candidate.barcode,
      'accepted_fields': acceptedFields.keys.toList(),
      'confidence': candidate.matchConfidence,
    };
  }
}
