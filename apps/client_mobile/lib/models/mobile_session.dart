import 'package:erp_core/erp_core.dart';

class MobileLocation {
  final String id;
  final String code;
  final String name;
  final String accessLevel;

  const MobileLocation({
    required this.id,
    required this.code,
    required this.name,
    required this.accessLevel,
  });

  factory MobileLocation.fromMap(Map<String, dynamic> map) => MobileLocation(
    id: map['id']?.toString() ?? '',
    code: map['code']?.toString() ?? map['location_code']?.toString() ?? '',
    name: map['name']?.toString() ?? map['location_name']?.toString() ?? '',
    accessLevel: map['access_level']?.toString() ?? 'view',
  );
}

class MobileSession {
  final String tenantId;
  final String businessName;
  final String deviceId;
  final String deviceCode;
  final String deviceName;
  final String locationId;
  final String locationCode;
  final String locationName;
  final String currencyCode;
  final String username;
  final bool canViewAllLocations;
  final bool canApprove;
  final bool canReceiveCustomerPayment;
  final bool canViewNotifications;
  final bool canViewAudit;
  final bool canViewTraceability;
  final bool canViewWarranty;
  final List<MobileLocation> locations;
  final ThqMobileReleaseStatus release;

  const MobileSession({
    required this.tenantId,
    required this.businessName,
    required this.deviceId,
    required this.deviceCode,
    required this.deviceName,
    required this.locationId,
    required this.locationCode,
    required this.locationName,
    required this.currencyCode,
    required this.username,
    required this.canViewAllLocations,
    required this.canApprove,
    required this.canReceiveCustomerPayment,
    required this.canViewNotifications,
    required this.canViewAudit,
    required this.canViewTraceability,
    required this.canViewWarranty,
    required this.locations,
    required this.release,
  });
}
