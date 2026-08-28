import 'package:supabase_flutter/supabase_flutter.dart';

class TransportService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> vehicles(
    String tenantId, {
    String? locationId,
  }) async {
    final result = await _supabase.rpc(
      'service_vehicles_list_v32',
      params: {'p_tenant_id': tenantId, 'p_location_id': locationId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> saveVehicle({
    required String tenantId,
    String? vehicleId,
    required String locationId,
    required String registration,
    required String vehicleType,
    required String makeModel,
    required double capacity,
    required String capacityUnit,
    required String driverName,
    required String driverPhone,
  }) async {
    await _supabase.rpc(
      'service_vehicle_save_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_vehicle_id': vehicleId,
        'p_location_id': locationId,
        'p_registration_number': registration.trim(),
        'p_vehicle_type': vehicleType.trim(),
        'p_make_model': makeModel.trim(),
        'p_capacity': capacity,
        'p_capacity_unit': capacityUnit.trim(),
        'p_driver_name': driverName.trim(),
        'p_driver_phone': driverPhone.trim(),
        'p_active': true,
      },
    );
  }

  Future<List<Map<String, dynamic>>> jobs(
    String tenantId, {
    String? locationId,
  }) async {
    final result = await _supabase.rpc(
      'service_jobs_list_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_limit': 500,
      },
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createJob({
    required String tenantId,
    required String locationId,
    String? customerId,
    String? vehicleId,
    required DateTime date,
    required String from,
    required String to,
    required double distanceKm,
    required double quantity,
    required String quantityUnit,
    required double rate,
    required String notes,
  }) async {
    final result = await _supabase.rpc(
      'service_job_create_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_customer_id': customerId,
        'p_vehicle_id': vehicleId,
        'p_service_date': _date(date),
        'p_from_location': from.trim(),
        'p_to_location': to.trim(),
        'p_distance_km': distanceKm,
        'p_quantity': quantity,
        'p_quantity_unit': quantityUnit.trim(),
        'p_rate': rate,
        'p_notes': notes.trim(),
      },
    );
    if (result is! Map) {
      throw Exception('Unexpected service job response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<void> linkSaleByReference({
    required String tenantId,
    required String jobId,
    required String saleNumber,
  }) async {
    await _supabase.rpc(
      'service_job_link_sale_by_reference_v32',
      params: {
        'p_tenant_id': tenantId,
        'p_job_id': jobId,
        'p_sale_number': saleNumber,
      },
    );
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
