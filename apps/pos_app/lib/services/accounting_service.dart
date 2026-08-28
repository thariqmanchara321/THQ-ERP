import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/accounting_summary.dart';
import 'location_scope_service.dart';

class AccountingService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<AccountingSummary> summary({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _supabase.rpc(
      'accounting_get_summary_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_from_date': _date(from),
        'p_to_date': _date(to),
        'p_location_id': LocationScopeService.selectedLocationId.value,
      },
    );
    if (result is! Map) throw Exception('Unexpected accounting response.');
    return AccountingSummary.fromMap(Map<String, dynamic>.from(result));
  }

  Future<List<Map<String, dynamic>>> accounts({
    required String tenantId,
  }) async {
    final result = await _supabase.rpc(
      'accounting_accounts_list_v4',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> mappings({
    required String tenantId,
  }) async {
    final result = await _supabase.rpc(
      'accounting_mappings_list_v4',
      params: {'p_tenant_id': tenantId},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> setMapping({
    required String tenantId,
    required String mappingKey,
    required String accountId,
  }) async {
    await _supabase.rpc(
      'accounting_mapping_set_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_mapping_key': mappingKey,
        'p_account_id': accountId,
      },
    );
  }

  Future<String> saveAccount({
    required String tenantId,
    String? accountId,
    required String code,
    required String name,
    required String type,
    String? parentId,
    String description = '',
    bool active = true,
  }) async {
    final result = await _supabase.rpc(
      'accounting_account_save_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_account_id': accountId,
        'p_code': code.trim(),
        'p_name': name.trim(),
        'p_account_type': type,
        'p_parent_id': parentId,
        'p_description': description.trim(),
        'p_active': active,
      },
    );
    return result?.toString() ?? '';
  }

  Future<List<Map<String, dynamic>>> register({
    required String tenantId,
    required String register,
    required DateTime from,
    required DateTime to,
    String query = '',
  }) async {
    final result = await _supabase.rpc(
      'accounting_register_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_register': register,
        'p_from': _date(from),
        'p_to': _date(to),
        'p_location_id': LocationScopeService.selectedLocationId.value,
        'p_query': query.trim(),
      },
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> gstSummary({
    required String tenantId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _supabase.rpc(
      'gst_summary_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_from': _date(from),
        'p_to': _date(to),
        'p_location_id': LocationScopeService.selectedLocationId.value,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
