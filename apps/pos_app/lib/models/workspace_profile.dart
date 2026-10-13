import 'dart:convert';

/// Represents a persistent location/device activation binding on this installation.
///
/// An installation can have multiple saved workspace profiles (e.g.
/// Tenzo Traders / Main, Tenzo Traders / Yard 2, Another Business / Main).
class ThqWorkspaceProfile {
  final String id;
  final String tenantId;
  final String tenantName;
  final String businessCode;
  final String locationId;
  final String locationName;
  final String locationCode;
  final String deviceId;
  final String deviceCode;
  final String deviceName;
  final String deviceSecret;
  final String appKey; // 'client' or 'pos'
  final DateTime activatedAt;
  final DateTime lastActiveAt;

  const ThqWorkspaceProfile({
    required this.id,
    required this.tenantId,
    required this.tenantName,
    required this.businessCode,
    required this.locationId,
    required this.locationName,
    required this.locationCode,
    required this.deviceId,
    required this.deviceCode,
    required this.deviceName,
    required this.deviceSecret,
    required this.appKey,
    required this.activatedAt,
    required this.lastActiveAt,
  });

  String get displayName => '$tenantName • $locationName';

  ThqWorkspaceProfile copyWith({
    String? tenantName,
    String? locationId,
    String? locationName,
    String? locationCode,
    String? deviceCode,
    String? deviceName,
    DateTime? lastActiveAt,
  }) {
    return ThqWorkspaceProfile(
      id: id,
      tenantId: tenantId,
      tenantName: tenantName ?? this.tenantName,
      businessCode: businessCode,
      locationId: locationId ?? this.locationId,
      locationName: locationName ?? this.locationName,
      locationCode: locationCode ?? this.locationCode,
      deviceId: deviceId,
      deviceCode: deviceCode ?? this.deviceCode,
      deviceName: deviceName ?? this.deviceName,
      deviceSecret: deviceSecret,
      appKey: appKey,
      activatedAt: activatedAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'tenant_id': tenantId,
    'tenant_name': tenantName,
    'business_code': businessCode,
    'location_id': locationId,
    'location_name': locationName,
    'location_code': locationCode,
    'device_id': deviceId,
    'device_code': deviceCode,
    'device_name': deviceName,
    'device_secret': deviceSecret,
    'app_key': appKey,
    'activated_at': activatedAt.toIso8601String(),
    'last_active_at': lastActiveAt.toIso8601String(),
  };

  factory ThqWorkspaceProfile.fromMap(Map<String, dynamic> map) {
    return ThqWorkspaceProfile(
      id: map['id']?.toString() ?? '',
      tenantId: map['tenant_id']?.toString() ?? '',
      tenantName: map['tenant_name']?.toString() ?? 'Business',
      businessCode: map['business_code']?.toString() ?? '',
      locationId: map['location_id']?.toString() ?? '',
      locationName: map['location_name']?.toString() ?? 'Main',
      locationCode: map['location_code']?.toString() ?? 'MAIN',
      deviceId: map['device_id']?.toString() ?? '',
      deviceCode: map['device_code']?.toString() ?? '',
      deviceName: map['device_name']?.toString() ?? 'System',
      deviceSecret: map['device_secret']?.toString() ?? '',
      appKey: map['app_key']?.toString() ?? 'pos',
      activatedAt: DateTime.tryParse(map['activated_at']?.toString() ?? '') ?? DateTime.now(),
      lastActiveAt: DateTime.tryParse(map['last_active_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
  factory ThqWorkspaceProfile.fromJson(String source) =>
      ThqWorkspaceProfile.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
