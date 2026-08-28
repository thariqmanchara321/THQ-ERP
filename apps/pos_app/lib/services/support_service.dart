import 'package:supabase_flutter/supabase_flutter.dart';

class SupportService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> createTicket({
    required String tenantId,
    required String? locationId,
    required String? deviceId,
    required String appKey,
    required String appVersion,
    required String category,
    required String priority,
    required String subject,
    required String description,
    String? errorLogId,
  }) async {
    final result = await _supabase.rpc(
      'support_ticket_create_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_device_id': deviceId,
        'p_app_key': appKey,
        'p_app_version': appVersion,
        'p_category': category,
        'p_priority': priority,
        'p_subject': subject.trim(),
        'p_description': description.trim(),
        'p_error_log_id': errorLogId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }
}
