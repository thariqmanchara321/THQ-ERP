import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_installation_service.dart';

class StaffLoadService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<Map<String, dynamic>> staff({
    required String tenantId,
    required String action,
    String? locationId,
    Map<String, dynamic> data = const {},
  }) async {
    final result = await _db.rpc(
      'staff_workspace_v630',
      params: {
        'p_tenant_id': tenantId,
        'p_action': action,
        'p_data': data,
        'p_location_id': locationId,
      },
    );
    if (result is! Map) throw StateError('Unexpected Staff response.');
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> load({
    required String tenantId,
    required String action,
    String? locationId,
    Map<String, dynamic> data = const {},
  }) async {
    var payload = data;
    if (action == 'billing_service') {
      final activation = await DeviceInstallationService().readActivation();
      if (activation == null || activation.tenantId != tenantId) {
        throw StateError('This system is not activated for this business.');
      }
      payload = {...data, 'device_id': activation.deviceId};
    }
    final result = await _db.rpc(
      'material_load_workspace_v630',
      params: {
        'p_tenant_id': tenantId,
        'p_action': action,
        'p_data': payload,
        'p_location_id': locationId,
      },
    );
    if (result is! Map) throw StateError('Unexpected load response.');
    return Map<String, dynamic>.from(result);
  }

  static List<Map<String, dynamic>> rows(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  static double number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  static String date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
