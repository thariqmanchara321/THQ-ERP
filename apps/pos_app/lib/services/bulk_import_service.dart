import 'package:supabase_flutter/supabase_flutter.dart';

class BulkImportService {
  SupabaseClient get _s => Supabase.instance.client;
  Future<Map<String, dynamic>> importProducts({
    required String tenantId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final r = await _s.rpc(
      'inventory_bulk_create_products',
      params: {'p_tenant_id': tenantId, 'p_rows': rows},
    );
    if (r is! Map) throw Exception('Unexpected import response.');
    return Map<String, dynamic>.from(r);
  }
}
