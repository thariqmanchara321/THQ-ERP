import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_error_log.dart';

class AppLogService {
  static String? activeTenantId;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> log({
    required String appKey,
    required Object error,
    StackTrace? stack,
    String? tenantId,
    String severity = 'error',
    Map<String, dynamic>? context,
  }) async {
    if (_supabase.auth.currentUser == null) {
      return;
    }

    try {
      await _supabase.rpc(
        'app_error_log_write',
        params: {
          'p_app_key': appKey,
          'p_message': error.toString(),
          'p_stack_trace': stack?.toString(),
          'p_context': context ?? <String, dynamic>{},
          'p_tenant_id': tenantId ?? activeTenantId,
          'p_severity': severity,
          'p_app_version': ThqReleaseContract.appVersion,
        },
      );
    } catch (_) {
      // Error logging must never crash the ERP itself.
    }
  }

  Future<void> reportIssue({
    required String tenantId,
    required String appKey,
    required String message,
    String details = '',
  }) async {
    await _supabase.rpc(
      'app_error_log_write',
      params: {
        'p_app_key': appKey,
        'p_message': message.trim(),
        'p_stack_trace': null,
        'p_context': {
          'reported_by_user': true,
          if (details.trim().isNotEmpty) 'details': details.trim(),
        },
        'p_tenant_id': tenantId,
        'p_severity': 'issue',
        'p_app_version': ThqReleaseContract.appVersion,
      },
    );
  }

  Future<List<Map<String, dynamic>>> auditList({
    required String tenantId,
  }) async {
    final result = await _supabase.rpc(
      'business_audit_log_list',
      params: {'p_tenant_id': tenantId, 'p_limit': 500},
    );

    return (result as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<AppErrorLog>> list({required String tenantId}) async {
    final result = await _supabase.rpc(
      'app_error_logs_list',
      params: {'p_tenant_id': tenantId, 'p_limit': 300},
    );

    return (result as List)
        .map(
          (row) => AppErrorLog.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }
}
