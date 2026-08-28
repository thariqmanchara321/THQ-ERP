class BusinessUserRole {
  final String id;
  final String key;
  final String name;
  final bool isSystem;

  const BusinessUserRole({
    required this.id,
    required this.key,
    required this.name,
    required this.isSystem,
  });

  factory BusinessUserRole.fromMap(Map<String, dynamic> map) {
    return BusinessUserRole(
      id: map['id']?.toString() ?? '',
      key: map['key']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      isSystem: map['is_system'] == true,
    );
  }
}

class BusinessUser {
  final String membershipId;
  final String userId;

  final String name;
  final String username;
  final String? email;
  final String status;

  final DateTime? joinedAt;

  final List<BusinessUserRole> roles;

  const BusinessUser({
    required this.membershipId,
    required this.userId,
    required this.name,
    required this.username,
    required this.email,
    required this.status,
    required this.joinedAt,
    required this.roles,
  });

  factory BusinessUser.fromMap(Map<String, dynamic> map) {
    final rawRoles = map['roles'];

    final roles = rawRoles is List
        ? rawRoles
              .map(
                (role) => BusinessUserRole.fromMap(
                  Map<String, dynamic>.from(role as Map),
                ),
              )
              .toList()
        : <BusinessUserRole>[];

    final joinedAtRaw = map['joined_at']?.toString();

    return BusinessUser(
      membershipId: map['membership_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      email: map['email']?.toString(),
      status: map['status']?.toString() ?? '',
      joinedAt: joinedAtRaw == null ? null : DateTime.tryParse(joinedAtRaw),
      roles: roles,
    );
  }
}

class BusinessUsersData {
  final List<BusinessUser> users;

  final List<BusinessUserRole> roles;

  const BusinessUsersData({required this.users, required this.roles});
}
