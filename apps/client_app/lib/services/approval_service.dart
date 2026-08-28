import 'package:supabase_flutter/supabase_flutter.dart';

class ApprovalService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list({
    required String tenantId,
    String status = 'pending',
  }) async {
    final result = await _supabase.rpc(
      'approval_requests_list_v4',
      params: {'p_tenant_id': tenantId, 'p_status': status},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> decide({
    required String tenantId,
    required String requestId,
    required bool approve,
    String note = '',
  }) async {
    await _supabase.rpc(
      'approval_request_decide_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_request_id': requestId,
        'p_approve': approve,
        'p_note': note,
      },
    );
  }
}
