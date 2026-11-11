import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../models/inventory_product.dart';
import 'offline_pos_service.dart';

/// Central service coordinating Smart Inventory scanning and product identification
/// within the THQ POS Desktop application.
class PosSmartInventoryService {
  PosSmartInventoryService._();

  static final PosSmartInventoryService instance = PosSmartInventoryService._();

  RpcCaller? _customRpc;
  OfflineProductIdentificationRepository? _customOfflineRepo;

  /// Injects custom RPC caller (useful for unit/widget tests).
  void setCustomRpc(RpcCaller? rpc) {
    _customRpc = rpc;
  }

  /// Injects custom offline repository (useful for tests).
  void setCustomOfflineRepo(OfflineProductIdentificationRepository? repo) {
    _customOfflineRepo = repo;
  }

  /// Builds a [ProductIdentificationEngine] configured with both online Supabase
  /// RPC and offline SQLite cache repositories for the given [session].
  ProductIdentificationEngine getEngine({
    required ClientSession session,
    String? locationId,
    bool forceOffline = false,
  }) {
    final effectiveLocationId = locationId ?? session.device?.locationId;

    // 1. Online Repository
    final RpcCaller caller = _customRpc ??
        (fn, {params}) => Supabase.instance.client.rpc(fn, params: params);
    final onlineRepo = RpcProductIdentificationRepository(caller);

    // 2. Offline SQLite Repository
    final OfflineProductIdentificationRepository offlineRepo =
        _customOfflineRepo ??
            LocalProductIdentificationRepository(
              (tenantId, locId) async {
                final targetLoc = locId ?? effectiveLocationId ?? '';
                final offline = OfflinePosService.instance;
                final cached = await offline.cachedProducts(
                  tenantId: tenantId,
                  locationId: targetLoc,
                );
                return cached.map((p) => _inventoryProductToMap(p)).toList();
              },
            );

    // 3. Composite Orchestrator
    final compositeRepo = CompositeProductIdentificationRepository(
      onlineRepository: onlineRepo,
      offlineRepository: offlineRepo,
      preferOnline: !forceOffline,
    );

    return ProductIdentificationEngine(
      repository: compositeRepo,
      offlineRepository: offlineRepo,
    );
  }

  /// Identifies a scanned barcode/QR [scan] within authenticated POS context.
  Future<ProductIdentificationResult> identifyScan(
    SmartScanResult scan, {
    required ClientSession session,
    String? locationId,
    bool forceOffline = false,
  }) async {
    final engine = getEngine(
      session: session,
      locationId: locationId,
      forceOffline: forceOffline,
    );

    return engine.identifyScan(
      scan,
      tenantId: session.business.id,
      locationId: locationId ?? session.device?.locationId,
      deviceId: session.device?.deviceId,
      forceOffline: forceOffline,
    );
  }

  /// Identifies a raw text code (from manual entry or hardware wedge string).
  Future<ProductIdentificationResult> identifyCode(
    String code, {
    required ClientSession session,
    String? locationId,
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
      locationId: locationId,
      forceOffline: forceOffline,
    );
  }

  /// Resolves a [ProductIdentificationMatch] to a full [InventoryProduct].
  ///
  /// First checks the in-memory [catalogueByVariantId] for the fast path.
  /// If missing from memory, constructs an [InventoryProduct] from the match's
  /// raw payload dictionary.
  InventoryProduct? resolveProduct(
    ProductIdentificationMatch match, {
    Map<String, InventoryProduct>? catalogueByVariantId,
  }) {
    if (catalogueByVariantId != null &&
        catalogueByVariantId.containsKey(match.variantId)) {
      return catalogueByVariantId[match.variantId];
    }

    if (match.rawPayload.isNotEmpty) {
      try {
        return InventoryProduct.fromMap(match.rawPayload);
      } catch (_) {
        // Fallback below
      }
    }

    return null;
  }

  /// Serializes an [InventoryProduct] into a schema map compatible with
  /// [LocalProductIdentificationRepository].
  static Map<String, dynamic> _inventoryProductToMap(InventoryProduct p) {
    return {
      'product_id': p.productId,
      'variant_id': p.variantId,
      'product_name': p.productName,
      'variant_name': p.variantName,
      'sku': p.sku,
      'barcode': p.barcode,
      'part_number': p.partNumber,
      'brand_name': p.brandName,
      'category_name': p.categoryName,
      'unit_name': p.unitName,
      'unit_code': p.unitCode,
      'selling_price': p.sellingPrice,
      'cost_price': p.costPrice,
      'stock_quantity': p.stockQuantity,
      'tax_rate': p.taxRate,
      'item_type': p.itemType,
      'tracking_mode': p.trackingMode,
      'search_codes': p.searchCodes,
      'identifiers': p.identifiers
          .map(
            (id) => {
              'identifier_id': id.id,
              'variant_id': id.variantId,
              'type': id.type,
              'code': id.code,
              'label': id.label,
              'is_primary': id.isPrimary,
              'active': id.active,
            },
          )
          .toList(),
    };
  }
}

