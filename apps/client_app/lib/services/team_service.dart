import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/team_user.dart';

class TeamService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final response = await _supabase.functions.invoke(
      'manage-tenant-users-v32',
      body: body,
    );
    if (response.data is! Map) {
      throw Exception('Unexpected user-management response.');
    }
    final result = Map<String, dynamic>.from(response.data as Map);
    if (result['success'] != true) {
      throw Exception(result['error']?.toString() ?? 'User operation failed.');
    }
    return result;
  }

  Future<TeamData> list(String tenantId) async {
    final result = await _invoke({'action': 'list', 'tenant_id': tenantId});
    return TeamData(
      users: (result['users'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => TeamUser.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      roles: (result['roles'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => TeamRole.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      locations: (result['locations'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => TeamLocation.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Future<void> create({
    required String tenantId,
    required String name,
    required String username,
    required String password,
    required String roleKey,
    required bool clientEnabled,
    required bool posEnabled,
    required List<String> locationIds,
    required String accessLevel,
  }) async {
    await _invoke({
      'action': 'create',
      'tenant_id': tenantId,
      'name': name.trim(),
      'username': username.trim().toLowerCase(),
      'password': password,
      'role_key': roleKey,
      'client_enabled': clientEnabled,
      'pos_enabled': posEnabled,
      'location_ids': locationIds,
      'access_level': accessLevel,
    });
  }

  Future<void> updateAccess({
    required String tenantId,
    required String userId,
    required String roleKey,
    required bool clientEnabled,
    required bool posEnabled,
    required List<String> locationIds,
    required String accessLevel,
  }) async {
    await _invoke({
      'action': 'update_access',
      'tenant_id': tenantId,
      'user_id': userId,
      'role_key': roleKey,
      'client_enabled': clientEnabled,
      'pos_enabled': posEnabled,
      'location_ids': locationIds,
      'access_level': accessLevel,
    });
  }

  Future<void> resetPassword({
    required String tenantId,
    required String userId,
    required String password,
  }) => _invoke({
    'action': 'reset_password',
    'tenant_id': tenantId,
    'user_id': userId,
    'password': password,
  });

  Future<void> remove({required String tenantId, required String userId}) =>
      _invoke({'action': 'delete', 'tenant_id': tenantId, 'user_id': userId});
}
