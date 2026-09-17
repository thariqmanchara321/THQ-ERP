import 'package:supabase_flutter/supabase_flutter.dart';

class ThqLogisticsApi {
  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<List<Map<String, dynamic>>> operations({
    required String tenantId,
    String? locationId,
    String? status,
    String? query,
  }) async => _rows(
    await _db.rpc(
      'logistics_operations_list_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_query': query,
        'p_limit': 500,
      },
    ),
  );

  Future<Map<String, dynamic>> detail({
    required String tenantId,
    required String operationId,
  }) async => _map(
    await _db.rpc(
      'logistics_operation_detail_v61',
      params: {'p_tenant_id': tenantId, 'p_operation_id': operationId},
    ),
  );

  Future<Map<String, dynamic>> dashboard({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async => _map(
    await _db.rpc(
      'logistics_dashboard_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_from_date': date(from),
        'p_to_date': date(to),
      },
    ),
  );

  Future<List<Map<String, dynamic>>> vehicles({
    required String tenantId,
    String? locationId,
  }) async => _rows(
    await _db.rpc(
      'service_vehicles_list_v51',
      params: {'p_tenant_id': tenantId, 'p_location_id': locationId},
    ),
  );

  Future<List<Map<String, dynamic>>> drivers(String tenantId) async => _rows(
    await _db.rpc(
      'logistics_drivers_list_v61',
      params: {'p_tenant_id': tenantId, 'p_active_only': false},
    ),
  );

  Future<List<Map<String, dynamic>>> destinations(String tenantId) async =>
      _rows(
        await _db.rpc(
          'logistics_destinations_list_v61',
          params: {'p_tenant_id': tenantId, 'p_active_only': false},
        ),
      );

  Future<Map<String, dynamic>> saveOperation({
    required String tenantId,
    String? operationId,
    required DateTime operationDate,
    String? baseLocationId,
    required String title,
    required String purpose,
    required String primaryUnit,
    String? secondaryUnit,
    required String coordinator,
    required String notes,
  }) async => _map(
    await _db.rpc(
      'logistics_operation_save_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_operation_id': operationId,
        'p_operation_date': date(operationDate),
        'p_base_location_id': baseLocationId,
        'p_title': title,
        'p_purpose': purpose,
        'p_primary_unit': primaryUnit,
        'p_secondary_unit': secondaryUnit,
        'p_coordinator_name': coordinator,
        'p_notes': notes,
      },
    ),
  );

  Future<Map<String, dynamic>> saveRun({
    required String tenantId,
    required String operationId,
    String? runId,
    String? vehicleId,
    String? driverId,
    required String driverName,
    required String driverPhone,
    DateTime? plannedDeparture,
    required double startingPrimary,
    double? startingSecondary,
    required String notes,
  }) async => _map(
    await _db.rpc(
      'logistics_run_save_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_operation_id': operationId,
        'p_run_id': runId,
        'p_vehicle_id': vehicleId,
        'p_driver_id': driverId,
        'p_driver_name': driverName,
        'p_driver_phone': driverPhone,
        'p_planned_departure_at': plannedDeparture?.toUtc().toIso8601String(),
        'p_starting_primary_qty': startingPrimary,
        'p_starting_secondary_qty': startingSecondary,
        'p_notes': notes,
      },
    ),
  );

  Future<Map<String, dynamic>> saveStop({
    required String tenantId,
    required String runId,
    String? stopId,
    required String actionType,
    String? destinationId,
    required String destinationName,
    String? linkedDocumentType,
    String? linkedDocumentReference,
    required double plannedPickupPrimary,
    required double plannedDeliveryPrimary,
    double? plannedPickupSecondary,
    double? plannedDeliverySecondary,
    required String note,
  }) async => _map(
    await _db.rpc(
      'logistics_stop_save_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_run_id': runId,
        'p_stop_id': stopId,
        'p_action_type': actionType,
        'p_destination_id': destinationId,
        'p_destination_name': destinationName,
        'p_linked_document_type': linkedDocumentType,
        'p_linked_document_id': null,
        'p_linked_document_reference': linkedDocumentReference,
        'p_planned_pickup_primary_qty': plannedPickupPrimary,
        'p_planned_delivery_primary_qty': plannedDeliveryPrimary,
        'p_planned_pickup_secondary_qty': plannedPickupSecondary,
        'p_planned_delivery_secondary_qty': plannedDeliverySecondary,
        'p_note': note,
      },
    ),
  );

  Future<Map<String, dynamic>> completeStop({
    required String tenantId,
    required String stopId,
    required double pickupPrimary,
    required double deliveryPrimary,
    double? pickupSecondary,
    double? deliverySecondary,
    required double variancePrimary,
    double? varianceSecondary,
    String? varianceReason,
    required String receiver,
    required String note,
  }) async => _map(
    await _db.rpc(
      'logistics_stop_complete_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_stop_id': stopId,
        'p_actual_pickup_primary_qty': pickupPrimary,
        'p_actual_delivery_primary_qty': deliveryPrimary,
        'p_actual_pickup_secondary_qty': pickupSecondary,
        'p_actual_delivery_secondary_qty': deliverySecondary,
        'p_variance_primary_qty': variancePrimary,
        'p_variance_secondary_qty': varianceSecondary,
        'p_variance_reason': varianceReason,
        'p_receiver_name': receiver,
        'p_note': note,
      },
    ),
  );

  Future<Map<String, dynamic>> runStatus({
    required String tenantId,
    required String runId,
    required String status,
    String? note,
  }) async => _map(
    await _db.rpc(
      'logistics_run_status_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_run_id': runId,
        'p_status': status,
        'p_note': note,
      },
    ),
  );

  Future<Map<String, dynamic>> operationStatus({
    required String tenantId,
    required String operationId,
    required String status,
    String? reason,
  }) async => _map(
    await _db.rpc(
      'logistics_operation_status_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_operation_id': operationId,
        'p_status': status,
        'p_reason': reason,
      },
    ),
  );

  Future<Map<String, dynamic>> saveDriver({
    required String tenantId,
    required String name,
    required String phone,
    required String license,
    required String notes,
  }) async => _map(
    await _db.rpc(
      'logistics_driver_save_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_driver_id': null,
        'p_name': name,
        'p_phone': phone,
        'p_license_number': license,
        'p_notes': notes,
        'p_active': true,
      },
    ),
  );

  Future<Map<String, dynamic>> saveDestination({
    required String tenantId,
    required String type,
    required String name,
    required String code,
    required String address,
    required String contact,
    required String phone,
    required String notes,
  }) async => _map(
    await _db.rpc(
      'logistics_destination_save_v61',
      params: {
        'p_tenant_id': tenantId,
        'p_destination_id': null,
        'p_destination_type': type,
        'p_name': name,
        'p_code': code,
        'p_address': address,
        'p_contact_person': contact,
        'p_phone': phone,
        'p_notes': notes,
        'p_active': true,
      },
    ),
  );

  Future<String> saveVehicle({
    required String tenantId,
    required String locationId,
    required String registration,
    required String vehicleType,
    required String makeModel,
    required double capacity,
    required String capacityUnit,
    required String driverName,
    required String driverPhone,
  }) async => (await _db.rpc(
    'service_vehicle_save_v51',
    params: {
      'p_tenant_id': tenantId,
      'p_vehicle_id': null,
      'p_location_id': locationId,
      'p_registration_number': registration,
      'p_vehicle_type': vehicleType,
      'p_make_model': makeModel,
      'p_capacity': capacity,
      'p_capacity_unit': capacityUnit,
      'p_driver_name': driverName,
      'p_driver_phone': driverPhone,
      'p_active': true,
    },
  )).toString();

  static String date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
