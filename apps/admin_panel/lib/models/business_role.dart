class BusinessRole {
  final String id;
  final String key;
  final String name;
  final bool isSystem;
  final Set<String> permissionKeys;

  const BusinessRole({
    required this.id,
    required this.key,
    required this.name,
    required this.isSystem,
    required this.permissionKeys,
  });

  factory BusinessRole.fromMap(Map<String, dynamic> map) {
    final rawPermissions = map['permission_keys'];

    final permissionKeys = <String>{};

    if (rawPermissions is List) {
      permissionKeys.addAll(rawPermissions.map((item) => item.toString()));
    }

    return BusinessRole(
      id: map['role_id']?.toString() ?? '',
      key: map['role_key']?.toString() ?? '',
      name: map['role_name']?.toString() ?? '',
      isSystem: map['is_system'] == true,
      permissionKeys: permissionKeys,
    );
  }
}

class BusinessPermission {
  final String key;
  final String name;
  final String moduleKey;
  final String moduleName;

  const BusinessPermission({
    required this.key,
    required this.name,
    required this.moduleKey,
    required this.moduleName,
  });

  factory BusinessPermission.fromMap(Map<String, dynamic> map) {
    return BusinessPermission(
      key: map['permission_key']?.toString() ?? '',
      name: map['permission_name']?.toString() ?? '',
      moduleKey: map['module_key']?.toString() ?? '',
      moduleName: map['module_name']?.toString() ?? '',
    );
  }
}

class BusinessRolesData {
  final List<BusinessRole> roles;
  final List<BusinessPermission> permissions;

  const BusinessRolesData({required this.roles, required this.permissions});
}
