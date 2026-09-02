import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erp_core/erp_core.dart';
import 'package:uuid/uuid.dart';

import '../models/inventory_product.dart';
import '../models/inventory_product_detail.dart';
import '../models/stock_movement.dart';
import 'device_installation_service.dart';
import 'location_scope_service.dart';

class InventoryService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String> nextSku({required String tenantId}) async {
    final result = await _supabase.rpc(
      'inventory_next_sku_v4',
      params: {'p_tenant_id': tenantId, 'p_prefix': 'SKU'},
    );
    return result?.toString() ?? '';
  }

  Future<bool> skuAvailable({
    required String tenantId,
    required String sku,
    String? variantId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_sku_available',
      params: {
        'p_tenant_id': tenantId,
        'p_sku': sku.trim(),
        'p_variant_id': variantId,
      },
    );
    return result == true;
  }

  Future<String?> publicId({
    required String tenantId,
    required String entityType,
    required String entityId,
  }) async {
    final result = await _supabase.rpc(
      'entity_public_id_get',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
      },
    );
    return result?.toString();
  }

  Future<List<InventoryProduct>> getProducts({
    required String tenantId,
    String? locationId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_list_products_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id':
            locationId ?? LocationScopeService.selectedLocationId.value,
      },
    );
    final rows = result as List<dynamic>;
    return rows
        .map(
          (row) =>
              InventoryProduct.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<List<InventoryUnit>> getUnits({required String tenantId}) async {
    final result = await _supabase.rpc(
      'inventory_units_list_v481',
      params: {'p_tenant_id': tenantId, 'p_active_only': true},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => InventoryUnit.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<String> saveUnit({
    required String tenantId,
    required String code,
    required String name,
    required String group,
    required int decimalPlaces,
    required bool allowFractional,
  }) async {
    final result = await _supabase.rpc(
      'inventory_unit_save_v481',
      params: {
        'p_tenant_id': tenantId,
        'p_unit_id': null,
        'p_code': code.trim(),
        'p_name': name.trim(),
        'p_group': group.trim(),
        'p_decimal_places': decimalPlaces,
        'p_allow_fractional': allowFractional,
        'p_active': true,
      },
    );
    return result?.toString() ?? '';
  }

  Future<List<ProductUnitOption>> getProductUnits({
    required String tenantId,
    required String variantId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_product_units_v481',
      params: {'p_tenant_id': tenantId, 'p_variant_id': variantId},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => ProductUnitOption.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<Map<String, dynamic>> saveProductUnits({
    required String tenantId,
    required String variantId,
    required String baseUnitCode,
    required List<Map<String, dynamic>> units,
  }) async {
    final result = await _supabase.rpc(
      'inventory_product_units_save_v481',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_base_unit_code': baseUnitCode,
        'p_units': units,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createProduct({
    required String tenantId,
    required String name,
    required String sku,
    required String itemType,
    required String description,
    required String categoryName,
    required String brandName,
    required String barcode,
    required String partNumber,
    required double costPrice,
    required double sellingPrice,
    required double? listPrice,
    required double taxRate,
    required double reorderLevel,
    required double openingStock,
    String? locationId,
    String baseUnitCode = 'PCS',
    List<Map<String, dynamic>> units = const <Map<String, dynamic>>[],
  }) async {
    final origin = await _origin(tenantId, locationId: locationId);
    final result = await _supabase.rpc(
      'inventory_create_product_v481',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': origin.locationId,
        'p_device_id': origin.deviceId,
        'p_name': name.trim(),
        'p_sku': sku.trim(),
        'p_item_type': itemType,
        'p_description': description.trim(),
        'p_category_name': categoryName.trim(),
        'p_brand_name': brandName.trim(),
        'p_barcode': barcode.trim(),
        'p_part_number': partNumber.trim(),
        'p_cost_price': costPrice,
        'p_selling_price': sellingPrice,
        'p_list_price': listPrice,
        'p_tax_rate': taxRate,
        'p_reorder_level': reorderLevel,
        'p_opening_stock': openingStock,
        'p_base_unit_code': baseUnitCode,
        'p_units': units,
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected response while creating product.');
  }

  Future<void> assignToLocation({
    required String tenantId,
    required String locationId,
    required String variantId,
    bool active = true,
    double? sellingPrice,
    double? reorderLevel,
    String rackCode = '',
  }) async {
    await _supabase.rpc(
      'inventory_location_assign_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_variant_id': variantId,
        'p_active': active,
        'p_selling_price': sellingPrice,
        'p_reorder_level': reorderLevel,
        'p_rack_code': rackCode.trim(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> locationStock({
    required String tenantId,
    required String variantId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_location_stock_summary_v4',
      params: {'p_tenant_id': tenantId, 'p_variant_id': variantId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> movementHistory({
    required String tenantId,
    String? variantId,
    String? locationId,
    String? movementType,
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    final result = await _supabase.rpc(
      'inventory_movement_history_v481',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_location_id': locationId,
        'p_movement_type': movementType,
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<InventoryProductDetail> getProductDetail({
    required String tenantId,
    required String variantId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_get_product_detail',
      params: {'p_tenant_id': tenantId, 'p_variant_id': variantId},
    );
    final rows = result as List<dynamic>;
    if (rows.isEmpty) throw Exception('Product not found.');
    return InventoryProductDetail.fromMap(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  Future<List<StockMovement>> getStockMovements({
    required String tenantId,
    required String variantId,
  }) async {
    final selectedLocation = LocationScopeService.selectedLocationId.value;
    final result = await _supabase.rpc(
      'inventory_movement_history_v481',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_location_id': selectedLocation,
        'p_movement_type': null,
        'p_from': null,
        'p_to': null,
        'p_limit': 500,
      },
    );
    return (result as List<dynamic>)
        .map(
          (row) => StockMovement.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> updateProduct({
    required String tenantId,
    required String variantId,
    required String name,
    required String description,
    required String categoryName,
    required String brandName,
    required String sku,
    required String barcode,
    required String partNumber,
    required double costPrice,
    required double sellingPrice,
    required double? listPrice,
    required double taxRate,
    required double reorderLevel,
  }) async {
    await _supabase.rpc(
      'inventory_update_product',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_name': name.trim(),
        'p_description': description.trim(),
        'p_category_name': categoryName.trim(),
        'p_brand_name': brandName.trim(),
        'p_sku': sku.trim(),
        'p_barcode': barcode.trim(),
        'p_part_number': partNumber.trim(),
        'p_cost_price': costPrice,
        'p_selling_price': sellingPrice,
        'p_list_price': listPrice,
        'p_tax_rate': taxRate,
        'p_reorder_level': reorderLevel,
      },
    );
  }

  Future<Map<String, dynamic>> adjustStock({
    required String tenantId,
    required String variantId,
    required double quantityDelta,
    required String note,
    String? locationId,
  }) async {
    final origin = await _origin(tenantId, locationId: locationId);
    final result = await _supabase.rpc(
      'inventory_adjust_stock_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': origin.locationId,
        'p_device_id': origin.deviceId,
        'p_variant_id': variantId,
        'p_quantity_delta': quantityDelta,
        'p_note': note.trim(),
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected stock adjustment response.');
  }

  Future<Map<String, dynamic>> postStockCount({
    required String tenantId,
    required String locationId,
    required List<Map<String, dynamic>> items,
    String notes = '',
  }) async {
    final origin = await _origin(tenantId, locationId: locationId);
    final result = await _supabase.rpc(
      'inventory_stock_count_post_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': origin.locationId,
        'p_items': items,
        'p_notes': notes.trim(),
        'p_device_id': origin.deviceId,
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected stock count response.');
  }

  Future<_Origin> _origin(String tenantId, {String? locationId}) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return _Origin(
      locationId:
          locationId ??
          LocationScopeService.selectedLocationId.value ??
          activation.locationId,
      deviceId: activation.deviceId,
    );
  }
}

class _Origin {
  final String locationId;
  final String deviceId;
  const _Origin({required this.locationId, required this.deviceId});
}
