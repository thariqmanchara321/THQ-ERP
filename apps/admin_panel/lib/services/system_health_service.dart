import 'package:supabase_flutter/supabase_flutter.dart';

class SystemHealthService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> summary(String tenantId) async {
    final result = await _supabase.rpc(
      'system_health_summary_v47',
      params: {'p_tenant_id': tenantId},
    );
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }


  Future<Map<String, dynamic>> connectivity(String tenantId) async {
    final api = await _supabase.rpc('thq_api_contract_v480');
    final sync = await _supabase.rpc(
      'thq_sync_versions_v480',
      params: {'p_tenant_id': tenantId},
    );
    return <String, dynamic>{
      'api': api is Map ? Map<String, dynamic>.from(api) : <String, dynamic>{},
      'sync': sync is Map ? Map<String, dynamic>.from(sync) : <String, dynamic>{},
    };
  }

  Future<List<Map<String, dynamic>>> scan(String tenantId) async {
    final result = await _supabase.rpc(
      'system_integrity_scan_v47',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) => ((row['issue_count'] as num?)?.toInt() ?? 0) > 0)
        .toList();
  }
}
