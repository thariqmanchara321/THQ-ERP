import 'package:supabase_flutter/supabase_flutter.dart';

class BarcodeService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> lookup({
    required String tenantId,
    required String barcode,
    String? locationId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_product_lookup_v482',
      params: {
        'p_tenant_id': tenantId,
        'p_code': barcode.trim(),
        'p_location_id': locationId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }
}
