import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business.dart';
import '../models/business_module.dart';
import '../models/erp_module.dart';

class BusinessService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Business>> getBusinesses() async {
    final result = await _supabase.rpc('platform_list_businesses_v41');

    final rows = result as List<dynamic>;

    return rows
        .map((row) => Business.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<ErpModule>> getModules() async {
    final result = await _supabase.rpc('platform_list_modules');

    final rows = result as List<dynamic>;

    return rows
        .map((row) => ErpModule.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<String> createBusiness({
    required String name,
    required String slug,
    required String businessType,
    required List<String> moduleKeys,
  }) async {
    final result = await _supabase.rpc(
      'platform_create_business',
      params: {
        'p_name': name,
        'p_slug': slug,
        'p_business_type': businessType,
        'p_module_keys': moduleKeys,
      },
    );

    return result.toString();
  }

  Future<void> applyTemplateSettings({
    required String tenantId,
    required String templateKey,
  }) async {
    await _supabase.rpc(
      'platform_apply_template_settings',
      params: {'p_tenant_id': tenantId, 'p_template_key': templateKey},
    );
  }

  Future<Map<String, dynamic>> getBusinessIdentity({
    required String tenantId,
  }) async {
    final result = await _supabase.rpc(
      'platform_business_identity',
      params: {'p_tenant_id': tenantId},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> getDivisions() async {
    final result = await _supabase.rpc('platform_divisions_list_v41');
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> saveDivision({
    String? divisionId,
    required String name,
    String code = '',
  }) async {
    final result = await _supabase.rpc(
      'platform_division_save_v41',
      params: {
        'p_division_id': divisionId,
        'p_name': name.trim(),
        'p_division_code': code.trim().isEmpty ? null : code.trim(),
        'p_active': true,
      },
    );
    return result.toString();
  }

  Future<void> assignBusinessToDivision({
    required String tenantId,
    required String divisionId,
    required String memberType,
  }) async {
    await _supabase.rpc(
      'platform_division_assign_business_v41',
      params: {
        'p_division_id': divisionId,
        'p_tenant_id': tenantId,
        'p_member_type': memberType,
      },
    );
  }

  Future<void> removeBusinessFromDivision({required String tenantId}) async {
    await _supabase.rpc(
      'platform_division_remove_business_v41',
      params: {'p_tenant_id': tenantId},
    );
  }

  Future<void> archiveBusiness({
    required String tenantId,
    String reason = '',
  }) async {
    await _supabase.rpc(
      'platform_business_archive_v41',
      params: {'p_tenant_id': tenantId, 'p_reason': reason.trim()},
    );
  }

  Future<void> deleteBusiness({
    required String tenantId,
    required String password,
    required String businessCode,
  }) async {
    final response = await _supabase.functions.invoke(
      'delete-business-v41',
      body: {
        'tenant_id': tenantId,
        'password': password,
        'confirm_code': businessCode,
        'mode': 'delete',
      },
    );
    if (response.data is Map && (response.data as Map)['error'] != null) {
      throw Exception((response.data as Map)['error'].toString());
    }
  }

  Future<List<BusinessModule>> getBusinessModules({
    required String tenantId,
  }) async {
    final result = await _supabase.rpc(
      'platform_get_business_modules',
      params: {'p_tenant_id': tenantId},
    );

    final rows = result as List<dynamic>;

    return rows
        .map(
          (row) =>
              BusinessModule.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> updateBusinessModules({
    required String tenantId,
    required List<String> moduleKeys,
  }) async {
    await _supabase.rpc(
      'platform_update_business_modules_v2',
      params: {'p_tenant_id': tenantId, 'p_module_keys': moduleKeys},
    );
  }
}
