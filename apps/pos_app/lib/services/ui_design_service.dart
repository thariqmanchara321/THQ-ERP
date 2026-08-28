import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/v43_theme.dart';

class UiDesignService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<UiDesignProfile> load({
    required String tenantId,
    required String appKey,
  }) async {
    try {
      final result = await _supabase.rpc(
        'tenant_ui_design_get_v43',
        params: {'p_tenant_id': tenantId, 'p_app_key': appKey},
      );
      if (result is Map) {
        return UiDesignProfile.fromMap(
          Map<String, dynamic>.from(result),
          appKey,
        );
      }
    } catch (_) {
      // V4.3 can still start with its local default before migration 073 is applied.
    }
    return UiDesignProfile.fallback(appKey);
  }
}
