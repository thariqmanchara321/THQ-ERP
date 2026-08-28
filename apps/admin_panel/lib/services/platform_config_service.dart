import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/platform_models.dart';

class PlatformConfigService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> getOverview() async {
    final result = await _supabase.rpc('platform_overview_summary');
    if (result is Map) return Map<String, dynamic>.from(result);
    return <String, dynamic>{};
  }

  Future<List<PlatformModuleInfo>> getModules() async {
    final result = await _supabase.rpc('platform_modules_v2_list');
    return (result as List)
        .map(
          (row) =>
              PlatformModuleInfo.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> saveModule({
    required String key,
    required String name,
    required String description,
    required String category,
    required int sortOrder,
    required bool isCore,
    required bool isActive,
    required bool isBeta,
    required bool requiresConfiguration,
    required String? minimumPlanKey,
    required List<String> dependencies,
    required List<String> businessTypes,
  }) async {
    await _supabase.rpc(
      'platform_module_v2_upsert',
      params: {
        'p_key': key.trim(),
        'p_name': name.trim(),
        'p_description': description.trim(),
        'p_category': category.trim(),
        'p_sort_order': sortOrder,
        'p_is_core': isCore,
        'p_is_active': isActive,
        'p_is_beta': isBeta,
        'p_requires_configuration': requiresConfiguration,
        'p_minimum_plan_key': minimumPlanKey,
        'p_dependencies': dependencies,
        'p_business_types': businessTypes,
      },
    );
  }

  Future<List<BusinessTemplate>> getTemplates() async {
    final result = await _supabase.rpc('platform_templates_list');
    return (result as List)
        .map(
          (row) =>
              BusinessTemplate.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> saveTemplate({
    String? id,
    required String key,
    required String name,
    required String businessType,
    required String description,
    required bool isActive,
    required int sortOrder,
    required List<String> moduleKeys,
  }) async {
    await _supabase.rpc(
      'platform_template_upsert',
      params: {
        'p_id': id,
        'p_key': key.trim(),
        'p_name': name.trim(),
        'p_business_type': businessType.trim(),
        'p_description': description.trim(),
        'p_is_active': isActive,
        'p_sort_order': sortOrder,
        'p_module_keys': moduleKeys,
        'p_settings': <String, dynamic>{},
      },
    );
  }

  Future<List<SubscriptionPlan>> getPlans() async {
    final result = await _supabase.rpc('platform_subscription_plans_list');
    return (result as List)
        .map(
          (row) =>
              SubscriptionPlan.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> savePlan({
    String? id,
    required String key,
    required String name,
    required String description,
    required double monthlyPrice,
    required double yearlyPrice,
    required String currencyCode,
    required bool isActive,
    required int sortOrder,
    required List<String> moduleKeys,
    required Map<String, dynamic> limits,
  }) async {
    await _supabase.rpc(
      'platform_subscription_plan_upsert',
      params: {
        'p_id': id,
        'p_key': key.trim(),
        'p_name': name.trim(),
        'p_description': description.trim(),
        'p_monthly_price': monthlyPrice,
        'p_yearly_price': yearlyPrice,
        'p_currency_code': currencyCode.trim().toUpperCase(),
        'p_is_active': isActive,
        'p_sort_order': sortOrder,
        'p_module_keys': moduleKeys,
        'p_limits': limits,
      },
    );
  }

  Future<List<PlatformAdminInfo>> getPlatformAdmins() async {
    final result = await _supabase.rpc('platform_admins_v3_list');
    return (result as List)
        .map(
          (row) =>
              PlatformAdminInfo.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> grantPlatformAdmin({
    required String username,
    required String roleKey,
  }) async {
    await _supabase.rpc(
      'platform_admin_v3_grant',
      params: {'p_username': username.trim(), 'p_role_key': roleKey},
    );
  }

  Future<void> revokePlatformAdmin(String userId) async {
    await _supabase.rpc(
      'platform_admin_v2_revoke',
      params: {'p_user_id': userId},
    );
  }

  Future<List<PlatformSetting>> getSettings() async {
    final result = await _supabase.rpc('platform_settings_list');
    return (result as List)
        .map(
          (row) =>
              PlatformSetting.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<void> setSetting(String key, dynamic value) async {
    await _supabase.rpc(
      'platform_setting_set',
      params: {'p_key': key, 'p_value': value},
    );
  }

  Future<TenantSubscriptionInfo> getTenantSubscription(String tenantId) async {
    final result = await _supabase.rpc(
      'platform_tenant_subscription_get',
      params: {'p_tenant_id': tenantId},
    );
    if (result is Map) {
      return TenantSubscriptionInfo.fromMap(Map<String, dynamic>.from(result));
    }
    throw Exception('Unexpected subscription response.');
  }

  Future<void> setTenantSubscription({
    required String tenantId,
    required String planId,
    required String status,
    required String billingCycle,
    DateTime? endsAt,
    DateTime? trialEndsAt,
  }) async {
    String? iso(DateTime? value) => value?.toUtc().toIso8601String();
    await _supabase.rpc(
      'platform_tenant_subscription_set',
      params: {
        'p_tenant_id': tenantId,
        'p_plan_id': planId,
        'p_status': status,
        'p_billing_cycle': billingCycle,
        'p_ends_at': iso(endsAt),
        'p_trial_ends_at': iso(trialEndsAt),
        'p_limit_overrides': <String, dynamic>{},
      },
    );
  }

  Future<List<PlatformAuditEvent>> getAuditEvents({int limit = 200}) async {
    final result = await _supabase.rpc(
      'platform_audit_list',
      params: {'p_limit': limit},
    );
    return (result as List)
        .map(
          (row) =>
              PlatformAuditEvent.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> getInvoiceTemplates() async {
    final r = await _supabase.rpc('platform_invoice_templates_list');
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> saveInvoiceTemplate({
    String? id,
    required String key,
    required String name,
    required String paperType,
    required String description,
    required Map<String, dynamic> config,
    required String sampleLogoKey,
    required bool isActive,
  }) async {
    await _supabase.rpc(
      'platform_invoice_template_upsert',
      params: {
        'p_id': id,
        'p_key': key,
        'p_name': name,
        'p_paper_type': paperType,
        'p_description': description,
        'p_config': config,
        'p_sample_logo_key': sampleLogoKey,
        'p_is_active': isActive,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAppErrorLogs() async {
    final r = await _supabase.rpc(
      'platform_app_error_logs_list',
      params: {'p_limit': 500},
    );
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> setTenantInvoiceTemplate({
    required String tenantId,
    required String paperType,
    required String templateId,
  }) async {
    await _supabase.rpc(
      'platform_tenant_invoice_template_set',
      params: {
        'p_tenant_id': tenantId,
        'p_paper_type': paperType,
        'p_template_id': templateId,
        'p_overrides': <String, dynamic>{},
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAppReleases() async {
    final result = await _supabase.rpc('platform_app_releases_list_v4');
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> saveAppRelease({
    String? id,
    required String appKey,
    required String platform,
    required String version,
    required int buildNumber,
    required String status,
    required bool minimumSupported,
    required bool mandatory,
    required String releaseNotes,
    required String downloadUrl,
  }) async {
    await _supabase.rpc(
      'platform_app_release_save_v4',
      params: {
        'p_id': id,
        'p_app_key': appKey,
        'p_platform': platform,
        'p_version': version,
        'p_build_number': buildNumber,
        'p_status': status,
        'p_minimum_supported': minimumSupported,
        'p_mandatory': mandatory,
        'p_release_notes': releaseNotes,
        'p_download_url': downloadUrl,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getDeviceVersions() async {
    final result = await _supabase.rpc(
      'platform_device_versions_list_v4',
      params: {'p_tenant_id': null},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getSupportTickets({String? status}) async {
    final result = await _supabase.rpc(
      'platform_support_tickets_list_v4',
      params: {'p_status': status, 'p_limit': 500},
    );
    return (result as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> setSupportTicketStatus(String ticketId, String status) async {
    await _supabase.rpc(
      'platform_support_ticket_status_v4',
      params: {'p_ticket_id': ticketId, 'p_status': status},
    );
  }

  Future<List<Map<String, dynamic>>> getUiDesignTemplates({
    String? appKey,
  }) async {
    final result = await _supabase.rpc(
      'platform_ui_design_templates_list_v43',
      params: {'p_app_key': appKey},
    );
    return (result as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<String> saveUiDesignTemplate({
    String? id,
    required String key,
    required String name,
    required String appKey,
    required String description,
    required Map<String, dynamic> config,
    required bool isActive,
    required bool isDefault,
    required int sortOrder,
  }) async {
    final result = await _supabase.rpc(
      'platform_ui_design_template_upsert_v43',
      params: {
        'p_id': id,
        'p_key': key.trim(),
        'p_name': name.trim(),
        'p_app_key': appKey,
        'p_description': description.trim(),
        'p_config': config,
        'p_is_active': isActive,
        'p_is_default': isDefault,
        'p_sort_order': sortOrder,
      },
    );
    return result.toString();
  }

  Future<Map<String, dynamic>> getTenantUiDesign({
    required String tenantId,
    required String appKey,
  }) async {
    final result = await _supabase.rpc(
      'platform_tenant_ui_design_get_v43',
      params: {'p_tenant_id': tenantId, 'p_app_key': appKey},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void> setTenantUiDesign({
    required String tenantId,
    required String appKey,
    required String templateId,
    required Map<String, dynamic> overrides,
  }) async {
    await _supabase.rpc(
      'platform_tenant_ui_design_set_v43',
      params: {
        'p_tenant_id': tenantId,
        'p_app_key': appKey,
        'p_template_id': templateId,
        'p_overrides': overrides,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getMenuNodes({
    String? tenantId,
    required String appKey,
  }) async {
    final result = await _supabase.rpc(
      'platform_menu_nodes_v45_list',
      params: {'p_tenant_id': tenantId, 'p_app_key': appKey},
    );
    return (result as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> copyDefaultMenu({
    required String tenantId,
    required String appKey,
  }) async {
    await _supabase.rpc(
      'platform_menu_copy_default_v45',
      params: {'p_tenant_id': tenantId, 'p_app_key': appKey},
    );
  }

  Future<String> saveMenuNode({
    String? id,
    String? tenantId,
    required String appKey,
    required String nodeKey,
    required String nodeType,
    String? moduleKey,
    String? parentId,
    required String label,
    required String iconKey,
    required int sortOrder,
    required bool enabled,
    required bool collapsedByDefault,
    Map<String, dynamic> metadata = const {},
  }) async {
    final result = await _supabase.rpc(
      'platform_menu_node_save_v45',
      params: {
        'p_id': id,
        'p_tenant_id': tenantId,
        'p_app_key': appKey,
        'p_node_key': nodeKey.trim(),
        'p_node_type': nodeType,
        'p_module_key': moduleKey,
        'p_parent_id': parentId,
        'p_label': label.trim(),
        'p_icon_key': iconKey.trim(),
        'p_sort_order': sortOrder,
        'p_enabled': enabled,
        'p_collapsed_by_default': collapsedByDefault,
        'p_metadata': metadata,
      },
    );
    return result.toString();
  }

  Future<void> deleteMenuNode(String id) async {
    await _supabase.rpc('platform_menu_node_delete_v45', params: {'p_id': id});
  }
}
