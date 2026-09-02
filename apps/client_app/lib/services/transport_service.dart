import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/gst/gst_v520_gateway.dart';
import 'device_installation_service.dart';
import 'gst_v520_request_id_store.dart';

class TransportService {
  SupabaseClient get _supabase => Supabase.instance.client;
  final GstV520RequestIdStore _requestIds = GstV520RequestIdStore();

  Future<List<Map<String, dynamic>>> vehicles(
    String tenantId, {
    String? locationId,
  }) async {
    final result = await _supabase.rpc(
      'service_vehicles_list_v51',
      params: {'p_tenant_id': tenantId, 'p_location_id': locationId},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<String> saveVehicle({
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
    bool active = true,
  }) async {
    final result = await _supabase.rpc(
      'service_vehicle_save_v51',
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
        'p_active': active,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> jobs(
    String tenantId, {
    String? locationId,
    String? status,
  }) async {
    final result = await _supabase.rpc(
      'service_jobs_list_v51',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_limit': 500,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> saveJob({
    required String tenantId,
    String? jobId,
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
    String status = 'planned',
  }) async {
    final result = await _supabase.rpc(
      'service_job_save_v51',
      params: {
        'p_tenant_id': tenantId,
        'p_job_id': jobId,
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
        'p_status': status,
      },
    );
    if (result is! Map) throw Exception('Unexpected service job response.');
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> setJobStatus({
    required String tenantId,
    required String jobId,
    required String status,
  }) async {
    final result = await _supabase.rpc(
      'service_job_status_v51',
      params: {'p_tenant_id': tenantId, 'p_job_id': jobId, 'p_status': status},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> billJob({
    required String tenantId,
    required String jobId,
    required String billingVariantId,
    DateTime? dueDate,
    required double initialPayment,
    required String paymentMethod,
    required String paymentReference,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }

    final payload = <String, dynamic>{
      'job_id': jobId,
      'billing_variant_id': billingVariantId,
      'due_date': dueDate == null ? null : _date(dueDate),
      'initial_payment': initialPayment,
      'payment_method': paymentMethod,
      'payment_reference': paymentReference.trim(),
      'device_id': activation.deviceId,
    };
    final lease = await _requestIds.acquire(
      tenantId: tenantId,
      operation: 'service_bill',
      payload: payload,
    );

    final gateway = GstV520Gateway(
      client: _supabase,
      tenantId: tenantId,
      channel: GstV520Channel.client,
      deviceId: activation.deviceId,
    );
    await gateway.initialize();
    final rpc = gateway.routeFor('service_bill');

    try {
      final result = await _supabase.rpc(
        rpc,
        params: {
          'p_tenant_id': tenantId,
          'p_job_id': jobId,
          'p_billing_variant_id': billingVariantId,
          'p_due_date': dueDate == null ? null : _date(dueDate),
          'p_initial_payment': initialPayment,
          'p_payment_method': paymentMethod,
          'p_payment_reference': paymentReference.trim(),
          'p_device_id': activation.deviceId,
          'p_request_id': lease.requestId,
        },
      );
      if (result is! Map) throw StateError('Unexpected response from $rpc.');
      await _requestIds.complete(lease);
      return Map<String, dynamic>.from(result);
    } catch (error) {
      throw StateError(
        'Authoritative GST v5.2 service billing failed. Legacy billing fallback '
        'is disabled. Retry the unchanged bill. $error',
      );
    }
  }

  Future<Map<String, dynamic>> linkSaleByReference({
    required String tenantId,
    required String jobId,
    required String saleNumber,
  }) async {
    final result = await _supabase.rpc(
      'service_job_link_sale_by_reference_v51',
      params: {
        'p_tenant_id': tenantId,
        'p_job_id': jobId,
        'p_sale_number': saleNumber.trim(),
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
