import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import 'app_log_service.dart';
import 'device_installation_service.dart';

class ClientSessionService {
  final String appKey;
  ClientSessionService({this.appKey = 'client'});

  SupabaseClient get _supabase => Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Future<List<ClientBusiness>> getAvailableBusinesses() async {
    final user = currentUser;

    if (user == null) {
      throw Exception('User is not signed in.');
    }

    final activation = await DeviceInstallationService().readActivation();
    if (activation == null) {
      throw Exception('This system must be activated first.');
    }

    final membershipResult = await _supabase
        .from('tenant_memberships')
        .select('id, tenant_id, status, joined_at')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .eq('tenant_id', activation.tenantId)
        .order('joined_at');

    final membershipRows = (membershipResult as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    if (membershipRows.isEmpty) {
      return [];
    }

    final tenantIds = membershipRows
        .map((row) => row['tenant_id'].toString())
        .toList();

    final tenantResult = await _supabase
        .from('tenants')
        .select('id, name, slug, business_type, status')
        .inFilter('id', tenantIds);

    final tenantRows = (tenantResult as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    final membershipByTenant = <String, Map<String, dynamic>>{};

    for (final membership in membershipRows) {
      membershipByTenant[membership['tenant_id'].toString()] = membership;
    }

    final businesses = <ClientBusiness>[];

    for (final tenant in tenantRows) {
      final tenantId = tenant['id'].toString();

      final membership = membershipByTenant[tenantId];

      if (membership == null) {
        continue;
      }

      if (tenant['status']?.toString() != 'active') {
        continue;
      }

      businesses.add(
        ClientBusiness(
          id: tenantId,
          membershipId: membership['id'].toString(),
          name: tenant['name']?.toString() ?? '',
          slug: tenant['slug']?.toString() ?? '',
          businessType: tenant['business_type']?.toString(),
          status: tenant['status']?.toString() ?? '',
        ),
      );
    }

    businesses.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return businesses;
  }

  Future<ClientSession> loadSession({required ClientBusiness business, bool requireRuntime = false}) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != business.id) {
      throw Exception('This system is not activated for this business.');
    }

    final tenantModuleResult = await _supabase
        .from('tenant_modules')
        .select('module_key, enabled')
        .eq('tenant_id', business.id)
        .eq('enabled', true);

    final tenantModuleRows = (tenantModuleResult as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    final moduleKeys = tenantModuleRows
        .map((row) => row['module_key'].toString())
        .toList();

    final modules = <ClientModule>[];

    if (moduleKeys.isNotEmpty) {
      final moduleResult = await _supabase
          .from('modules')
          .select('key, name, description, category, sort_order')
          .inFilter('key', moduleKeys)
          .order('sort_order');

      final moduleRows = (moduleResult as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      modules.addAll(moduleRows.map(ClientModule.fromMap));
    }

    final userRoleResult = await _supabase
        .from('user_roles')
        .select('role_id')
        .eq('tenant_id', business.id)
        .eq('membership_id', business.membershipId);

    final userRoleRows = (userRoleResult as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    final roleIds = userRoleRows
        .map((row) => row['role_id'].toString())
        .toList();

    final roleKeys = <String>{};
    final permissionKeys = <String>{};

    if (roleIds.isNotEmpty) {
      final roleResult = await _supabase
          .from('roles')
          .select('id, key, name')
          .inFilter('id', roleIds);

      final roleRows = (roleResult as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      roleKeys.addAll(roleRows.map((row) => row['key'].toString()));

      final permissionResult = await _supabase
          .from('role_permissions')
          .select('role_id, permission_key')
          .inFilter('role_id', roleIds);

      final permissionRows = (permissionResult as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      permissionKeys.addAll(
        permissionRows.map((row) => row['permission_key'].toString()),
      );
    }

    final settingsResult = await _supabase
        .from('tenant_settings')
        .select('currency_code, timezone, locale')
        .eq('tenant_id', business.id)
        .maybeSingle();

    final settings = settingsResult == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(settingsResult);

    ClientSubscription subscription = ClientSubscription.none;
    Map<String, dynamic> v2Settings = <String, dynamic>{};

    try {
      final subscriptionResult = await _supabase.rpc(
        'client_subscription_context',
        params: {'p_tenant_id': business.id},
      );
      if (subscriptionResult is Map) {
        subscription = ClientSubscription.fromMap(
          Map<String, dynamic>.from(subscriptionResult),
        );
      }
    } catch (_) {
      // Backward-compatible while Platform V2 migrations are being installed.
    }

    try {
      final v2SettingsResult = await _supabase.rpc(
        'tenant_settings_v2_get',
        params: {'p_tenant_id': business.id},
      );
      if (v2SettingsResult is Map) {
        v2Settings = Map<String, dynamic>.from(v2SettingsResult);
      }
    } catch (_) {
      // Existing tenant_settings remains the source for currency/locale/timezone.
    }

    Map<String, dynamic> runtime = <String, dynamic>{};
    try {
      final runtimeResult = await _supabase.rpc(
        'client_runtime_context_v4',
        params: {
          'p_tenant_id': business.id,
          'p_device_id': activation.deviceId,
          'p_app_key': appKey,
        },
      );
      if (runtimeResult is Map) {
        runtime = Map<String, dynamic>.from(runtimeResult);
      }
    } catch (error) {
      if (requireRuntime) {
        throw Exception('Unable to refresh system/store configuration: $error');
      }
      // Login remains readable during staged deployment; an explicit Refresh is strict.
    }

    final runtimeLocations = (runtime['locations'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => ClientLocationAccess.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
    final runtimeDeviceModules =
        (runtime['device_modules'] as List? ?? const [])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toSet();
    final runtimeDeviceCode = runtime['device_code']?.toString() ?? activation.deviceCode;
    final runtimeDeviceName = runtime['device_name']?.toString() ?? activation.deviceName;
    final runtimeLocationId = runtime['location_id']?.toString() ?? activation.locationId;
    final runtimeLocationCode = runtime['location_code']?.toString() ?? activation.locationCode;
    final runtimeLocationName = runtime['location_name']?.toString() ?? activation.locationName;
    final canViewAllLocations = runtime['can_view_all_locations'] == true;
    final runtimeUsername = runtime['username']?.toString() ?? '';
    final runtimeUserId =
        runtime['user_id']?.toString() ?? currentUser?.id ?? '';

    final visibleModules = modules.where((module) {
      if (module.key == 'pos') {
        return false; // POS remains a separate application.
      }
      if (subscription.blocksAccess) return module.key == 'dashboard';
      if (!subscription.hasPlan || subscription.entitledModules.isEmpty) {
        return true;
      }
      return subscription.entitledModules.contains(module.key);
    }).toList();

    await DeviceInstallationService().updateRuntimeBinding(
      deviceCode: runtimeDeviceCode,
      deviceName: runtimeDeviceName,
      locationId: runtimeLocationId,
      locationName: runtimeLocationName,
      locationCode: runtimeLocationCode,
    );

    AppLogService.activeTenantId = business.id;

    return ClientSession(
      business: business,
      userId: runtimeUserId,
      username: runtimeUsername,
      modules: visibleModules,
      roles: roleKeys,
      permissions: permissionKeys,
      currencyCode: settings['currency_code']?.toString() ?? 'INR',
      timezone: settings['timezone']?.toString() ?? 'Asia/Kolkata',
      locale: settings['locale']?.toString() ?? 'en_IN',
      subscription: subscription,
      settings: v2Settings,
      device: ClientDeviceContext(
        deviceId: activation.deviceId,
        deviceCode: runtimeDeviceCode,
        deviceName: runtimeDeviceName,
        locationId: runtimeLocationId,
        locationName: runtimeLocationName,
        locationCode: runtimeLocationCode,
        allowedModules: runtimeDeviceModules,
      ),
      locations: runtimeLocations.isEmpty
          ? <ClientLocationAccess>[
              ClientLocationAccess(
                id: activation.locationId,
                code: activation.locationCode,
                name: activation.locationName,
                type: 'store',
                trackingCode: null,
                accessLevel: 'operate',
              ),
            ]
          : runtimeLocations,
      canViewAllLocations: canViewAllLocations,
    );
  }
}
