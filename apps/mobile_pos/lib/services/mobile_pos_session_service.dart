import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pos_session.dart';
import 'device_installation_service.dart';

class MobilePosSessionService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<PosSession> load() async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null) {
      throw StateError('Mobile POS is not activated.');
    }
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('User is not signed in.');

    final membership = await _supabase
        .from('tenant_memberships')
        .select('id')
        .eq('tenant_id', activation.tenantId)
        .eq('user_id', user.id)
        .eq('status', 'active')
        .maybeSingle();
    if (membership == null) {
      throw StateError('You do not have access to this business.');
    }

    final settings = await _supabase
        .from('tenant_settings')
        .select('currency_code')
        .eq('tenant_id', activation.tenantId)
        .maybeSingle();

    final raw = await _supabase.rpc(
      'mobile_pos_terminal_context_v488',
      params: {
        'p_tenant_id': activation.tenantId,
        'p_device_id': activation.deviceId,
      },
    );
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final modules = (map['allowed_modules'] as List? ?? const [])
        .map((value) => value.toString().trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();

    return PosSession(
      tenantId: activation.tenantId,
      businessName: activation.tenantName,
      deviceId: activation.deviceId,
      deviceCode: map['device_code']?.toString() ?? activation.deviceCode,
      deviceName: map['device_name']?.toString() ?? activation.deviceName,
      locationId: map['location_id']?.toString() ?? activation.locationId,
      locationCode:
          map['location_code']?.toString() ?? activation.locationCode,
      locationName:
          map['location_name']?.toString() ?? activation.locationName,
      currencyCode: settings?['currency_code']?.toString() ?? 'INR',
      username: map['username']?.toString() ?? user.email ?? 'User',
      restaurantEnabled: map['restaurant_enabled'] == true,
      allowedModules: Set<String>.unmodifiable(modules),
    );
  }
}
