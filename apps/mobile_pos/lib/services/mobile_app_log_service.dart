import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MobileAppLogService {
  static String? activeTenantId;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> log({
    required Object error,
    StackTrace? stack,
    String severity = 'error',
    Map<String, dynamic>? context,
  }) async {
    if (_supabase.auth.currentUser == null) return;
    try {
      await _supabase.rpc(
        'app_error_log_write',
        params: {
          'p_app_key': 'pos',
          'p_message': error.toString(),
          'p_stack_trace': stack?.toString(),
          'p_context': {
            'channel': 'mobile_pos',
            'build': ThqPosMobileReleaseContract.buildNumber,
            ...?context,
          },
          'p_tenant_id': activeTenantId,
          'p_severity': severity,
          'p_app_version': ThqPosMobileReleaseContract.appVersion,
        },
      );
    } catch (_) {
      // Diagnostics must never become an application failure.
    }
  }
}
