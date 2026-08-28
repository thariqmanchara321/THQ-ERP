import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  SupabaseClient get _s => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list(String tenantId) async {
    final r = await _s.rpc(
      'business_location_tree_v42',
      params: {'p_tenant_id': tenantId},
    );
    return (r as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> stockOverview(String tenantId) async {
    final r = await _s.rpc(
      'inventory_location_overview_v42',
      params: {'p_tenant_id': tenantId},
    );
    return (r as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> directory(String tenantId) async {
    final r = await _s.rpc(
      'tenant_locations_devices_list_v42',
      params: {'p_tenant_id': tenantId},
    );
    if (r is! Map) throw Exception('Unexpected stores/systems response.');
    return Map<String, dynamic>.from(r);
  }

  Future<Map<String, dynamic>> summary(
    String tenantId, {
    String? locationId,
    DateTime? from,
    DateTime? to,
  }) async {
    String? date(DateTime? d) => d == null
        ? null
        : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = await _s.rpc(
      'location_business_summary',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_from_date': date(from),
        'p_to_date': date(to),
      },
    );
    if (r is! Map) throw Exception('Unexpected location report response.');
    return Map<String, dynamic>.from(r);
  }

  Future<String> saveLocation({
    required String tenantId,
    String? id,
    String? parentId,
    required String code,
    required String name,
    required String type,
    String phone = '',
    String email = '',
    String gstin = '',
    String addressLine1 = '',
    String addressLine2 = '',
    String city = '',
    String state = '',
    String postalCode = '',
    String country = 'India',
    String invoicePrefix = '',
    String logoUrl = '',
    String hierarchyRole = 'child_store',
    int sortOrder = 100,
    bool active = true,
  }) async {
    final r = await _s.rpc(
      'tenant_business_location_save_v42',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': id,
        'p_parent_location_id': parentId,
        'p_location_code': code,
        'p_name': name,
        'p_location_type': type,
        'p_hierarchy_role': hierarchyRole,
        'p_sort_order': sortOrder,
        'p_phone': phone,
        'p_email': email,
        'p_gstin': gstin,
        'p_address_line1': addressLine1,
        'p_address_line2': addressLine2,
        'p_city': city,
        'p_state': state,
        'p_postal_code': postalCode,
        'p_country': country,
        'p_invoice_prefix': invoicePrefix,
        'p_logo_url': logoUrl,
        'p_active': active,
      },
    );
    return r.toString();
  }

  Future<Map<String, dynamic>> issueDevice({
    required String tenantId,
    required String locationId,
    required String name,
    required String appType,
    required String platform,
    required List<String> modules,
    String invoicePrefix = '',
    String? systemRole,
  }) async {
    final r = await _s.rpc(
      'tenant_system_create_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_name': name,
        'p_app_type': appType,
        'p_platform_hint': platform,
        'p_module_keys': modules,
        'p_invoice_prefix': invoicePrefix,
        'p_system_role': systemRole,
      },
    );
    if (r is! Map) throw Exception('Unexpected activation response.');
    return Map<String, dynamic>.from(r);
  }

  Future<void> updateDevice({
    required String tenantId,
    required String deviceId,
    required String locationId,
    required String name,
    required List<String> modules,
    required String invoicePrefix,
    String? systemRole,
  }) async {
    await _s.rpc(
      'tenant_system_update_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_system_id': deviceId,
        'p_location_id': locationId,
        'p_module_keys': modules,
        'p_invoice_prefix': invoicePrefix,
        'p_name': name,
        'p_system_role': systemRole,
      },
    );
  }

  Future<void> revokeDevice({
    required String tenantId,
    required String deviceId,
  }) async {
    await _s.rpc(
      'tenant_system_revoke_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_system_id': deviceId,
        'p_reason': 'Revoked from THQ Client',
      },
    );
  }
}
