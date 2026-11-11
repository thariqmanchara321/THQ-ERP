import 'dart:convert';

import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';
import 'mobile_pos_local_store.dart';

/// Orchestrates multi-tier product identification for THQ Mobile POS.
///
/// Features:
/// 1. Online lookup via Supabase RPC (`inventory_product_lookup_v482`).
/// 2. Offline fallback via local SQLite (`MobilePosLocalStore` / `thq_mobile_pos_v488.sqlite`).
/// 3. Preserves leading zeros and exact raw text integrity.
/// 4. Maps resolved [ProductIdentificationMatch] candidates directly to [MobileProduct].
class MobilePosSmartInventoryService {
  MobilePosSmartInventoryService._();
  static final MobilePosSmartInventoryService instance =
      MobilePosSmartInventoryService._();

  RpcCaller? _customRpc;
  OfflineProductIdentificationRepository? _customOfflineRepo;

  /// Injects a custom RPC caller (primarily for automated unit tests).
  void setCustomRpc(RpcCaller? caller) {
    _customRpc = caller;
  }

  /// Injects a custom offline repository (primarily for automated unit tests).
  void setCustomOfflineRepo(
    OfflineProductIdentificationRepository? offlineRepo,
  ) {
    _customOfflineRepo = offlineRepo;
  }

  /// Builds a [ProductIdentificationEngine] configured with online RPC
  /// and local SQLite offline fallback.
  ProductIdentificationEngine _buildEngine({
    required PosSession session,
    bool forceOffline = false,
  }) {
    final onlineRepo = RpcProductIdentificationRepository(
      _customRpc ??
          (functionName, {params}) async {
            return Supabase.instance.client.rpc(
              functionName,
              params: params ?? const {},
            );
          },
    );

    final offlineRepo =
        _customOfflineRepo ??
        LocalProductIdentificationRepository(
          (tenantId, locationId) async {
            try {
              final db = await MobilePosLocalStore.instance.db;
              final locId = locationId ?? session.locationId;
              final rows = await db.query(
                'products',
                columns: ['payload_json', 'available_qty'],
                where: 'tenant_id = ? AND location_id = ?',
                whereArgs: [tenantId, locId],
              );

              return rows.map((r) {
                final payload = Map<String, dynamic>.from(
                  jsonDecode(r['payload_json'] as String) as Map,
                );
                final availQty = (r['available_qty'] as num?)?.toDouble() ?? 0;
                payload['stock_quantity'] = availQty;
                payload['offline_available_quantity'] = availQty;
                return payload;
              }).toList();
            } catch (_) {
              return const [];
            }
          },
        );

    final compositeRepo = CompositeProductIdentificationRepository(
      onlineRepository: onlineRepo,
      offlineRepository: offlineRepo,
      preferOnline: !forceOffline,
    );

    return ProductIdentificationEngine(
      repository: compositeRepo,
      offlineRepository: offlineRepo,
      configuration: const ProductIdentificationConfiguration(
        trimWhitespace: true,
        minCodeLength: 1,
        allowFuzzyMatching: false,
        requireSelectionOnAmbiguity: true,
      ),
    );
  }

  /// Identifies a scanned item from a [SmartScanResult].
  Future<ProductIdentificationResult> identifyScan(
    SmartScanResult scan, {
    required PosSession session,
    bool forceOffline = false,
  }) async {
    final engine = _buildEngine(
      session: session,
      forceOffline: forceOffline,
    );

    return engine.identifyScan(
      scan,
      tenantId: session.tenantId,
      locationId: session.locationId,
      deviceId: session.deviceId,
      forceOffline: forceOffline,
    );
  }

  /// Identifies a raw text code (from manual entry or hardware wedge string).
  Future<ProductIdentificationResult> identifyCode(
    String code, {
    required PosSession session,
    ScannerSource source = ScannerSource.manual,
    bool forceOffline = false,
  }) async {
    final scan = SmartScanResult.valid(
      rawValue: code.trim(),
      format: SmartBarcodeFormat.unknown,
      source: source,
    );

    return identifyScan(
      scan,
      session: session,
      forceOffline: forceOffline,
    );
  }

  /// Resolves a [ProductIdentificationMatch] to a full [MobileProduct].
  ///
  /// First checks the in-memory [products] list for O(1) matching.
  /// If missing from memory, constructs a [MobileProduct] from the match's
  /// raw payload dictionary.
  MobileProduct? resolveProduct(
    ProductIdentificationMatch match, {
    List<MobileProduct>? products,
  }) {
    if (products != null) {
      for (final p in products) {
        if (p.variantId == match.variantId) {
          return p;
        }
      }
    }

    if (match.rawPayload.isNotEmpty) {
      try {
        return MobileProduct.fromMap(match.rawPayload);
      } catch (_) {
        // Fallback below
      }
    }

    return null;
  }
}
