import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'device_installation_service.dart';

class StockTransferService {
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
      'inventory_transfers_list_v485',
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
    required String transferId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_transfer_detail_v485',
      params: {'p_tenant_id': tenantId, 'p_transfer_id': transferId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected transfer detail response.');
  }

  Future<List<Map<String, dynamic>>> history({
    required String tenantId,
    required String transferId,
  }) async => _rows(
    await _supabase.rpc(
      'inventory_transfer_history_v485',
      params: {'p_tenant_id': tenantId, 'p_transfer_id': transferId},
    ),
  );

  Future<List<Map<String, dynamic>>> warehouses({
    required String tenantId,
  }) async => _rows(
    await _supabase.rpc(
      'warehouse_locations_v485',
      params: {'p_tenant_id': tenantId},
    ),
  );

  Future<List<Map<String, dynamic>>> warehouseInventory({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async => _rows(
    await _supabase.rpc(
      'warehouse_inventory_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_query': query.trim(),
        'p_limit': 2000,
      },
    ),
  );

  Future<Map<String, dynamic>> trackingOptions({
    required String tenantId,
    required String locationId,
    required String variantId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_transfer_tracking_options_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_variant_id': variantId,
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> create({
    required String tenantId,
    required String fromLocationId,
    required String toLocationId,
    required List<Map<String, dynamic>> items,
    required String notes,
    DateTime? expectedArrival,
    String transportReference = '',
  }) async {
    final result = await _supabase.rpc(
      'inventory_transfer_request_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_from_location_id': fromLocationId,
        'p_to_location_id': toLocationId,
        'p_items': items,
        'p_notes': notes.trim(),
        'p_expected_arrival_date': expectedArrival
            ?.toIso8601String()
            .split('T')
            .first,
        'p_transport_reference': transportReference.trim(),
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected transfer request response.');
  }

  Future<Map<String, dynamic>> decide({
    required String tenantId,
    required String transferId,
    required bool approve,
    String note = '',
  }) async {
    final result = await _supabase.rpc(
      'inventory_transfer_decide_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_transfer_id': transferId,
        'p_approve': approve,
        'p_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> cancel({
    required String tenantId,
    required String transferId,
    String reason = '',
  }) async {
    final result = await _supabase.rpc(
      'inventory_transfer_cancel_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_transfer_id': transferId,
        'p_reason': reason.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> dispatch({
    required String tenantId,
    required String transferId,
    String note = '',
    String transportReference = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'inventory_transfer_dispatch_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_transfer_id': transferId,
        'p_device_id': activation?.deviceId,
        'p_dispatch_note': note.trim(),
        'p_transport_reference': transportReference.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> receive({
    required String tenantId,
    required String transferId,
    String note = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'inventory_transfer_receive_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_transfer_id': transferId,
        'p_device_id': activation?.deviceId,
        'p_receive_note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<Map<String, dynamic>>> countSnapshot({
    required String tenantId,
    required String locationId,
    String query = '',
  }) async => _rows(
    await _supabase.rpc(
      'inventory_stock_count_snapshot_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_query': query.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> postCount({
    required String tenantId,
    required String locationId,
    required List<Map<String, dynamic>> items,
    String notes = '',
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    final result = await _supabase.rpc(
      'inventory_stock_count_post_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_items': items,
        'p_notes': notes.trim(),
        'p_device_id': activation?.deviceId,
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected stock count response.');
  }

  Future<List<Map<String, dynamic>>> countHistory({
    required String tenantId,
    String? locationId,
  }) async => _rows(
    await _supabase.rpc(
      'stock_counts_list_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_from': null,
        'p_to': null,
        'p_limit': 500,
      },
    ),
  );

  Future<Map<String, dynamic>> countDetail({
    required String tenantId,
    required String countId,
  }) async {
    final result = await _supabase.rpc(
      'stock_count_detail_v485',
      params: {'p_tenant_id': tenantId, 'p_count_id': countId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected stock count detail response.');
  }

  Future<List<Map<String, dynamic>>> reconciliation({
    required String tenantId,
    String? locationId,
    String query = '',
    bool onlyVariance = false,
  }) async => _rows(
    await _supabase.rpc(
      'inventory_stock_reconciliation_v485',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_query': query.trim(),
        'p_only_variance': onlyVariance,
        'p_limit': 5000,
      },
    ),
  );
}
