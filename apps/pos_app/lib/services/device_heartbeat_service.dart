import 'package:erp_core/erp_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';

class DeviceHeartbeatService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> send(ClientSession session) async {
    final device = session.device;
    if (device == null) return const {};
    final result = await _supabase.rpc(
      'device_heartbeat_v4',
      params: {
        'p_tenant_id': session.business.id,
        'p_device_id': device.deviceId,
        'p_app_key': 'pos',
        'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'p_version': ThqReleaseContract.appVersion,
        'p_build': ThqReleaseContract.buildNumber,
        'p_metadata': {
          'location_code': device.locationCode,
          'device_code': device.deviceCode,
          'username': session.username,
        },
      },
    );
    return result is Map ? Map<String, dynamic>.from(result) : const {};
  }
}
