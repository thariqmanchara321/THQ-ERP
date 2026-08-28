class TeamRole {
  final String id;
  final String key;
  final String name;
  final bool isSystem;

  const TeamRole({
    required this.id,
    required this.key,
    required this.name,
    required this.isSystem,
  });

  factory TeamRole.fromMap(Map<String, dynamic> map) => TeamRole(
    id: map['id']?.toString() ?? '',
    key: map['key']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    isSystem: map['is_system'] == true,
  );
}

class TeamLocation {
  final String id;
  final String code;
  final String name;

  const TeamLocation({
    required this.id,
    required this.code,
    required this.name,
  });

  factory TeamLocation.fromMap(Map<String, dynamic> map) => TeamLocation(
    id: map['id']?.toString() ?? '',
    code: map['code']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
  );
}

class TeamUser {
  final String membershipId;
  final String userId;
  final String name;
  final String username;
  final String status;
  final List<TeamRole> roles;
  final bool clientEnabled;
  final bool posEnabled;
  final List<String> locationIds;
  final String locationAccessLevel;

  const TeamUser({
    required this.membershipId,
    required this.userId,
    required this.name,
    required this.username,
    required this.status,
    required this.roles,
    required this.clientEnabled,
    required this.posEnabled,
    required this.locationIds,
    required this.locationAccessLevel,
  });

  bool get isOwner => roles.any((role) => role.key == 'owner');
  String get roleName =>
      roles.isEmpty ? 'No role' : roles.map((role) => role.name).join(', ');

  factory TeamUser.fromMap(Map<String, dynamic> map) {
    final roles = (map['roles'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => TeamRole.fromMap(Map<String, dynamic>.from(row)))
        .toList();
    final locationRows = (map['locations'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final locations = locationRows
        .map((row) => row['location_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    var accessLevel = 'view';
    if (locationRows.isNotEmpty) {
      accessLevel = locationRows.first['access_level']?.toString() ?? 'view';
    }

    return TeamUser(
      membershipId: map['membership_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      roles: roles,
      clientEnabled: map['client_enabled'] != false,
      posEnabled: map['pos_enabled'] == true,
      locationIds: locations,
      locationAccessLevel: accessLevel,
    );
  }
}

class TeamData {
  final List<TeamUser> users;
  final List<TeamRole> roles;
  final List<TeamLocation> locations;

  const TeamData({
    required this.users,
    required this.roles,
    required this.locations,
  });
}
