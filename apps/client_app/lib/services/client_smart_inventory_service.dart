import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../models/smart_inventory_session_models.dart';

/// Client application service providing access to the shared [ProductIdentificationEngine],
/// session management for bulk scanning, and in-memory scan history tracking.
class ClientSmartInventoryService {
  ClientSmartInventoryService._();
  static final ClientSmartInventoryService instance =
      ClientSmartInventoryService._();

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

  /// Resolves an incoming Phase 1 [SmartScanResult] using authenticated [ClientSession].
  Future<ProductIdentificationResult> identifyScan(
    SmartScanResult scan, {
    required ClientSession session,
    String? locationId,
    bool forceOffline = false,
  }) async {
    final result = await engine.identifyScan(
      scan,
      tenantId: session.business.id,
      locationId: locationId,
      forceOffline: forceOffline,
    );

    _recordActivity(result);
    return result;
  }

  /// Resolves a manual or programmatic identifier string.
  Future<ProductIdentificationResult> identifyCode(
    String code, {
    required ClientSession session,
    String? locationId,
    ScannerSource source = ScannerSource.manual,
    bool forceOffline = false,
  }) async {
    final request = ProductIdentificationRequest(
      rawIdentifier: code,
      tenantId: session.business.id,
      locationId: locationId,
      scannerSource: source,
      forceOffline: forceOffline,
    );

    final result = await engine.identify(request);
    _recordActivity(result);
    return result;
  }

  /// Multi-identifier catalog search querying products across names, SKUs, and barcodes.
  Future<List<ProductIdentificationMatch>> searchCatalog(
    String query, {
    required ClientSession session,
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
          tenantId: session.business.id,
          locationId: locationId,
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
        'p_tenant_id': session.business.id,
      };
      if (locationId != null) {
        rpcParams['p_location_id'] = locationId;
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
        final partNumber = (map['part_number'] ?? map['partNumber'])?.toString() ?? '';
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
    required ClientSession session,
    String? locationId,
    String? locationName,
    String? title,
  }) {
    final newSession = SmartScanSession(
      id: 'bulk-${DateTime.now().millisecondsSinceEpoch}',
      title: title ?? 'Bulk Scan #${DateTime.now().minute.toString().padLeft(2, '0')}',
      locationId: locationId,
      locationName: locationName,
      operatorName: session.username.isNotEmpty ? session.username : 'Authorized User',
    );
    _activeBulkSession = newSession;
    return newSession;
  }

  /// Completes the active bulk session, moves it to history, and clears active state.
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

    _activityStreamController.add(entry);
  }
}
