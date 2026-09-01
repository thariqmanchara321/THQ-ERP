import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final result = await _supabase.rpc(
      'notifications_list_v4',
      params: {'p_tenant_id': tenantId, 'p_limit': 200},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> markRead(String tenantId, String id) async {
    await _supabase.rpc(
      'notification_mark_read_v4',
      params: {'p_tenant_id': tenantId, 'p_notification_id': id},
    );
  }

  Future<int> markAllRead(String tenantId) async {
    final result = await _supabase.rpc(
      'notifications_mark_all_read_v495',
      params: {'p_tenant_id': tenantId},
    );
    return result is num ? result.toInt() : int.tryParse('$result') ?? 0;
  }
}
