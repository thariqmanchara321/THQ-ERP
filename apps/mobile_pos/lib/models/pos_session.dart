import 'package:erp_core/erp_core.dart';

class PosSession {
  final String tenantId;
  final String businessName;
  final String logoUrl;
  final String deviceId;
  final String deviceCode;
  final String deviceName;
  final String locationId;
  final String locationCode;
  final String locationName;
  final String currencyCode;
  final String username;
  final bool restaurantEnabled;
  final Set<String> allowedModules;
  final ThqMobileReleaseStatus release;

  const PosSession({
    required this.tenantId,
    required this.businessName,
    this.logoUrl = '',
    required this.deviceId,
    required this.deviceCode,
    required this.deviceName,
    required this.locationId,
    required this.locationCode,
    required this.locationName,
    required this.currencyCode,
    required this.username,
    required this.restaurantEnabled,
    required this.release,
    this.allowedModules = const <String>{},
  });

  bool hasDeviceModule(String module) =>
      allowedModules.contains(module.trim().toLowerCase());
}
