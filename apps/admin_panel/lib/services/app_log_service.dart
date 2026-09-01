import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:erp_core/erp_core.dart';

class AdminAppLogService {
  SupabaseClient get _s => Supabase.instance.client;
  Future<void> log(
    Object error,
    StackTrace? stack, {
    String severity = 'error',
  }) async {
    if (_s.auth.currentUser == null) return;
    try {
      await _s.rpc(
        'app_error_log_write',
        params: {
          'p_app_key': 'admin',
          'p_message': error.toString(),
          'p_stack_trace': stack?.toString(),
          'p_context': <String, dynamic>{},
          'p_tenant_id': null,
          'p_severity': severity,
          'p_app_version': ThqReleaseContract.appVersion,
        },
      );
    } catch (_) {}
  }
}
