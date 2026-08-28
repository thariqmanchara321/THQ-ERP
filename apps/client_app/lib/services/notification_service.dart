import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  SupabaseClient get _supabase => Supabase.instance.client;
  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final result = await _supabase.rpc(
      'notifications_list_v4',
      params: {'p_tenant_id': tenantId, 'p_limit': 100},
    );
    return (result as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> markRead(String tenantId, String id) async {
    await _supabase.rpc(
      'notification_mark_read_v4',
      params: {'p_tenant_id': tenantId, 'p_notification_id': id},
    );
  }
}
