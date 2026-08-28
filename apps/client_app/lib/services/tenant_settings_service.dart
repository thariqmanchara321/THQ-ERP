import 'package:supabase_flutter/supabase_flutter.dart';

class TenantSettingsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> getSettings(String tenantId) async {
    final result = await _supabase.rpc(
      'tenant_settings_v2_get',
      params: {'p_tenant_id': tenantId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return <String, dynamic>{};
  }

  Future<void> setSettings(
    String tenantId,
    Map<String, dynamic> settings,
  ) async {
    await _supabase.rpc(
      'tenant_settings_v2_set',
      params: {'p_tenant_id': tenantId, 'p_settings': settings},
    );
  }
}
