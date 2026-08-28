import 'package:supabase_flutter/supabase_flutter.dart';

class PosCompletionService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> printerProfiles({
    required String tenantId,
    required String deviceId,
  }) async {
    final result = await _supabase.rpc(
      'pos_printer_profiles_list_v44',
      params: {'p_tenant_id': tenantId, 'p_device_id': deviceId},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<String> savePrinterProfile({
    required String tenantId,
    required String deviceId,
    String? profileId,
    required String name,
    required String purpose,
    required String paperSize,
    required String printerName,
    String routeName = '',
    int copies = 1,
    bool autoPrint = false,
    bool cashDrawerEnabled = false,
    String cashDrawerCommand = 'standard',
    bool isDefault = false,
    bool active = true,
    Map<String, dynamic> settings = const {},
  }) async {
    final result = await _supabase.rpc(
      'pos_printer_profile_save_v44',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_profile_id': profileId,
        'p_name': name,
        'p_purpose': purpose,
        'p_paper_size': paperSize,
        'p_printer_name': printerName,
        'p_route_name': routeName,
        'p_copies': copies,
        'p_auto_print': autoPrint,
        'p_cash_drawer_enabled': cashDrawerEnabled,
        'p_cash_drawer_command': cashDrawerCommand,
        'p_is_default': isDefault,
        'p_active': active,
        'p_settings': settings,
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> getPreferences({
    required String tenantId,
    required String deviceId,
  }) async {
    final result = await _supabase.rpc(
      'pos_device_preferences_get_v44',
      params: {'p_tenant_id': tenantId, 'p_device_id': deviceId},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void> setPreferences({
    required String tenantId,
    required String deviceId,
    required Map<String, dynamic> settings,
  }) async {
    await _supabase.rpc(
      'pos_device_preferences_set_v44',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_settings': settings,
      },
    );
  }

  Future<Map<String, dynamic>> holdSale({
    required String tenantId,
    required String deviceId,
    String? customerId,
    String label = '',
    required Map<String, dynamic> state,
  }) async {
    final result = await _supabase.rpc(
      'pos_hold_sale_v44',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_customer_id': customerId,
        'p_label': label,
        'p_state': state,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> heldSales({
    required String tenantId,
    required String deviceId,
  }) async {
    final result = await _supabase.rpc(
      'pos_held_sales_feed_v471',
      params: {'p_tenant_id': tenantId, 'p_device_id': deviceId},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> getHeldSale({
    required String tenantId,
    required String deviceId,
    required String holdId,
  }) async {
    final result = await _supabase.rpc(
      'pos_held_sale_get_v44',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_hold_id': holdId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void> deleteHeldSale({
    required String tenantId,
    required String deviceId,
    required String holdId,
  }) async {
    await _supabase.rpc(
      'pos_held_sale_delete_v44',
      params: {
        'p_tenant_id': tenantId,
        'p_device_id': deviceId,
        'p_hold_id': holdId,
      },
    );
  }
}
