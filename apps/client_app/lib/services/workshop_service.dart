import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_scope_service.dart';

class WorkshopService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> vehicles({
    required String tenantId,
    String query = '',
  }) async {
    final result = await _supabase.rpc(
      'workshop_vehicles_list_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': LocationScopeService.selectedLocationId.value,
        'p_query': query,
      },
    );
    return (result as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> saveVehicle({
    required String tenantId,
    String? id,
    required String locationId,
    String? customerId,
    required String vehicleNumber,
    String make = '',
    String model = '',
    int? year,
    String vin = '',
    String chassis = '',
    double? odometer,
    String notes = '',
    bool active = true,
  }) async {
    await _supabase.rpc(
      'workshop_vehicle_save_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_id': id,
        'p_location_id': locationId,
        'p_customer_id': customerId,
        'p_vehicle_number': vehicleNumber,
        'p_make': make,
        'p_model': model,
        'p_year': year,
        'p_vin': vin,
        'p_chassis': chassis,
        'p_odometer': odometer,
        'p_notes': notes,
        'p_active': active,
      },
    );
  }

  Future<List<Map<String, dynamic>>> jobs({
    required String tenantId,
    String status = '',
    String query = '',
  }) async {
    final result = await _supabase.rpc(
      'workshop_jobs_list_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': LocationScopeService.selectedLocationId.value,
        'p_status': status,
        'p_query': query,
      },
    );
    return (result as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createJob({
    required String tenantId,
    required String locationId,
    required String vehicleId,
    String? customerId,
    required String complaint,
    DateTime? estimatedDelivery,
  }) async {
    final result = await _supabase.rpc(
      'workshop_job_create_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_vehicle_id': vehicleId,
        'p_customer_id': customerId,
        'p_complaint': complaint,
        'p_estimated_delivery': estimatedDelivery?.toIso8601String(),
        'p_technician': null,
      },
    );
    return result is Map ? Map<String, dynamic>.from(result) : const {};
  }

  Future<void> updateStatus({
    required String tenantId,
    required String jobId,
    required String status,
    String note = '',
  }) => _supabase.rpc(
    'workshop_job_status_v4',
    params: {
      'p_tenant_id': tenantId,
      'p_job_id': jobId,
      'p_status': status,
      'p_note': note,
    },
  );
}
