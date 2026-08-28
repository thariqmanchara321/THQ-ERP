import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_role.dart';

class BusinessRoleService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<BusinessRole>> getRoles({required String tenantId}) async {
    final result = await _supabase.rpc(
      'platform_get_business_roles',
      params: {'p_tenant_id': tenantId},
    );

    final rows = result as List<dynamic>;

    return rows
        .map(
          (row) => BusinessRole.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<List<BusinessPermission>> getPermissions({
    required String tenantId,
  }) async {
    final result = await _supabase.rpc(
      'platform_get_business_permissions',
      params: {'p_tenant_id': tenantId},
    );

    final rows = result as List<dynamic>;

    return rows
        .map(
          (row) =>
              BusinessPermission.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<BusinessRolesData> getRoleData({required String tenantId}) async {
    final results = await Future.wait([
      getRoles(tenantId: tenantId),
      getPermissions(tenantId: tenantId),
    ]);

    return BusinessRolesData(
      roles: results[0] as List<BusinessRole>,
      permissions: results[1] as List<BusinessPermission>,
    );
  }

  Future<void> updateRolePermissions({
    required String tenantId,
    required String roleId,
    required List<String> permissionKeys,
  }) async {
    await _supabase.rpc(
      'platform_update_role_permissions',
      params: {
        'p_tenant_id': tenantId,
        'p_role_id': roleId,
        'p_permission_keys': permissionKeys,
      },
    );
  }
}
