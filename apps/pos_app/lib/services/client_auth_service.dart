import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_installation_service.dart';

class ClientAuthService {
  final String appKey;
  ClientAuthService({this.appKey = 'pos'});

  SupabaseClient get _supabase => Supabase.instance.client;
  User? get currentUser => _supabase.auth.currentUser;
  bool get isSignedIn => _supabase.auth.currentSession != null;

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null) {
      throw const AuthException('This system must be activated first.');
    }
    final response = await _supabase.functions.invoke(
      'username-login',
      body: {
        'username': username.trim().toLowerCase(),
        'password': password,
        'app_key': appKey,
        'device_id': activation.deviceId,
        'device_secret': activation.deviceSecret,
      },
    );
    if (response.data is! Map) throw Exception('Unexpected login response.');
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw AuthException(data['error'].toString());
    final refreshToken = data['refresh_token']?.toString();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthException('Login failed.');
    }
    await _supabase.auth.setSession(refreshToken);
  }

  Future<void> authorizeBindingChange({
    required String username,
    required String password,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null) {
      throw const AuthException('This system must be activated first.');
    }
    final response = await _supabase.functions.invoke(
      'username-login',
      body: {
        'username': username.trim().toLowerCase(),
        'password': password,
        'app_key': appKey,
        'device_id': activation.deviceId,
        'device_secret': activation.deviceSecret,
        'authorization_scope': 'change_binding',
      },
    );
    if (response.data is! Map) {
      throw Exception('Unexpected authorization response.');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) {
      throw AuthException(data['error'].toString());
    }
    if (data['authorized'] != true) {
      throw const AuthException('Owner or administrator authorization failed.');
    }
  }

  Future<void> signOut() => _supabase.auth.signOut();
}
