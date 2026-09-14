import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_installation_service.dart';

class LogisticsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic result) =>
      (result as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  Future<List<Map<String, dynamic>>> list({
    required String tenantId,
    String? locationId,
    String? status,
    String query = '',
  }) async => _rows(
    await _supabase.rpc(
      'logistics_trips_list_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_query': query.trim(),
        'p_limit': 500,
      },
    ),
  );

  Future<Map<String, dynamic>> detail({
    required String tenantId,
    required String tripId,
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_detail_v1',
      params: {'p_tenant_id': tenantId, 'p_trip_id': tripId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw StateError('Unexpected logistics trip detail response.');
  }

  Future<Map<String, dynamic>> create({
    required String tenantId,
    required String vehicleId,
    required List<String> transferIds,
    DateTime? plannedDepartureAt,
    String driverName = '',
    String driverPhone = '',
    String notes = '',
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_create_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_vehicle_id': vehicleId,
        'p_transfer_ids': transferIds,
        'p_planned_departure_at': plannedDepartureAt?.toUtc().toIso8601String(),
        'p_driver_name': driverName.trim(),
        'p_driver_phone': driverPhone.trim(),
        'p_notes': notes.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> startLoading({
    required String tenantId,
    required String tripId,
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_start_loading_v1',
      params: {'p_tenant_id': tenantId, 'p_trip_id': tripId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> dispatch({
    required String tenantId,
    required String tripId,
    String note = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'logistics_trip_dispatch_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_device_id': activation?.deviceId,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> arrive({
    required String tenantId,
    required String tripId,
    String note = '',
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_arrive_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> receiveTransfer({
    required String tenantId,
    required String tripId,
    required String transferId,
    String note = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'logistics_trip_receive_transfer_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_transfer_id': transferId,
        'p_device_id': activation?.deviceId,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> receiptContext({
    required String tenantId,
    required String tripId,
    required String transferId,
  }) async {
    final result = await _supabase.rpc(
      'logistics_transfer_receipt_context_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_transfer_id': transferId,
      },
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw StateError('Unexpected logistics receipt context response.');
  }

  Future<Map<String, dynamic>> receiveTransferReconciled({
    required String tenantId,
    required String tripId,
    required String transferId,
    required List<Map<String, dynamic>> lines,
    String note = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'logistics_trip_receive_transfer_reconciled_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_transfer_id': transferId,
        'p_device_id': activation?.deviceId,
        'p_lines': lines,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> reportsDashboard({
    required String tenantId,
    String? locationId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    String dateOnly(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

    final result = await _supabase.rpc(
      'logistics_reports_dashboard_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_from_date': dateOnly(fromDate),
        'p_to_date': dateOnly(toDate),
      },
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw StateError('Unexpected logistics reports response.');
  }

  Future<Map<String, dynamic>> close({
    required String tenantId,
    required String tripId,
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_close_v1',
      params: {'p_tenant_id': tenantId, 'p_trip_id': tripId},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> cancel({
    required String tenantId,
    required String tripId,
    required String reason,
  }) async {
    final result = await _supabase.rpc(
      'logistics_trip_cancel_v1',
      params: {
        'p_tenant_id': tenantId,
        'p_trip_id': tripId,
        'p_reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }
}
