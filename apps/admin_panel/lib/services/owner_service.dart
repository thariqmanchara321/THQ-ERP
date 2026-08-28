import 'package:supabase_flutter/supabase_flutter.dart';

class OwnerService {
  SupabaseClient get _s => Supabase.instance.client;
  Future<Map<String, dynamic>> createOwner({
    required String tenantId,
    required String name,
    required String username,
    required String password,
  }) async {
    final response = await _s.functions.invoke(
      'manage-business-users-v31',
      body: {
        'action': 'create',
        'tenant_id': tenantId,
        'name': name.trim(),
        'username': username.trim().toLowerCase(),
        'password': password,
        'role_key': 'owner',
      },
    );
    if (response.data is Map) {
      final r = Map<String, dynamic>.from(response.data as Map);
      if (r['success'] == true) return r;
      throw Exception(
        r['error']?.toString() ?? 'Could not create owner account.',
      );
    }
    throw Exception('Unexpected response from server.');
  }
}
