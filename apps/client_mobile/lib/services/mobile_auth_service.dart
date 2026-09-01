import 'package:supabase_flutter/supabase_flutter.dart';
import 'device_installation_service.dart';

class MobileAuthService {
  SupabaseClient get _supabase => Supabase.instance.client;
  bool get signedIn => _supabase.auth.currentSession != null;

  Future<void> signIn({required String username, required String password}) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null) throw const AuthException('Activate this Client Mobile system first.');
    final response = await _supabase.functions.invoke('username-login', body: {
      'username': username.trim().toLowerCase(),'password': password,'app_key': 'client','device_id': activation.deviceId,'device_secret': activation.deviceSecret,
    });
    if (response.data is! Map) throw const AuthException('Unexpected login response.');
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw AuthException(data['error'].toString());
    final refreshToken = data['refresh_token']?.toString() ?? '';
    if (refreshToken.isEmpty) throw const AuthException('Login failed.');
    await _supabase.auth.setSession(refreshToken);
  }

  Future<void> signOut() => _supabase.auth.signOut();
}
