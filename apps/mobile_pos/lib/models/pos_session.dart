class PosSession {
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
  final bool restaurantEnabled;

  const PosSession({
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
    required this.restaurantEnabled,
  });
}
