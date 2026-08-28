import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inventory_product.dart';

class InventoryService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<InventoryProduct>> getProducts({required String tenantId}) async {
    final result = await _supabase.rpc(
      'inventory_list_products',
      params: {'p_tenant_id': tenantId},
    );

    final rows = result as List<dynamic>;

    return rows
        .map(
          (row) =>
              InventoryProduct.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
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
  }) async {
    final result = await _supabase.rpc(
      'inventory_create_product',
      params: {
        'p_tenant_id': tenantId,
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
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    throw Exception('Unexpected response while creating product.');
  }
}
