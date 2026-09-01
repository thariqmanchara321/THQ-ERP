import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pos_session.dart';
import 'device_installation_service.dart';
class MobilePosSessionService {
  SupabaseClient get _supabase=>Supabase.instance.client;
  Future<PosSession> load() async {
    final a=await DeviceInstallationService().readActivation();if(a==null)throw StateError('Mobile POS is not activated.');final user=_supabase.auth.currentUser;if(user==null)throw StateError('User is not signed in.');
    final membership=await _supabase.from('tenant_memberships').select('id').eq('tenant_id',a.tenantId).eq('user_id',user.id).eq('status','active').maybeSingle();if(membership==null)throw StateError('You do not have access to this business.');
    final settings=await _supabase.from('tenant_settings').select('currency_code').eq('tenant_id',a.tenantId).maybeSingle();
    final raw=await _supabase.rpc('mobile_pos_terminal_context_v488',params:{'p_tenant_id':a.tenantId,'p_device_id':a.deviceId});final m=raw is Map?Map<String,dynamic>.from(raw):<String,dynamic>{};
    return PosSession(tenantId:a.tenantId,businessName:a.tenantName,deviceId:a.deviceId,deviceCode:m['device_code']?.toString()??a.deviceCode,deviceName:m['device_name']?.toString()??a.deviceName,locationId:m['location_id']?.toString()??a.locationId,locationCode:m['location_code']?.toString()??a.locationCode,locationName:m['location_name']?.toString()??a.locationName,currencyCode:settings?['currency_code']?.toString()??'INR',username:m['username']?.toString()??user.email??'User',restaurantEnabled:m['restaurant_enabled']==true);
  }
}
