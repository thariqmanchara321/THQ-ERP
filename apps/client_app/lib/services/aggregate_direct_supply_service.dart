import 'package:supabase_flutter/supabase_flutter.dart';

class AggregateDirectSupplyService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> materials({
    required String tenantId,
  }) async {
    final result = await _db.rpc(
      'aggregate_direct_materials_v621',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> loads({
    required String tenantId,
    String? operatingLocationId,
    String? query,
    int limit = 300,
  }) async {
    final result = await _db.rpc(
      'aggregate_direct_list_v621',
      params: {
        'p_tenant_id': tenantId,
        'p_operating_location_id': operatingLocationId,
        'p_query': query,
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) {
          final mapped = Map<String, dynamic>.from(row);
          mapped['direction'] = 'direct_delivery';
          mapped['location_id'] = mapped['operating_location_id'];
          return mapped;
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createLoad({
    required String tenantId,
    required String operatingLocationId,
    required String variantId,
    required double quantity,
    required String unitCode,
    String measurementMethod = 'manual',
    double? bodyLengthFt,
    double? bodyWidthFt,
    double? bodyHeightFt,
    String? vehicleId,
    String? driverId,
    required String supplierId,
    required String customerId,
    String? sourceName,
    String? destinationName,
    String? sourceReference,
    String freightMode = 'none',
    double freightAmount = 0,
    bool capacityOverride = false,
    String? capacityOverrideReason,
    String? notes,
  }) async {
    final result = await _db.rpc(
      'aggregate_direct_load_create_v621',
      params: {
        'p_tenant_id': tenantId,
        'p_operating_location_id': operatingLocationId,
        'p_variant_id': variantId,
        'p_quantity': quantity,
        'p_unit_code': unitCode,
        'p_measurement_method': measurementMethod,
        'p_body_length_ft': bodyLengthFt,
        'p_body_width_ft': bodyWidthFt,
        'p_body_height_ft': bodyHeightFt,
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
    );
    if (result is! Map) {
      throw StateError('Unexpected Direct Supply create response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<Map<String, dynamic>>> documentCandidates({
    required String tenantId,
    required String loadId,
    required String documentType,
    int limit = 30,
  }) async {
    final result = await _db.rpc(
      'aggregate_direct_document_candidates_v621',
      params: {
        'p_tenant_id': tenantId,
        'p_load_id': loadId,
        'p_document_type': documentType,
        'p_limit': limit,
      },
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> linkDocument({
    required String tenantId,
    required String loadId,
    required String documentType,
    required String documentId,
  }) async {
    final result = await _db.rpc(
      'aggregate_direct_link_document_v621',
      params: {
        'p_tenant_id': tenantId,
        'p_load_id': loadId,
        'p_document_type': documentType,
        'p_document_id': documentId,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected Direct Supply link response.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> updateStatus({
    required String tenantId,
    required String loadId,
    required String status,
    String? note,
  }) async {
    final result = await _db.rpc(
      'aggregate_direct_status_v621',
      params: {
        'p_tenant_id': tenantId,
        'p_load_id': loadId,
        'p_status': status,
        'p_note': note,
      },
    );
    if (result is! Map) {
      throw StateError('Unexpected Direct Supply status response.');
    }
    return Map<String, dynamic>.from(result);
  }
}
