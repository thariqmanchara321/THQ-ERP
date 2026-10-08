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
    if (!const {
      'list',
      'detail',
      'statement',
      'report',
      'save',
      'payroll',
      'payment',
    }.contains(action)) {
      throw StateError('Staff supports profiles, payroll and payments only.');
    }
    final result = await _db.rpc(
      action == 'statement' ? 'staff_statement_v634' : 'staff_workspace_v630',
      params: action == 'statement'
          ? {
              'p_tenant_id': tenantId,
              'p_staff_id': data['staff_id'],
              'p_from': data['from'],
              'p_to': data['to'],
              'p_location_id': locationId,
            }
          : {
              'p_tenant_id': tenantId,
              'p_action': action,
              'p_data': data,
              'p_location_id': locationId,
            },
    );
    if (result is! Map) throw StateError('Unexpected Staff response.');
    return staffRecord(Map<String, dynamic>.from(result));
  }

  // Keep older backend responses out of Staff statements and exports too.
  static Map<String, dynamic> staffRecord(Map<String, dynamic> record) => {
    for (final entry in record.entries)
      if (!const {'attendance', 'staff_attendance'}.contains(entry.key))
        entry.key: entry.key == 'history'
            ? rows(entry.value)
                  .where((row) => !'${row['action']}'.startsWith('attendance.'))
                  .toList()
            : entry.value,
  };

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
