import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAuthService {
  SupabaseClient get _supabase => Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Future<String> currentUsername() async {
    final result = await _supabase.rpc('current_username');
    return result?.toString() ?? '';
  }

  Future<bool> signIn({
    required String username,
    required String password,
  }) async {
    final response = await _supabase.functions.invoke(
      'username-login',
      body: {'username': username.trim(), 'password': password},
    );

    if (response.data is! Map) {
      throw Exception('Unexpected login response.');
    }

    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) {
      throw AuthException(data['error'].toString());
    }

    final refreshToken = data['refresh_token']?.toString();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthException('Login failed.');
    }

    await _supabase.auth.setSession(refreshToken);

    var allowed = false;
    try {
      final context = await _supabase.rpc('platform_current_admin_context');
      if (context is Map) {
        allowed = context['is_admin'] == true;
      }
    } catch (_) {
      final legacy = await _supabase.rpc('current_user_is_platform_admin');
      allowed = legacy == true;
    }

    if (allowed) {
      return true;
    }

    await _supabase.auth.signOut();
    return false;
  }

  Future<void> signOut() => _supabase.auth.signOut();
}
