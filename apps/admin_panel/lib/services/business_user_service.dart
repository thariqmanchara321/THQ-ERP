import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_user.dart';

class BusinessUserService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> _invoke({
    required Map<String, dynamic> body,
  }) async {
    final response = await _supabase.functions.invoke(
      'manage-business-users-v31',
      body: body,
    );

    final data = response.data;

    if (data is! Map) {
      throw Exception('Unexpected response from server.');
    }

    final result = Map<String, dynamic>.from(data);

    if (result['success'] != true) {
      throw Exception(result['error']?.toString() ?? 'Operation failed.');
    }

    return result;
  }

  Future<BusinessUsersData> getUsers({required String tenantId}) async {
    final result = await _invoke(
      body: {'action': 'list', 'tenant_id': tenantId},
    );

    final rawUsers = result['users'] as List? ?? [];

    final rawRoles = result['roles'] as List? ?? [];

    final users = rawUsers
        .map(
          (user) =>
              BusinessUser.fromMap(Map<String, dynamic>.from(user as Map)),
        )
        .toList();

    final roles = rawRoles
        .map(
          (role) =>
              BusinessUserRole.fromMap(Map<String, dynamic>.from(role as Map)),
        )
        .toList();

    return BusinessUsersData(users: users, roles: roles);
  }

  Future<void> addUser({
    required String tenantId,
    required String name,
    required String username,
    required String password,
    required String roleKey,
  }) async {
    await _invoke(
      body: {
        'action': 'create',
        'tenant_id': tenantId,
        'name': name.trim(),
        'username': username.trim().toLowerCase(),
        'password': password,
        'role_key': roleKey,
      },
    );
  }

  Future<void> resetPassword({
    required String tenantId,
    required String userId,
    required String password,
  }) async {
    await _invoke(
      body: {
        'action': 'reset_password',
        'tenant_id': tenantId,
        'user_id': userId,
        'password': password,
      },
    );
  }

  Future<void> deleteUser({
    required String tenantId,
    required String userId,
  }) async {
    await _invoke(
      body: {'action': 'delete', 'tenant_id': tenantId, 'user_id': userId},
    );
  }
}
