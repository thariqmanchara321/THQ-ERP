import 'dart:async';

import '../scanner/scanner_models.dart';
import 'identification_models.dart';
import 'product_identification_repository.dart';

/// Reusable orchestrator that resolves scanned barcodes, QR codes, SKUs, and
/// custom part numbers into existing catalog products and variants.
class ProductIdentificationEngine {
  final ProductIdentificationRepository repository;
  final OfflineProductIdentificationRepository? offlineRepository;
  final ProductIdentificationConfiguration configuration;

  ProductIdentificationEngine({
    required this.repository,
    this.offlineRepository,
    this.configuration = ProductIdentificationConfiguration.standard,
  });

  /// High-level entrypoint that seamlessly connects a Phase 1 [SmartScanResult]
  /// with authenticated ERP business context to resolve the scanned product.
  Future<ProductIdentificationResult> identifyScan(
    SmartScanResult scan, {
    required String tenantId,
    String? locationId,
    String? deviceId,
    bool forceOffline = false,
  }) {
    final request = ProductIdentificationRequest.fromScanResult(
      scan,
      tenantId: tenantId,
      locationId: locationId,
      forceOffline: forceOffline,
    );
    return identify(request);
  }

  /// Primary identification workflow resolving any [ProductIdentificationRequest].
  Future<ProductIdentificationResult> identify(
    ProductIdentificationRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();

    // 1. Validation & Input Sanitization
    final raw = request.rawIdentifier;
    if (raw.isEmpty) {
      return ProductIdentificationResult.invalidIdentifier(
        request: request,
        reason: 'Scanned identifier cannot be empty.',
      );
    }

    final code = configuration.trimWhitespace ? raw.trim() : raw;
    if (code.isEmpty) {
      return ProductIdentificationResult.invalidIdentifier(
        request: request,
        reason: 'Scanned identifier contained only whitespace.',
      );
    }

    if (code.length < configuration.minCodeLength) {
      return ProductIdentificationResult.invalidIdentifier(
        request: request,
        reason:
            'Identifier length (${code.length}) is below minimum configured length (${configuration.minCodeLength}).',
      );
    }

    // 2. Offline routing check
    if (request.forceOffline) {
      return _executeOfflineLookup(request, code, stopwatch);
    }

    // 3. Online/standard repository execution
    try {
      final matches = await repository.lookupIdentifier(
        tenantId: request.tenantId,
        code: code,
        locationId: request.locationId,
      );
      stopwatch.stop();

      return _evaluateMatches(
        request: request,
        code: code,
        matches: matches,
        elapsedMs: stopwatch.elapsedMilliseconds,
        isOfflineLookup: false,
      );
    } on RepositoryException catch (re) {
      stopwatch.stop();
      // If repository throws an error, check if offline fallback is available
      if (offlineRepository != null) {
        final hasOffline = await offlineRepository!.isOfflineDataAvailable(
          tenantId: request.tenantId,
          locationId: request.locationId,
        );
        if (hasOffline) {
          return _executeOfflineLookup(request, code, stopwatch);
        }
      }

      return ProductIdentificationResult.error(
        request: request,
        message: re.message,
        diagnostics: {
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'error_type': 'RepositoryException',
          if (re.cause != null) 'cause': re.cause.toString(),
        },
      );
    } catch (e, stack) {
      stopwatch.stop();
      return ProductIdentificationResult.error(
        request: request,
        message: 'Unexpected error during product identification: $e',
        diagnostics: {
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'stack': stack.toString(),
        },
      );
    }
  }

  /// Internal handler for offline lookup requests.
  Future<ProductIdentificationResult> _executeOfflineLookup(
    ProductIdentificationRequest request,
    String code,
    Stopwatch stopwatch,
  ) async {
    final offlineRepo = offlineRepository;
    if (offlineRepo == null) {
      stopwatch.stop();
      return ProductIdentificationResult.offlineMiss(
        request: request,
        diagnostics: {
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'reason': 'No offline repository adapter configured on engine.',
        },
      );
    }

    try {
      final isAvailable = await offlineRepo.isOfflineDataAvailable(
        tenantId: request.tenantId,
        locationId: request.locationId,
      );

      if (!isAvailable) {
        stopwatch.stop();
        return ProductIdentificationResult.offlineMiss(
          request: request,
          diagnostics: {
            'elapsed_ms': stopwatch.elapsedMilliseconds,
            'reason': 'Offline catalog cache is unpopulated or empty.',
          },
        );
      }

      final matches = await offlineRepo.lookupIdentifier(
        tenantId: request.tenantId,
        code: code,
        locationId: request.locationId,
      );
      stopwatch.stop();

      return _evaluateMatches(
        request: request,
        code: code,
        matches: matches,
        elapsedMs: stopwatch.elapsedMilliseconds,
        isOfflineLookup: true,
      );
    } catch (e) {
      stopwatch.stop();
      return ProductIdentificationResult.error(
        request: request,
        message: 'Offline repository query error: $e',
        diagnostics: {
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'mode': 'offline',
        },
      );
    }
  }

