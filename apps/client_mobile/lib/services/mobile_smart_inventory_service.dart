import 'dart:async';
import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/mobile_session.dart';

/// Client Mobile service providing access to the shared [ProductIdentificationEngine],
/// in-memory bulk scanning session state, and scan activity tracking.
///
/// Designed specifically for mobile constraints: safe online RPC lookup,
/// explicit offline boundary reporting, and non-mutating session collection.
class MobileSmartInventoryService {
  MobileSmartInventoryService._();
  static final MobileSmartInventoryService instance =
      MobileSmartInventoryService._();

  ProductIdentificationEngine? _engine;
  RpcCaller? _customRpc;

  /// Active bulk scanning session held in memory.
  SmartScanSession? _activeBulkSession;

  /// Completed bulk sessions recorded during the current app run.
  final List<SmartScanSession> _completedSessions = <SmartScanSession>[];

  /// Rolling feed of recent scan identification attempts (max 100).
  final List<ScanActivityLogEntry> _activityFeed = <ScanActivityLogEntry>[];

  /// Stream controller broadcasting recent scan events to active UI listeners.
  final StreamController<ScanActivityLogEntry> _activityStreamController =
      StreamController<ScanActivityLogEntry>.broadcast();

  Stream<ScanActivityLogEntry> get activityStream =>
      _activityStreamController.stream;

  List<ScanActivityLogEntry> get recentActivity =>
      List.unmodifiable(_activityFeed);

  SmartScanSession? get activeBulkSession => _activeBulkSession;

  List<SmartScanSession> get completedSessions =>
      List.unmodifiable(_completedSessions);

  /// Custom RPC injector for automated tests.
  void setCustomRpc(RpcCaller? rpc) {
    _customRpc = rpc;
    _engine = null; // Rebuild engine with custom repository
  }

  /// Lazy-initialized product identification engine backed by Supabase RPC.
  ProductIdentificationEngine get engine {
    if (_engine != null) return _engine!;

    final RpcCaller caller = _customRpc ??
        (fn, {params}) => Supabase.instance.client.rpc(fn, params: params);

    final onlineRepo = RpcProductIdentificationRepository(caller);

    _engine = ProductIdentificationEngine(
      repository: onlineRepo,
      configuration: ProductIdentificationConfiguration.standard,
    );
    return _engine!;
  }

  /// Resolves an incoming Phase 1 [SmartScanResult] using authenticated [MobileSession].
  Future<ProductIdentificationResult> identifyScan(
    SmartScanResult scan, {
    required MobileSession session,
    String? locationId,
    bool forceOffline = false,
  }) async {
    try {
      final result = await engine.identifyScan(
        scan,
        tenantId: session.tenantId,
        locationId: locationId ?? session.locationId,
        forceOffline: forceOffline,
      );

      _recordActivity(result);
      return result;
    } on SocketException catch (e) {
      final err = ProductIdentificationResult.error(
        request: ProductIdentificationRequest(
          rawIdentifier: scan.rawValue,
          tenantId: session.tenantId,
          locationId: locationId ?? session.locationId,
          scannerSource: scan.source,
          barcodeFormat: scan.format,
          forceOffline: forceOffline,
        ),
        message: 'No internet connection. Client Mobile requires live network access: ${e.message}',
      );
      _recordActivity(err);
      return err;
    } on TimeoutException {
      final err = ProductIdentificationResult.error(
        request: ProductIdentificationRequest(
          rawIdentifier: scan.rawValue,
          tenantId: session.tenantId,
          locationId: locationId ?? session.locationId,
          scannerSource: scan.source,
          barcodeFormat: scan.format,
          forceOffline: forceOffline,
        ),
        message: 'Network request timed out. Please verify connectivity and try again.',
      );
      _recordActivity(err);
      return err;
    } catch (e) {
      final err = ProductIdentificationResult.error(
        request: ProductIdentificationRequest(
          rawIdentifier: scan.rawValue,
          tenantId: session.tenantId,
          locationId: locationId ?? session.locationId,
          scannerSource: scan.source,
          barcodeFormat: scan.format,
          forceOffline: forceOffline,
        ),
        message: e.toString(),
      );
      _recordActivity(err);
      return err;
    }
  }

  /// Resolves a manual or programmatic identifier string.
  Future<ProductIdentificationResult> identifyCode(
    String code, {
    required MobileSession session,
    String? locationId,
    ScannerSource source = ScannerSource.manual,
    bool forceOffline = false,
  }) async {
    final cleanCode = code.trim();
    final request = ProductIdentificationRequest(
      rawIdentifier: cleanCode,
      tenantId: session.tenantId,
      locationId: locationId ?? session.locationId,
      scannerSource: source,
      forceOffline: forceOffline,
    );

    try {
      final result = await engine.identify(request);
      _recordActivity(result);
      return result;
    } on SocketException catch (e) {
      final err = ProductIdentificationResult.error(
        request: request,
        message: 'No internet connection. Client Mobile requires live network access: ${e.message}',
      );
      _recordActivity(err);
      return err;
    } on TimeoutException {
      final err = ProductIdentificationResult.error(
        request: request,
        message: 'Network request timed out. Please verify connectivity and try again.',
      );
      _recordActivity(err);
      return err;
    } catch (e) {
      final err = ProductIdentificationResult.error(
        request: request,
        message: e.toString(),
      );
      _recordActivity(err);
      return err;
    }
  }

