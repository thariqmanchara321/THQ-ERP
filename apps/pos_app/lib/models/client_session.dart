class ClientBusiness {
  final String id;
  final String membershipId;
  final String name;
  final String slug;
  final String? businessType;
  final String status;

  const ClientBusiness({
    required this.id,
    required this.membershipId,
    required this.name,
    required this.slug,
    required this.businessType,
    required this.status,
  });
}

class ClientModule {
  final String key;
  final String name;
  final String? description;
  final String category;
  final int sortOrder;

  const ClientModule({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.sortOrder,
  });

  factory ClientModule.fromMap(Map<String, dynamic> map) {
    return ClientModule(
      key: map['key']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString(),
      category: map['category']?.toString() ?? 'general',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class ClientSubscription {
  final String? planKey;
  final String? planName;
  final String status;
  final String billingCycle;
  final Set<String> entitledModules;
  final Map<String, dynamic> limits;

  const ClientSubscription({
    required this.planKey,
    required this.planName,
    required this.status,
    required this.billingCycle,
    required this.entitledModules,
    required this.limits,
  });

  bool get hasPlan => planKey != null && planKey!.isNotEmpty;
  bool get blocksAccess => status == 'suspended' || status == 'cancelled';

  factory ClientSubscription.fromMap(Map<String, dynamic> map) {
    return ClientSubscription(
      planKey: map['plan_key']?.toString(),
      planName: map['plan_name']?.toString(),
      status: map['status']?.toString() ?? 'none',
      billingCycle: map['billing_cycle']?.toString() ?? 'monthly',
      entitledModules: (map['entitled_modules'] as List? ?? const [])
          .map((e) => e.toString())
          .toSet(),
      limits: map['limits'] is Map
          ? Map<String, dynamic>.from(map['limits'] as Map)
          : <String, dynamic>{},
    );
  }

  static const none = ClientSubscription(
    planKey: null,
    planName: null,
    status: 'none',
    billingCycle: 'monthly',
    entitledModules: <String>{},
    limits: <String, dynamic>{},
  );
}

class ClientLocationAccess {
  final String id;
  final String code;
  final String name;
  final String type;
  final String? trackingCode;
  final String accessLevel;

  const ClientLocationAccess({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.trackingCode,
    required this.accessLevel,
  });

  factory ClientLocationAccess.fromMap(Map<String, dynamic> map) {
    return ClientLocationAccess(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? map['location_code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      type:
          map['type']?.toString() ??
          map['location_type']?.toString() ??
          'store',
      trackingCode: map['tracking_code']?.toString(),
      accessLevel: map['access_level']?.toString() ?? 'view',
    );
  }
}

class ClientDeviceContext {
  final String deviceId;
  final String deviceCode;
  final String deviceName;
  final String locationId;
  final String locationName;
  final String locationCode;
  final Set<String> allowedModules;

  const ClientDeviceContext({
    required this.deviceId,
    required this.deviceCode,
    required this.deviceName,
    required this.locationId,
    required this.locationName,
    required this.locationCode,
    this.allowedModules = const <String>{},
  });

  bool allows(String moduleKey) =>
      allowedModules.isEmpty || allowedModules.contains(moduleKey);
}

class ClientSession {
  final ClientBusiness business;
  final String userId;
  final String username;
  final List<ClientModule> modules;
  final Set<String> roles;
  final Set<String> permissions;
  final String currencyCode;
  final String timezone;
  final String locale;
  final ClientSubscription subscription;
  final Map<String, dynamic> settings;
  final ClientDeviceContext? device;
  final List<ClientLocationAccess> locations;
  final bool canViewAllLocations;

  const ClientSession({
    required this.business,
    this.userId = '',
    this.username = '',
    required this.modules,
    required this.roles,
    required this.permissions,
    required this.currencyCode,
    required this.timezone,
    required this.locale,
    this.subscription = ClientSubscription.none,
    this.settings = const <String, dynamic>{},
    this.device,
    this.locations = const <ClientLocationAccess>[],
    this.canViewAllLocations = false,
  });

  String get roleLabel => roles.isEmpty
      ? 'User'
      : roles.map((e) => e.replaceAll('_', ' ')).join(' • ');

  bool hasModule(String key) => modules.any((module) => module.key == key);
  bool hasRole(String key) => roles.contains(key);
  bool hasPermission(String key) => permissions.contains(key);

  bool isEntitled(String moduleKey) {
    if (!subscription.hasPlan || subscription.entitledModules.isEmpty) {
      return true;
    }
    if (subscription.entitledModules.contains(moduleKey)) return true;
    if ((moduleKey == 'cashier_shifts' || moduleKey == 'terminal_day') &&
        subscription.entitledModules.contains('pos')) {
      return true;
    }
    return false;
  }

  bool canAccessLocation(String id) =>
      canViewAllLocations || locations.any((location) => location.id == id);
  bool deviceAllows(String moduleKey) => device?.allows(moduleKey) ?? true;

  dynamic setting(String key, [dynamic fallback]) =>
      settings.containsKey(key) ? settings[key] : fallback;
}
