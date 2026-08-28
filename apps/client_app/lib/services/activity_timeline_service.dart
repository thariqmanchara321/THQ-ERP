import 'package:supabase_flutter/supabase_flutter.dart';

class ActivityTimelineService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> load({
    required String tenantId,
    required String entityType,
    required String entityId,
  }) async {
    final result = await _supabase.rpc(
      'entity_activity_timeline_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_limit': 100,
      },
    );
    return (result as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
