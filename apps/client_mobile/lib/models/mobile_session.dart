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
  final String logoUrl;
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
  final Set<String> roles;
  final Set<String> permissions;
  final Set<String> enabledModules;
  final Map<String, dynamic> settings;

  const MobileSession({
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
    required this.canViewAllLocations,
    required this.canApprove,
    required this.canReceiveCustomerPayment,
    required this.canViewNotifications,
    required this.canViewAudit,
    required this.canViewTraceability,
    required this.canViewWarranty,
    required this.locations,
    required this.release,
    this.roles = const <String>{},
    this.permissions = const <String>{},
    this.enabledModules = const <String>{},
    this.settings = const <String, dynamic>{},
  });

  String get currency => currencyCode;

  bool hasRole(String role) => roles.contains(role);
  bool hasPermission(String perm) => permissions.contains(perm);
  bool hasModule(String module) => enabledModules.contains(module);

  dynamic setting(String key, [dynamic fallback]) {
    if (settings.containsKey(key)) return settings[key];
    if (key == 'sales.show_standalone_new') {
      if (settings['sales_purchases'] is Map &&
          settings['sales_purchases']['show_standalone_new_sale'] != null) {
        return settings['sales_purchases']['show_standalone_new_sale'];
      }
      if (settings['sales'] is Map &&
          settings['sales']['show_standalone_new'] != null) {
        return settings['sales']['show_standalone_new'];
      }
    }
    if (key == 'purchases.show_standalone_new') {
      if (settings['sales_purchases'] is Map &&
          settings['sales_purchases']['show_standalone_new_purchase'] != null) {
        return settings['sales_purchases']['show_standalone_new_purchase'];
      }
      if (settings['purchases'] is Map &&
          settings['purchases']['show_standalone_new'] != null) {
        return settings['purchases']['show_standalone_new'];
      }
    }
    if (key == 'sales.preferred_entry') {
      if (settings['sales_purchases'] is Map &&
          settings['sales_purchases']['preferred_transaction_entry'] != null) {
        return settings['sales_purchases']['preferred_transaction_entry'];
      }
      if (settings['sales'] is Map &&
          settings['sales']['preferred_entry'] != null) {
        return settings['sales']['preferred_entry'];
      }
    }
    return fallback;
  }

  bool get showStandaloneNewSale =>
      setting('sales.show_standalone_new', true) == true;

  bool get showStandaloneNewPurchase =>
      setting('purchases.show_standalone_new', true) == true;

  String get preferredTransactionEntry =>
      setting('sales.preferred_entry', 'standard')?.toString() ?? 'standard';

  bool get isOwner => hasRole('owner');
  bool get canManageMaterialYard =>
      isOwner ||
      hasPermission('aggregate_yard.manage') ||
      hasPermission('operations.manage');
  bool get canManageRates =>
      isOwner ||
      hasPermission('aggregate_yard.manage') ||
      hasPermission('daily_rates.manage');
  bool get canViewReceivables =>
      isOwner ||
      hasPermission('financial.receivables.view') ||
      hasPermission('accounting.view') ||
      hasPermission('sales.view');
  bool get canViewPayables =>
      isOwner ||
      hasPermission('financial.payables.view') ||
      hasPermission('accounting.view') ||
      hasPermission('purchases.view');

  MobileSession copyWith({
    String? tenantId,
    String? businessName,
    String? logoUrl,
    String? deviceId,
    String? deviceCode,
    String? deviceName,
    String? locationId,
    String? locationCode,
    String? locationName,
    String? currencyCode,
    String? username,
    bool? canViewAllLocations,
    bool? canApprove,
    bool? canReceiveCustomerPayment,
    bool? canViewNotifications,
    bool? canViewAudit,
    bool? canViewTraceability,
    bool? canViewWarranty,
    List<MobileLocation>? locations,
    ThqMobileReleaseStatus? release,
    Set<String>? roles,
    Set<String>? permissions,
    Set<String>? enabledModules,
    Map<String, dynamic>? settings,
  }) =>
      MobileSession(
        tenantId: tenantId ?? this.tenantId,
        businessName: businessName ?? this.businessName,
        logoUrl: logoUrl ?? this.logoUrl,
        deviceId: deviceId ?? this.deviceId,
        deviceCode: deviceCode ?? this.deviceCode,
        deviceName: deviceName ?? this.deviceName,
        locationId: locationId ?? this.locationId,
        locationCode: locationCode ?? this.locationCode,
        locationName: locationName ?? this.locationName,
        currencyCode: currencyCode ?? this.currencyCode,
        username: username ?? this.username,
        canViewAllLocations: canViewAllLocations ?? this.canViewAllLocations,
        canApprove: canApprove ?? this.canApprove,
        canReceiveCustomerPayment:
            canReceiveCustomerPayment ?? this.canReceiveCustomerPayment,
        canViewNotifications: canViewNotifications ?? this.canViewNotifications,
        canViewAudit: canViewAudit ?? this.canViewAudit,
        canViewTraceability: canViewTraceability ?? this.canViewTraceability,
        canViewWarranty: canViewWarranty ?? this.canViewWarranty,
        locations: locations ?? this.locations,
        release: release ?? this.release,
        roles: roles ?? this.roles,
        permissions: permissions ?? this.permissions,
        enabledModules: enabledModules ?? this.enabledModules,
        settings: settings ?? this.settings,
      );
}
