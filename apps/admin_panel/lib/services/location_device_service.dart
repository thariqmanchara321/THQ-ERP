import 'package:supabase_flutter/supabase_flutter.dart';

class LocationDeviceService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> identity(String tenantId) async {
    final result = await _supabase.rpc(
      'platform_business_identity',
      params: {'p_tenant_id': tenantId},
    );
    return result is Map ? Map<String, dynamic>.from(result) : {};
  }

  Future<List<Map<String, dynamic>>> locations(String tenantId) async {
    final result = await _supabase.rpc(
      'platform_business_locations_list',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> devices(String tenantId) async {
    final result = await _supabase.rpc(
      'platform_business_devices_list',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> nextPosInvoicePrefix(String tenantId) async {
    final result = await _supabase.rpc(
      'platform_next_pos_invoice_prefix_v500',
      params: {'p_tenant_id': tenantId},
    );
    final value = result?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw Exception('Could not allocate the next POS invoice prefix.');
    }
    return value;
  }

  Future<void> saveLocation({
    required String tenantId,
    String? id,
    String? parentLocationId,
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
    String postal = '',
    String country = 'India',
    String invoicePrefix = '',
    String hierarchyRole = 'child_store',
    int sortOrder = 100,
    bool active = true,
  }) {
    return _supabase.rpc(
      'platform_business_location_save_v42',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': id,
        'p_parent_location_id': parentLocationId,
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
        'p_postal_code': postal,
        'p_country': country,
        'p_invoice_prefix': invoicePrefix,
        'p_active': active,
      },
    );
  }

  Future<Map<String, dynamic>> issue({
    required String tenantId,
    required String locationId,
    required String name,
    required String appType,
    String? platformHint,
    List<String> moduleKeys = const <String>[],
    String invoicePrefix = '',
  }) async {
    final result = await _supabase.rpc(
      'platform_device_issue_activation_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_name': name,
        'p_app_type': appType,
        'p_platform_hint': platformHint,
        'p_module_keys': moduleKeys,
        'p_invoice_prefix': invoicePrefix,
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected activation response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> updateDevice({
    required String tenantId,
    required String deviceId,
    required String locationId,
    required String name,
    required List<String> moduleKeys,
    required String invoicePrefix,
    required String systemRole,
  }) async {
    final result = await _supabase.rpc(
      'platform_system_update_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_system_id': deviceId,
        'p_location_id': locationId,
        'p_name': name,
        'p_module_keys': moduleKeys,
        'p_invoice_prefix': invoicePrefix,
        'p_system_role': systemRole,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createSystem({
    required String tenantId,
    required String locationId,
    required String name,
    required String appType,
    required String systemRole,
    String? platformHint,
    List<String> moduleKeys = const <String>[],
    String invoicePrefix = '',
  }) async {
    final result = await _supabase.rpc(
      'platform_system_create_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_name': name,
        'p_app_type': appType,
        'p_platform_hint': platformHint,
        'p_module_keys': moduleKeys,
        'p_invoice_prefix': invoicePrefix.isEmpty ? null : invoicePrefix,
        'p_system_role': systemRole,
      },
    );
    if (result is! Map) throw Exception('Unexpected system creation response.');
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> systemsV46(String tenantId) async {
    final result = await _supabase.rpc(
      'platform_systems_list_v471',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> deleteSystem({
    required String tenantId,
    required String systemId,
    String reason = '',
  }) async {
    final result = await _supabase.rpc(
      'platform_system_delete_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_system_id': systemId,
        'p_reason': reason.trim().isEmpty ? null : reason.trim(),
      },
    );
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> deleteLocation({
    required String tenantId,
    required String locationId,
    String reason = '',
  }) async {
    final result = await _supabase.rpc(
      'platform_location_delete_v471',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_reason': reason.trim().isEmpty ? null : reason.trim(),
      },
    );
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> activateSystem({
    required String tenantId,
    required String deviceId,
  }) async {
    final result = await _supabase.rpc(
      'platform_system_activate_v46',
      params: {'p_tenant_id': tenantId, 'p_device_id': deviceId},
    );
    if (result is! Map) throw Exception('Unexpected activation response.');
    return Map<String, dynamic>.from(result);
  }

  Future<void> deactivateSystem(
    String tenantId,
    String deviceId, {
    String reason = '',
  }) {
    return _supabase.rpc(
      'platform_system_deactivate_v46',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_reason': reason.isEmpty ? null : reason,
      },
    );
  }

  Future<void> revoke(String tenantId, String deviceId) {
    return _supabase.rpc(
      'platform_device_revoke',
      params: {'p_tenant_id': tenantId, 'p_device_id': deviceId},
    );
  }
}
