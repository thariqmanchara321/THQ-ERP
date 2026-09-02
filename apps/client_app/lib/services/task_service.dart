import 'package:supabase_flutter/supabase_flutter.dart';

class TaskService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list({
    required String tenantId,
    String? locationId,
    String? status,
  }) async {
    final result = await _supabase.rpc(
      'business_tasks_list_v500',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<String> save({
    required String tenantId,
    String? taskId,
    String? locationId,
    required String title,
    String description = '',
    String priority = 'normal',
    String status = 'open',
    String? assignedTo,
    DateTime? dueAt,
    DateTime? reminderAt,
    String? entityType,
    String? entityId,
    String? sourceNotificationId,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final result = await _supabase.rpc(
      'business_task_save_v495',
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
        'p_reminder_at': reminderAt?.toUtc().toIso8601String(),
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_source_notification_id': sourceNotificationId,
        'p_metadata': metadata,
      },
    );
    return result?.toString() ?? '';
  }

  Future<Map<String, dynamic>> timeline({
    required String tenantId,
    required String taskId,
  }) async {
    final result = await _supabase.rpc(
      'business_task_timeline_v500',
      params: {'p_tenant_id': tenantId, 'p_task_id': taskId},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : const <String, dynamic>{};
  }

  Future<void> addComment({
    required String tenantId,
    required String taskId,
    required String comment,
  }) async {
    await _supabase.rpc(
      'business_task_comment_add_v500',
      params: {
        'p_tenant_id': tenantId,
        'p_task_id': taskId,
        'p_comment': comment,
      },
    );
  }

  Future<void> setEscalation({
    required String tenantId,
    required String taskId,
    DateTime? escalationAt,
    String? escalationUserId,
  }) async {
    await _supabase.rpc(
      'business_task_escalation_set_v500',
      params: {
        'p_tenant_id': tenantId,
        'p_task_id': taskId,
        'p_escalation_at': escalationAt?.toUtc().toIso8601String(),
        'p_escalation_user_id': escalationUserId,
      },
    );
  }

  Future<String> createFromNotification({
    required String tenantId,
    required String notificationId,
    String? assignedTo,
    DateTime? dueAt,
    String? priority,
  }) async {
    final result = await _supabase.rpc(
      'business_task_from_notification_v495',
      params: {
        'p_tenant_id': tenantId,
        'p_notification_id': notificationId,
        'p_assigned_to': assignedTo,
        'p_due_at': dueAt?.toUtc().toIso8601String(),
        'p_priority': priority,
      },
    );
    return result?.toString() ?? '';
  }
}