  /// Multi-identifier catalog search querying products across names, SKUs, and barcodes.
  Future<List<ProductIdentificationMatch>> searchCatalog(
    String query, {
    required MobileSession session,
    String? locationId,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    try {
      final RpcCaller caller = _customRpc ??
          (fn, {params}) => Supabase.instance.client.rpc(fn, params: params);

      // 1. First attempt exact identifier resolution via the identification RPC
      final exactResult = await engine.identify(
        ProductIdentificationRequest(
          rawIdentifier: cleanQuery,
          tenantId: session.tenantId,
          locationId: locationId ?? session.locationId,
          scannerSource: ScannerSource.manual,
        ),
      );

      if (exactResult.isExact && exactResult.primaryMatch != null) {
        return [exactResult.primaryMatch!];
      }
      if (exactResult.isAmbiguous && exactResult.matches.isNotEmpty) {
        return exactResult.matches;
      }

      // 2. Fall back to multi-product listing search if code did not hit directly
      final Map<String, dynamic> rpcParams = {
        'p_tenant_id': session.tenantId,
      };
      final loc = locationId ?? session.locationId;
      if (loc.isNotEmpty) {
        rpcParams['p_location_id'] = loc;
      }

      final response = await caller(
        'inventory_list_products_v483',
        params: rpcParams,
      );

      if (response == null || response is! List) return const [];

      final lowerQuery = cleanQuery.toLowerCase();
      final results = <ProductIdentificationMatch>[];

      for (final row in response) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);

        final name = (map['product_name'] ?? map['name'])?.toString() ?? '';
        final sku = map['sku']?.toString() ?? '';
        final barcode = map['barcode']?.toString() ?? '';
        final partNumber =
            (map['part_number'] ?? map['partNumber'])?.toString() ?? '';
        final brand = (map['brand_name'] ?? map['brand'])?.toString() ?? '';
        final searchCodes = map['search_codes']?.toString() ?? '';

        final matches = name.toLowerCase().contains(lowerQuery) ||
            sku.toLowerCase().contains(lowerQuery) ||
            barcode.toLowerCase().contains(lowerQuery) ||
            partNumber.toLowerCase().contains(lowerQuery) ||
            brand.toLowerCase().contains(lowerQuery) ||
            searchCodes.toLowerCase().contains(lowerQuery);

        if (matches) {
          results.add(
            ProductIdentificationMatch.fromRpcMap(
              map,
              matchMethod: MatchMethod.searchIndexMatch,
              matchedCode: cleanQuery,
            ),
          );
        }
      }

      return results;
    } catch (_) {
      return const [];
    }
  }

  // --- Bulk Session Management ---

  /// Initializes a new in-memory bulk scanning session.
  SmartScanSession startBulkSession({
    required MobileSession session,
    String? locationId,
    String? locationName,
    String? title,
  }) {
    final effectiveLocationId = locationId ?? session.locationId;
    final effectiveLocationName = locationName ?? session.locationName;
    final newSession = SmartScanSession(
      id: 'bulk-mob-${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? 'Mobile Scan #${DateTime.now().minute.toString().padLeft(2, '0')}',
      locationId: effectiveLocationId,
      locationName: effectiveLocationName,
      operatorName: session.username.isNotEmpty ? session.username : 'Mobile Operator',
    );
    _activeBulkSession = newSession;
    return newSession;
  }

  /// Completes the active bulk session, moves it to history, and clears active state.
  ///
  /// STRICT ARCHITECTURAL INVARIANT:
  /// This operation records and closes the session in-memory only.
  /// It DOES NOT mutate inventory counts or post stock adjustments.
  SmartScanSession? finishBulkSession() {
    final current = _activeBulkSession;
    if (current == null) return null;

    current.complete();
    _completedSessions.insert(0, current);
    _activeBulkSession = null;
    return current;
  }

  /// Cancels and discards the active bulk scanning session without saving.
  void cancelBulkSession() {
    _activeBulkSession = null;
  }

  /// Clears completed sessions and activity history (useful for test isolation).
  void clearCompletedSessions() {
    _completedSessions.clear();
    _activityFeed.clear();
    _activeBulkSession = null;
  }

  void clearActivity() {
    _activityFeed.clear();
  }

  void _recordActivity(ProductIdentificationResult result) {
    final entry = ScanActivityLogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      rawCode: result.request.rawIdentifier,
      status: result.status,
      productName: result.primaryMatch?.productName,
      sku: result.primaryMatch?.sku,
      source: result.request.scannerSource,
      timestamp: result.request.timestamp,
      errorMessage: result.errorMessage,
    );

    _activityFeed.insert(0, entry);
    if (_activityFeed.length > 100) {
      _activityFeed.removeLast();
    }

    if (!_activityStreamController.isClosed) {
      _activityStreamController.add(entry);
    }
  }

  void dispose() {
    _activityStreamController.close();
  }
}
