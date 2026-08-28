import 'package:supabase_flutter/supabase_flutter.dart';

class ProductionService {
  SupabaseClient get _s => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> recipes(String tenantId) async {
    final result = await _s.rpc(
      'production_recipes_list_v32',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> saveRecipe({
    required String tenantId,
    String? recipeId,
    required String name,
    required String outputVariantId,
    required double outputQuantity,
    required List<Map<String, dynamic>> items,
    String notes = '',
  }) async {
    await _s.rpc(
      'production_recipe_save',
      params: {
        'p_tenant_id': tenantId,
        'p_recipe_id': recipeId,
        'p_name': name.trim(),
        'p_output_variant_id': outputVariantId,
        'p_output_quantity': outputQuantity,
        'p_notes': notes.trim(),
        'p_active': true,
        'p_items': items,
      },
    );
  }

  Future<List<Map<String, dynamic>>> runs(
    String tenantId, {
    String? locationId,
  }) async {
    final result = await _s.rpc(
      'production_runs_list_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_limit': 300,
      },
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> execute({
    required String tenantId,
    required String recipeId,
    required String locationId,
    required double batches,
    String notes = '',
  }) async {
    final result = await _s.rpc(
      'production_run_execute_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_recipe_id': recipeId,
        'p_location_id': locationId,
        'p_batches': batches,
        'p_notes': notes.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected production response.');
    }
    return Map<String, dynamic>.from(result);
  }
}
