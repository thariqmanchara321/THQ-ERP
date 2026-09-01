import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mobile_session.dart';
import 'device_installation_service.dart';

class MobileSessionService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<MobileSession> load() async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null) throw StateError('Client Mobile is not activated.');
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');
    final membership = await _supabase.from('tenant_memberships').select('id').eq('tenant_id', activation.tenantId).eq('user_id', user.id).eq('status', 'active').maybeSingle();
    if (membership == null) throw StateError('You do not have access to this business.');
    final settingsRaw = await _supabase.from('tenant_settings').select('currency_code').eq('tenant_id', activation.tenantId).maybeSingle();
    final runtimeRaw = await _supabase.rpc('client_runtime_context_v4', params: {'p_tenant_id': activation.tenantId,'p_device_id': activation.deviceId,'p_app_key': 'client'});
    final runtime = runtimeRaw is Map ? Map<String, dynamic>.from(runtimeRaw) : <String, dynamic>{};
    final locations = (runtime['locations'] as List? ?? const []).whereType<Map>().map((row) => MobileLocation.fromMap(Map<String, dynamic>.from(row))).toList();
    return MobileSession(
      tenantId: activation.tenantId,businessName: activation.tenantName,deviceId: activation.deviceId,
      deviceCode: runtime['device_code']?.toString() ?? activation.deviceCode,deviceName: runtime['device_name']?.toString() ?? activation.deviceName,
      locationId: runtime['location_id']?.toString() ?? activation.locationId,locationCode: runtime['location_code']?.toString() ?? activation.locationCode,locationName: runtime['location_name']?.toString() ?? activation.locationName,
      currencyCode: settingsRaw?['currency_code']?.toString() ?? 'INR',username: runtime['username']?.toString() ?? user.email ?? 'User',
      canViewAllLocations: runtime['can_view_all_locations'] == true,locations: locations,
    );
  }
}
