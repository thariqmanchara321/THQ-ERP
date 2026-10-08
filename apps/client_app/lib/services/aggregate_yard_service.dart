import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'staff_load_service.dart';
import 'location_scope_service.dart';

class AggregateYardService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> stock({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async {
    final result = await _db.rpc(
      'aggregate_yard_stock_v628',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_query': query.trim(),
        'p_limit': 1000,
      },
    );
    return (result as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> saveBatchProfile({
    required String tenantId,
    required String batchId,
    required String qualityLabel,
    double? sellingPriceBase,
  }) async {
    await _db.rpc(
      'aggregate_yard_batch_profile_save_v628',
      params: {
        'p_tenant_id': tenantId,
        'p_batch_id': batchId,
        'p_quality_label': qualityLabel,
        'p_selling_price_base': sellingPriceBase,
      },
    );
  }

  Future<void> saveVehicleDriver({
    required String tenantId,
    required String vehicleId,
    required String driverName,
    required String driverPhone,
  }) async {
    await _db.rpc(
      'aggregate_vehicle_driver_save_v628',
      params: {
        'p_tenant_id': tenantId,
        'p_vehicle_id': vehicleId,
        'p_driver_name': driverName.trim(),
        'p_driver_phone': driverPhone.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> context({required String tenantId}) async {
    final result = await _db.rpc(
      'aggregate_yard_context_v629',
      params: {'p_tenant_id': tenantId},
    );
    if (result is! Map) {
      throw StateError('Unexpected Material Yard context response.');
    }
    final costs = await StaffLoadService().load(
      tenantId: tenantId,
      action: 'context',
      locationId: LocationScopeService.selectedLocationId.value,
    );
    return {...Map<String, dynamic>.from(result), ...costs};
  }

  Future<Map<String, dynamic>> dashboard({
    required String tenantId,
    String? locationId,
    DateTime? day,
  }) async {
    final localDay = day ?? DateTime.now();
    final date =
        '${localDay.year.toString().padLeft(4, '0')}-'
        '${localDay.month.toString().padLeft(2, '0')}-'
        '${localDay.day.toString().padLeft(2, '0')}';

    final result = await _db.rpc(
      'aggregate_yard_dashboard_v621',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_day': date,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected Material Yard dashboard response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> loads({
    required String tenantId,
    String? locationId,
    String? status,
    String? query,
    int limit = 300,
  }) async {
    final result = await _db.rpc(
      'aggregate_load_list_v629',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_query': query,
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> freightContext({
    required String tenantId,
  }) async {
    final result = await _db.rpc(
      'aggregate_freight_context_v620',
      params: {'p_tenant_id': tenantId},
    );
    if (result is! Map) {
      throw StateError('Unexpected freight context response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> freightLoads({
    required String tenantId,
    String? locationId,
    String? query,
    int limit = 300,
  }) async {
    final result = await _db.rpc(
      'aggregate_freight_list_v620',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_query': query,
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> configureFreight({
    required String tenantId,
    required String loadId,
    required String freightMode,
    String? transporterSupplierId,
    required double freightAmount,
    String? note,
  }) async {
    final result = await _db.rpc(
      'aggregate_freight_configure_v620',
      params: {
        'p_tenant_id': tenantId,
        'p_load_id': loadId,
        'p_freight_mode': freightMode,
        'p_transporter_supplier_id': transporterSupplierId,
        'p_freight_amount': freightAmount,
        'p_note': note,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected freight configuration response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> settleFreight({
    required String tenantId,
    required String loadId,
    required String categoryId,
    required DateTime settlementDate,
    required double amount,
    double taxAmount = 0,
    double roundOff = 0,
    required String paymentMethod,
    String? referenceNumber,
    String? note,
    String? deviceId,
    required String requestId,
  }) async {
    final date =
        '${settlementDate.year.toString().padLeft(4, '0')}-'
        '${settlementDate.month.toString().padLeft(2, '0')}-'
        '${settlementDate.day.toString().padLeft(2, '0')}';

    final result = await _db.rpc(
      'aggregate_freight_settle_v620',
      params: {
        'p_tenant_id': tenantId,
        'p_load_id': loadId,
        'p_category_id': categoryId,
        'p_settlement_date': date,
        'p_amount': amount,
        'p_tax_amount': taxAmount,
        'p_round_off': roundOff,
        'p_payment_method': paymentMethod,
        'p_reference_number': referenceNumber,
        'p_note': note,
        'p_device_id': deviceId,
        'p_request_id': requestId,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected freight settlement response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> orders({
    required String tenantId,
    String? locationId,
    String? status,
    String? query,
    int limit = 300,
  }) async {
    final result = await _db.rpc(
      'aggregate_order_list_v618',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_query': query,
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> createOrder({
    required String tenantId,
    required String locationId,
    required String customerId,
    DateTime? requestedDate,
    String? deliverySiteName,
    String? deliveryAddress,
    String? notes,
    required List<Map<String, dynamic>> lines,
  }) async {
    String? requested;
    if (requestedDate != null) {
      requested =
          '${requestedDate.year.toString().padLeft(4, '0')}-'
          '${requestedDate.month.toString().padLeft(2, '0')}-'
          '${requestedDate.day.toString().padLeft(2, '0')}';
    }

    final result = await _db.rpc(
      'aggregate_order_create_v618',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_customer_id': customerId,
        'p_requested_date': requested,
        'p_delivery_site_name': deliverySiteName,
        'p_delivery_address': deliveryAddress,
        'p_notes': notes,
        'p_lines': lines,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected Material Yard order response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> createOrderLoad({
    required String tenantId,
    required String orderLineId,
    required double quantity,
    String measurementMethod = 'manual',
    double? bodyLengthFt,
    double? bodyWidthFt,
    double? bodyHeightFt,
    String? vehicleId,
    String? driverId,
    String? sourceName,
    String? destinationName,
    String freightMode = 'none',
    double freightAmount = 0,
    bool capacityOverride = false,
    String? capacityOverrideReason,
    String? notes,
  }) async {
    final result = await _db.rpc(
      'aggregate_order_load_create_v618',
      params: {
        'p_tenant_id': tenantId,
        'p_order_line_id': orderLineId,
        'p_quantity': quantity,
        'p_measurement_method': measurementMethod,
        'p_body_length_ft': bodyLengthFt,
        'p_body_width_ft': bodyWidthFt,
        'p_body_height_ft': bodyHeightFt,
        'p_vehicle_id': vehicleId,
        'p_driver_id': driverId,
        'p_source_name': sourceName,
        'p_destination_name': destinationName,
        'p_freight_mode': freightMode,
        'p_freight_amount': freightAmount,
        'p_capacity_override': capacityOverride,
        'p_capacity_override_reason': capacityOverrideReason,
        'p_notes': notes,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected order load response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> closeOrder({
    required String tenantId,
    required String orderId,
    required String reason,
  }) async {
    final result = await _db.rpc(
      'aggregate_order_close_v618',
      params: {
        'p_tenant_id': tenantId,
        'p_order_id': orderId,
        'p_reason': reason,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected close order response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> createLoad({
    required String tenantId,
    required String direction,
    String? locationId,
    required String variantId,
    required double quantity,
    String unitCode = 'CFT',
    String measurementMethod = 'manual',
    double? bodyLengthFt,
    double? bodyWidthFt,
    double? bodyHeightFt,
    double? grossWeightKg,
    double? tareWeightKg,
    double? netWeightKg,
    String? vehicleId,
    String? driverId,
    String? supplierId,
    String? customerId,
    String? sourceName,
    String? destinationName,
    String? sourceReference,
    String freightMode = 'none',
    double freightAmount = 0,
    bool capacityOverride = false,
    String? capacityOverrideReason,
    String? notes,
    List<Map<String, dynamic>> costs = const [],
    Map<String, dynamic> delivery = const {},
    String? requestId,
  }) async {
    final result = await StaffLoadService().load(
      tenantId: tenantId,
      action: 'create',
      locationId: locationId,
      data: {
        'load': {
          'p_tenant_id': tenantId,
          'p_direction': direction,
          'p_location_id': locationId,
          'p_variant_id': variantId,
          'p_quantity': quantity,
          'p_unit_code': unitCode,
          'p_measurement_method': measurementMethod,
          'p_body_length_ft': bodyLengthFt,
          'p_body_width_ft': bodyWidthFt,
          'p_body_height_ft': bodyHeightFt,
          'p_gross_weight_kg': grossWeightKg,
          'p_tare_weight_kg': tareWeightKg,
          'p_net_weight_kg': netWeightKg,
          'p_vehicle_id': vehicleId,
          'p_driver_id': driverId,
          'p_supplier_id': supplierId,
          'p_customer_id': customerId,
          'p_source_name': sourceName,
          'p_destination_name': destinationName,
          'p_source_reference': sourceReference,
          'p_freight_mode': freightMode,
          'p_freight_amount': freightAmount,
          'p_capacity_override': capacityOverride,
          'p_capacity_override_reason': capacityOverrideReason,
          'p_notes': notes,
        },
        'costs': costs,
        'delivery': delivery,
        'request_id': requestId ?? const Uuid().v4(),
      },
    );
    return result;
  }

  Future<Map<String, dynamic>> loadDetail({
    required String tenantId,
    required String loadId,
  }) => StaffLoadService().load(
    tenantId: tenantId,
    action: 'detail',
    data: {'load_id': loadId},
  );

  Future<Map<String, dynamic>> confirmLoad({
    required String tenantId,
    required String loadId,
  }) => StaffLoadService().load(
    tenantId: tenantId,
    action: 'confirm',
    data: {'load_id': loadId},
  );

  Future<Map<String, dynamic>> deleteLoad({
    required String tenantId,
    required String loadId,
  }) => StaffLoadService().load(
    tenantId: tenantId,
    action: 'delete',
    data: {'load_id': loadId},
  );

  Future<Map<String, dynamic>> editLoad({
    required String tenantId,
    required String loadId,
    required String direction,
    String? locationId,
    required String variantId,
    required double quantity,
    String unitCode = 'CFT',
    String measurementMethod = 'manual',
    double? bodyLengthFt,
    double? bodyWidthFt,
    double? bodyHeightFt,
    double? grossWeightKg,
    double? tareWeightKg,
    double? netWeightKg,
    String? vehicleId,
    String? driverId,
    String? supplierId,
    String? customerId,
    String? sourceName,
    String? destinationName,
    String? sourceReference,
    String freightMode = 'none',
    double freightAmount = 0,
    bool capacityOverride = false,
    String? capacityOverrideReason,
    String? notes,
    List<Map<String, dynamic>> costs = const [],
    Map<String, dynamic> delivery = const {},
    String? requestId,
  }) async {
    final result = await StaffLoadService().load(
      tenantId: tenantId,
      action: 'edit',
      locationId: locationId,
      data: {
        'load': {
          'p_tenant_id': tenantId,
          'p_load_id': loadId,
          'p_direction': direction,
          'p_location_id': locationId,
          'p_variant_id': variantId,
          'p_quantity': quantity,
          'p_unit_code': unitCode,
          'p_measurement_method': measurementMethod,
          'p_body_length_ft': bodyLengthFt,
          'p_body_width_ft': bodyWidthFt,
          'p_body_height_ft': bodyHeightFt,
          'p_gross_weight_kg': grossWeightKg,
          'p_tare_weight_kg': tareWeightKg,
          'p_net_weight_kg': netWeightKg,
          'p_vehicle_id': vehicleId,
          'p_driver_id': driverId,
          'p_supplier_id': supplierId,
          'p_customer_id': customerId,
          'p_source_name': sourceName,
          'p_destination_name': destinationName,
          'p_source_reference': sourceReference,
          'p_freight_mode': freightMode,
          'p_freight_amount': freightAmount,
          'p_capacity_override': capacityOverride,
          'p_capacity_override_reason': capacityOverrideReason,
          'p_notes': notes,
        },
        'costs': costs,
        'delivery': delivery,
        'load_id': loadId,
      },
    );
    return result;
  }

  Future<Map<String, dynamic>> updateStatus({
    required String tenantId,
    required String loadId,
    required String status,
    String? note,
  }) async {
    final result = await _db.rpc(
      'aggregate_load_status_v617',
      params: {
        'p_tenant_id': tenantId,
        'p_load_id': loadId,
        'p_status': status,
        'p_note': note,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected load status response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> linkDocument({
    required String tenantId,
    required String loadId,
    required String documentType,
    required String documentId,
  }) async {
    final result = await _db.rpc(
      'aggregate_load_link_document_v617',
      params: {
        'p_tenant_id': tenantId,
        'p_load_id': loadId,
        'p_document_type': documentType,
        'p_document_id': documentId,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected load document-link response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<String> createVehicle({
    required String tenantId,
    required String locationId,
    required String registrationNumber,
    String vehicleType = 'Truck',
    String? makeModel,
    String? driverName,
    String? driverPhone,
    double? capacityCft,
  }) async {
    final result = await _db.rpc(
      'aggregate_vehicle_create_v621',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_registration_number': registrationNumber,
        'p_vehicle_type': vehicleType,
        'p_make_model': makeModel,
        'p_driver_name': driverName,
        'p_driver_phone': driverPhone,
        'p_capacity_cft': capacityCft,
      },
    );
    if (result == null || result.toString().isEmpty) {
      throw StateError('Unexpected truck-create response.');
    }
    return result.toString();
  }

  Future<Map<String, dynamic>> saveVehicleProfile({
    required String tenantId,
    required String vehicleId,
    required String ownershipType,
    String? ownerName,
    String? ownerPhone,
    double? bodyLengthFt,
    double? bodyWidthFt,
    double? bodyHeightFt,
    double? nominalCapacityCft,
    double? tareWeightKg,
    double? maxPayloadKg,
    double defaultFreight = 0,
    String? notes,
  }) async {
    final result = await _db.rpc(
      'aggregate_vehicle_profile_save_v617',
      params: {
        'p_tenant_id': tenantId,
        'p_vehicle_id': vehicleId,
        'p_ownership_type': ownershipType,
        'p_owner_name': ownerName,
        'p_owner_phone': ownerPhone,
        'p_body_length_ft': bodyLengthFt,
        'p_body_width_ft': bodyWidthFt,
        'p_body_height_ft': bodyHeightFt,
        'p_nominal_capacity_cft': nominalCapacityCft,
        'p_tare_weight_kg': tareWeightKg,
        'p_max_payload_kg': maxPayloadKg,
        'p_default_freight': defaultFreight,
        'p_notes': notes,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected vehicle profile response.');
    }
    return Map<String, dynamic>.from(result);
  }
}
