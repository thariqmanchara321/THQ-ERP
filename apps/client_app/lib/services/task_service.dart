import 'package:supabase_flutter/supabase_flutter.dart';

class TaskService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list({
    required String tenantId,
    String? locationId,
    String? status,
  }) async {
    final result = await _supabase.rpc(
      'business_tasks_list_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
      },
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> save({
    required String tenantId,
    String? taskId,
    String? locationId,
    required String title,
    String description = '',
    String priority = 'normal',
    String status = 'open',
    String? assignedTo,
    DateTime? dueAt,
    String? entityType,
    String? entityId,
  }) async {
    await _supabase.rpc(
      'business_task_save_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_task_id': taskId,
        'p_location_id': locationId,
        'p_title': title,
        'p_description': description,
        'p_priority': priority,
        'p_status': status,
        'p_assigned_to': assignedTo,
        'p_due_at': dueAt?.toUtc().toIso8601String(),
        'p_entity_type': entityType,
        'p_entity_id': entityId,
      },
    );
  }
}
