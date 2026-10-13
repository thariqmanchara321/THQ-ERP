import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_installation_service.dart';

class ClientAuthService {
  final String appKey;
  ClientAuthService({this.appKey = 'pos'});

  SupabaseClient get _supabase => Supabase.instance.client;
  User? get currentUser => _supabase.auth.currentUser;
  bool get isSignedIn => _supabase.auth.currentSession != null;

  String _extractErrorMessage(dynamic error, {String fallback = 'Authentication failed.'}) {
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        return details['error'].toString();
      }
      if (details is String && details.trim().isNotEmpty) {
        return details.trim();
      }
      final reason = error.reasonPhrase;
      if (reason != null && reason.trim().isNotEmpty) {
        return reason.trim();
      }
    }
    if (error is AuthException) {
      return error.message;
    }
    final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return raw.isNotEmpty ? raw : fallback;
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null) {
      throw const AuthException('This system must be activated first.');
    }
    try {
      final response = await _supabase.functions.invoke(
        'username-login',
        body: {
          'username': username.trim().toLowerCase(),
          'password': password,
          'app_key': appKey,
          'device_id': activation.deviceId,
          'device_secret': activation.deviceSecret,
          'tenant_id': activation.tenantId,
        },
      ).timeout(const Duration(seconds: 15));
      if (response.data is! Map) throw const AuthException('Unexpected login response.');
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null) throw AuthException(data['error'].toString());
      final refreshToken = data['refresh_token']?.toString();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const AuthException('Login failed.');
      }
      await _supabase.auth
          .setSession(refreshToken)
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(_extractErrorMessage(e, fallback: 'Login failed. Please try again.'));
    }
  }

  Future<void> authorizeBindingChange({
    required String username,
    required String password,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null) {
      throw const AuthException('This system must be activated first.');
    }
    try {
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
      ).timeout(const Duration(seconds: 15));
      if (response.data is! Map) {
        throw const AuthException('Unexpected authorization response.');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null) {
        throw AuthException(data['error'].toString());
      }
      if (data['authorized'] != true) {
        throw const AuthException('Owner or administrator authorization failed.');
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        _extractErrorMessage(
          e,
          fallback: 'Owner or administrator authorization failed.',
        ),
      );
    }
  }

  Future<void> signOut() => _supabase.auth
      .signOut()
      .timeout(const Duration(seconds: 5), onTimeout: () {});
}

