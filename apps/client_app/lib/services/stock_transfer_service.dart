import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'device_installation_service.dart';
import 'location_scope_service.dart';

class StockTransferService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> list({required String tenantId}) async {
    final result = await _supabase.rpc(
      'inventory_transfers_list_v42',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': LocationScopeService.selectedLocationId.value,
        'p_limit': 200,
      },
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> detail({
    required String tenantId,
    required String transferId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_transfer_detail_v42',
      params: {'p_tenant_id': tenantId, 'p_transfer_id': transferId},
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected transfer detail response.');
  }

  Future<Map<String, dynamic>> create({
    required String tenantId,
    required String fromLocationId,
    required String toLocationId,
    required List<Map<String, dynamic>> items,
    required String notes,
  }) async {
    final result = await _supabase.rpc(
      'inventory_transfer_create_v47',
      params: {
        'p_tenant_id': tenantId,
        'p_from_location_id': fromLocationId,
        'p_to_location_id': toLocationId,
        'p_items': items,
        'p_notes': notes.trim(),
        'p_request_id': const Uuid().v4(),
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    throw Exception('Unexpected transfer response.');
  }

  Future<void> approve({required String tenantId, required String transferId}) {
    return _supabase.rpc(
      'inventory_transfer_approve_v42',
      params: {'p_tenant_id': tenantId, 'p_transfer_id': transferId},
    );
  }

  Future<void> reject({
    required String tenantId,
    required String transferId,
    required String reason,
  }) {
    return _supabase.rpc(
      'inventory_transfer_reject_v42',
      params: {
        'p_tenant_id': tenantId,
        'p_transfer_id': transferId,
        'p_reason': reason.trim(),
      },
    );
  }

  Future<void> cancel({
    required String tenantId,
    required String transferId,
    String reason = '',
  }) {
    return _supabase.rpc(
      'inventory_transfer_cancel_v42',
      params: {
        'p_tenant_id': tenantId,
        'p_transfer_id': transferId,
        'p_reason': reason.trim(),
      },
    );
  }

  Future<void> dispatch({
    required String tenantId,
    required String transferId,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    await _supabase.rpc(
      'inventory_transfer_dispatch_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_transfer_id': transferId,
        'p_device_id': activation?.deviceId,
      },
    );
  }

  Future<void> receive({
    required String tenantId,
    required String transferId,
  }) async {
    final activation = await DeviceInstallationService().readActivation();
    await _supabase.rpc(
      'inventory_transfer_receive_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_transfer_id': transferId,
        'p_device_id': activation?.deviceId,
      },
    );
  }
}
