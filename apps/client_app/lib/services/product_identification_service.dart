import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductIdentificationService {
  SupabaseClient get _supabase => Supabase.instance.client;
  Future<List<ProductIdentifier>> identifiers({
    required String tenantId,
    required String variantId,
  }) async {
    final r = await _supabase.rpc(
      'product_identifiers_v482_list',
      params: {'p_tenant_id': tenantId, 'p_variant_id': variantId},
    );
    return (r as List? ?? const [])
        .whereType<Map>()
        .map((e) => ProductIdentifier.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String> save({
    required String tenantId,
    required String variantId,
    String? identifierId,
    required String type,
    required String code,
    String? supplierId,
    String label = '',
    bool isPrimary = false,
    bool active = true,
  }) async {
    final r = await _supabase.rpc(
      'product_identifier_save_v482',
      params: {
        'p_tenant_id': tenantId,
        'p_identifier_id': identifierId,
        'p_variant_id': variantId,
        'p_identifier_type': type,
        'p_code': code.trim(),
        'p_supplier_id': supplierId,
        'p_label': label.trim(),
        'p_is_primary': isPrimary,
        'p_active': active,
      },
    );
    return r?.toString() ?? '';
  }

  Future<ProductIdentifier> generate({
    required String tenantId,
    required String variantId,
    required String type,
  }) async {
    final r = await _supabase.rpc(
      'product_identifier_generate_v482',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_identifier_type': type,
      },
    );
    final m = Map<String, dynamic>.from(r as Map);
    return ProductIdentifier.fromMap({
      ...m,
      'variant_id': variantId,
      'active': true,
      'generated': true,
    });
  }

  Future<void> archive({
    required String tenantId,
    required String identifierId,
  }) => _supabase.rpc(
    'product_identifier_archive_v482',
    params: {'p_tenant_id': tenantId, 'p_identifier_id': identifierId},
  );
  Future<Map<String, dynamic>> lookup({
    required String tenantId,
    required String code,
    String? locationId,
  }) async {
    final r = await _supabase.rpc(
      'inventory_product_lookup_v482',
      params: {
        'p_tenant_id': tenantId,
        'p_code': code.trim(),
        'p_location_id': locationId,
      },
    );
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> labelTemplates(String tenantId) async {
    final r = await _supabase.rpc(
      'label_templates_v482',
      params: {'p_tenant_id': tenantId},
    );
    return (r as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