  /// Evaluates candidates against lookup priorities and ambiguity rules.
  ProductIdentificationResult _evaluateMatches({
    required ProductIdentificationRequest request,
    required String code,
    required List<ProductIdentificationMatch> matches,
    required int elapsedMs,
    required bool isOfflineLookup,
  }) {
    final diagnostics = <String, dynamic>{
      'elapsed_ms': elapsedMs,
      'code_analyzed': code,
      'total_candidates': matches.length,
      'source': request.scannerSource.name,
      'is_offline': isOfflineLookup,
    };

    if (matches.isEmpty) {
      return isOfflineLookup
          ? ProductIdentificationResult.offlineMiss(
              request: request,
              diagnostics: diagnostics,
            )
          : ProductIdentificationResult.noMatch(
              request: request,
              diagnostics: diagnostics,
            );
    }

    // Deduplicate distinct candidates by variantId (or productId if missing variant)
    final candidateByVariant = <String, ProductIdentificationMatch>{};
    for (final match in matches) {
      final key = match.variantId.isNotEmpty ? match.variantId : match.productId;
      if (!candidateByVariant.containsKey(key)) {
        candidateByVariant[key] = match;
      }
    }

    final uniqueCandidates = candidateByVariant.values.toList();

    // Exactly one product resolved
    if (uniqueCandidates.length == 1) {
      return ProductIdentificationResult.exactMatch(
        request: request,
        match: uniqueCandidates.first,
        diagnostics: diagnostics,
      );
    }

    // Multiple candidates: Sort according to configured lookup priority
    uniqueCandidates.sort((a, b) {
      final rankA = _priorityRank(a.matchMethod);
      final rankB = _priorityRank(b.matchMethod);
      return rankA.compareTo(rankB);
    });

    final topRank = _priorityRank(uniqueCandidates.first.matchMethod);
    final topTier = uniqueCandidates
        .where((m) => _priorityRank(m.matchMethod) == topRank)
        .toList();

    // If the top priority tier unambiguously identifies 1 candidate, select it
    if (topTier.length == 1) {
      return ProductIdentificationResult.exactMatch(
        request: request,
        match: topTier.first,
        diagnostics: {
          ...diagnostics,
          'prioritized_over_lower_tiers': uniqueCandidates.length - 1,
        },
      );
    }

    // Genuine multiple match ambiguity across equal-priority candidates
    return ProductIdentificationResult.multipleMatches(
      request: request,
      matches: uniqueCandidates,
      diagnostics: {
        ...diagnostics,
        'requires_disambiguation': true,
      },
    );
  }

  /// Calculates numeric ranking according to the THQ identification priority hierarchy:
  /// 1. Exact Barcode
  /// 2. Exact QR
  /// 3. Exact Internal code
  /// 4. Exact SKU
  /// 5. Exact Manufacturer part number
  /// 6. Exact Supplier code
  /// 7. Exact Alternate SKU
  /// 8. Legacy Barcode fallback
  /// 9. Search index token match
  int _priorityRank(MatchMethod method) {
    switch (method) {
      case MatchMethod.exactBarcode:
        return 1;
      case MatchMethod.exactQr:
        return 2;
      case MatchMethod.exactInternal:
        return 3;
      case MatchMethod.exactSku:
        return 4;
      case MatchMethod.exactManufacturer:
        return 5;
      case MatchMethod.exactSupplier:
        return 6;
      case MatchMethod.exactAlternateSku:
        return 7;
      case MatchMethod.legacyBarcodeFallback:
        return 8;
      case MatchMethod.searchIndexMatch:
        return 9;
      case MatchMethod.unknown:
        return 10;
    }
  }
}
