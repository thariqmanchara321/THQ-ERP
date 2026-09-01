import 'package:supabase_flutter/supabase_flutter.dart';
import 'device_installation_service.dart';
class MobilePosAuthService {
  SupabaseClient get _supabase=>Supabase.instance.client;
  bool get signedIn=>_supabase.auth.currentSession!=null;
  Future<void> signIn({required String username,required String password}) async {
    final a=await DeviceInstallationService().readActivation();if(a==null)throw const AuthException('Activate this Mobile POS first.');
    final r=await _supabase.functions.invoke('username-login',body:{'username':username.trim().toLowerCase(),'password':password,'app_key':'pos','device_id':a.deviceId,'device_secret':a.deviceSecret});
    if(r.data is! Map)throw const AuthException('Unexpected login response.');final d=Map<String,dynamic>.from(r.data as Map);if(d['error']!=null)throw AuthException(d['error'].toString());final token=d['refresh_token']?.toString()??'';if(token.isEmpty)throw const AuthException('Login failed.');await _supabase.auth.setSession(token);
  }
  Future<void> signOut()=>_supabase.auth.signOut();
}
