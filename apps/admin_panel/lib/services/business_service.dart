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

  Future<Map<String, dynamic>> createBusinessV709({
    required String name,
    required String businessType,
    required String ownerUsername,
    required String ownerPassword,
    String? ownerPhone,
    String? ownerEmail,
    String storeName = 'Main',
    String storeCode = 'MAIN',
    List<String>? moduleKeys,
    String? gstin,
  }) async {
    final result = await _supabase.rpc(
      'platform_create_business_v709',
      params: {
        'p_name': name.trim(),
        'p_business_type': businessType,
        'p_owner_username': ownerUsername.trim().toLowerCase(),
        'p_owner_password': ownerPassword,
        'p_owner_phone': ownerPhone?.trim().isEmpty == true ? null : ownerPhone?.trim(),
        'p_owner_email': ownerEmail?.trim().isEmpty == true ? null : ownerEmail?.trim(),
        'p_store_name': storeName.trim().isEmpty ? 'Main' : storeName.trim(),
        'p_store_code': storeCode.trim().isEmpty ? 'MAIN' : storeCode.trim().toUpperCase(),
        'p_module_keys': moduleKeys,
        'p_gstin': gstin?.trim().isEmpty == true ? null : gstin?.trim().toUpperCase(),
      },
    );
    if (result is! Map) throw Exception('Unexpected business creation response.');
    return Map<String, dynamic>.from(result);
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
