import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_installation_service.dart';
import 'location_scope_service.dart';

class TrackingService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> syncWarranties({required String tenantId}) async {
    final result = await _supabase.rpc(
      'warranty_sync_v51',
      params: {'p_tenant_id': tenantId},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getPolicy({
    required String tenantId,
    required String variantId,
  }) async {
    final result = await _supabase.rpc(
      'inventory_tracking_policy_v483',
      params: {'p_tenant_id': tenantId, 'p_variant_id': variantId},
    );
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> savePolicy({
    required String tenantId,
    required String variantId,
    required String trackingMode,
    required bool warrantyEnabled,
    required int warrantyMonths,
    required int warrantyDays,
    required bool requireBatchExpiry,
    required bool allowExpiredSale,
  }) async {
    final result = await _supabase.rpc(
      'inventory_tracking_policy_save_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_tracking_mode': trackingMode,
        'p_warranty_enabled': warrantyEnabled,
        'p_warranty_months': warrantyMonths,
        'p_warranty_days': warrantyDays,
        'p_require_batch_expiry': requireBatchExpiry,
        'p_allow_expired_sale': allowExpiredSale,
      },
    );
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> reconciliation({
    required String tenantId,
    required String variantId,
    String? locationId,
  }) async {
    final resolved = await resolveLocation(tenantId, locationId: locationId);
    final result = await _supabase.rpc(
      'inventory_tracking_reconciliation_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_location_id': resolved,
      },
    );
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> registerOpening({
    required String tenantId,
    required String variantId,
    required List<String> serialNumbers,
    required List<Map<String, dynamic>> batches,
    String note = '',
    String? locationId,
  }) async {
    final resolved = await resolveLocation(tenantId, locationId: locationId);
    final result = await _supabase.rpc(
      'inventory_tracking_register_opening_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_variant_id': variantId,
        'p_location_id': resolved,
        'p_serial_numbers': serialNumbers,
        'p_batches': batches,
        'p_note': note.trim(),
      },
    );
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> searchSerials({
    required String tenantId,
    String query = '',
    String? locationId,
    int limit = 200,
  }) async {
    final result = await _supabase.rpc(
      'inventory_serial_search_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_query': query.trim(),
        'p_location_id': locationId ?? LocationScopeService.selectedLocationId.value,
        'p_limit': limit,
      },
    );
    return (result as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> searchBatches({
    required String tenantId,
    String query = '',
    String? locationId,
    int limit = 200,
  }) async {
    final result = await _supabase.rpc(
      'inventory_batch_search_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_query': query.trim(),
        'p_location_id': locationId ?? LocationScopeService.selectedLocationId.value,
        'p_limit': limit,
      },
    );
    return (result as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> serialHistory({required String tenantId, required String serialId}) async {
    final result = await _supabase.rpc('inventory_serial_history_v483', params: {'p_tenant_id': tenantId, 'p_serial_id': serialId});
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> batchHistory({required String tenantId, required String batchId}) async {
    final result = await _supabase.rpc('inventory_batch_history_v483', params: {'p_tenant_id': tenantId, 'p_batch_id': batchId});
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> warranties({
    required String tenantId,
    String query = '',
    String? status,
    int? expiringDays,
    int limit = 300,
  }) async {
    final result = await _supabase.rpc(
      'warranty_register_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_query': query.trim(),
        'p_status': status,
        'p_expiring_days': expiringDays,
        'p_limit': limit,
        'p_location_id': LocationScopeService.selectedLocationId.value,
      },
    );
    return (result as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> resolveSerial({
    required String tenantId,
    required String serialNumber,
    String? locationId,
  }) async {
    final resolvedLocation = await resolveLocation(tenantId, locationId: locationId);
    final result = await _supabase.rpc(
      'inventory_serial_resolve_v483',
      params: {
        'p_tenant_id': tenantId,
        'p_serial_number': serialNumber.trim(),
        'p_location_id': resolvedLocation,
      },
    );
    return result is Map ? Map<String, dynamic>.from(result) : null;
  }

  Future<String> resolveLocation(String tenantId, {String? locationId}) async {
    final selected = locationId ?? LocationScopeService.selectedLocationId.value;
    if (selected != null && selected.isNotEmpty) return selected;
    final activation = await DeviceInstallationService().readActivation();
    if (activation == null || activation.tenantId != tenantId) {
      throw StateError('This system is not activated for this business.');
    }
    return activation.locationId;
  }
}
