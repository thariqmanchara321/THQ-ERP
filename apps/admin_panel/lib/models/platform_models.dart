class PlatformModuleInfo {
  final String key;
  final String name;
  final String? description;
  final String category;
  final bool isCore;
  final int sortOrder;
  final bool isActive;
  final bool isBeta;
  final bool requiresConfiguration;
  final String? minimumPlanKey;
  final List<String> dependencies;
  final List<String> businessTypes;

  const PlatformModuleInfo({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.isCore,
    required this.sortOrder,
    required this.isActive,
    required this.isBeta,
    required this.requiresConfiguration,
    required this.minimumPlanKey,
    required this.dependencies,
    required this.businessTypes,
  });

  factory PlatformModuleInfo.fromMap(Map<String, dynamic> map) {
    List<String> strings(dynamic value) {
      if (value is List) return value.map((e) => e.toString()).toList();
      return const [];
    }

    return PlatformModuleInfo(
      key: map['key']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString(),
      category: map['category']?.toString() ?? 'General',
      isCore: map['is_core'] == true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      isActive: map['is_active'] != false,
      isBeta: map['is_beta'] == true,
      requiresConfiguration: map['requires_configuration'] == true,
      minimumPlanKey: map['minimum_plan_key']?.toString(),
      dependencies: strings(map['dependencies']),
      businessTypes: strings(map['business_types']),
    );
  }
}

class BusinessTemplate {
  final String id;
  final String key;
  final String name;
  final String businessType;
  final String? description;
  final bool isActive;
  final bool isSystem;
  final int sortOrder;
  final List<String> moduleKeys;
  final Map<String, dynamic> settings;

  const BusinessTemplate({
    required this.id,
    required this.key,
    required this.name,
    required this.businessType,
    required this.description,
    required this.isActive,
    required this.isSystem,
    required this.sortOrder,
    required this.moduleKeys,
    required this.settings,
  });

  factory BusinessTemplate.fromMap(Map<String, dynamic> map) {
    return BusinessTemplate(
      id: map['id']?.toString() ?? '',
      key: map['key']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      businessType: map['business_type']?.toString() ?? 'Custom',
      description: map['description']?.toString(),
      isActive: map['is_active'] != false,
      isSystem: map['is_system'] == true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      moduleKeys: (map['module_keys'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      settings: map['settings'] is Map
          ? Map<String, dynamic>.from(map['settings'] as Map)
          : <String, dynamic>{},
    );
  }
}

class SubscriptionPlan {
  final String id;
  final String key;
  final String name;
  final String? description;
  final double monthlyPrice;
  final double yearlyPrice;
  final String currencyCode;
  final bool isActive;
  final int sortOrder;
  final List<String> moduleKeys;
  final Map<String, dynamic> limits;

  const SubscriptionPlan({
    required this.id,
    required this.key,
    required this.name,
    required this.description,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.currencyCode,
    required this.isActive,
    required this.sortOrder,
    required this.moduleKeys,
    required this.limits,
  });

  factory SubscriptionPlan.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return SubscriptionPlan(
      id: map['id']?.toString() ?? '',
      key: map['key']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString(),
      monthlyPrice: number(map['monthly_price']),
      yearlyPrice: number(map['yearly_price']),
      currencyCode: map['currency_code']?.toString() ?? 'INR',
      isActive: map['is_active'] != false,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      moduleKeys: (map['module_keys'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      limits: map['limits'] is Map
          ? Map<String, dynamic>.from(map['limits'] as Map)
          : <String, dynamic>{},
    );
  }
}

class PlatformAdminInfo {
  final String userId;
  final String username;
  final String roleKey;
  final bool active;
  final DateTime? createdAt;
  const PlatformAdminInfo({
    required this.userId,
    required this.username,
    required this.roleKey,
    required this.active,
    required this.createdAt,
  });
  factory PlatformAdminInfo.fromMap(Map<String, dynamic> map) =>
      PlatformAdminInfo(
        userId: map['user_id']?.toString() ?? '',
        username: map['username']?.toString() ?? '',
        roleKey: map['role_key']?.toString() ?? 'super_admin',
        active: map['active'] != false,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      );
}

class PlatformSetting {
  final String key;
  final dynamic value;
  final String? description;

  const PlatformSetting({
    required this.key,
    required this.value,
    required this.description,
  });

  factory PlatformSetting.fromMap(Map<String, dynamic> map) {
    return PlatformSetting(
      key: map['key']?.toString() ?? '',
      value: map['value'],
      description: map['description']?.toString(),
    );
  }
}

class PlatformAuditEvent {
  final String id;
  final DateTime? createdAt;
  final String actorEmail;
  final String action;
  final String entityType;
  final String? entityId;
  final String? tenantName;
  final Map<String, dynamic> details;

  const PlatformAuditEvent({
    required this.id,
    required this.createdAt,
    required this.actorEmail,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.tenantName,
    required this.details,
  });

  factory PlatformAuditEvent.fromMap(Map<String, dynamic> map) {
    return PlatformAuditEvent(
      id: map['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      actorEmail: map['actor_email']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      entityType: map['entity_type']?.toString() ?? '',
      entityId: map['entity_id']?.toString(),
      tenantName: map['tenant_name']?.toString(),
      details: map['details'] is Map
          ? Map<String, dynamic>.from(map['details'] as Map)
          : <String, dynamic>{},
    );
  }
}

class TenantSubscriptionInfo {
  final String tenantId;
  final String? planId;
  final String? planKey;
  final String? planName;
  final String status;
  final String billingCycle;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? trialEndsAt;
  final Map<String, dynamic> limitOverrides;

  const TenantSubscriptionInfo({
    required this.tenantId,
    required this.planId,
    required this.planKey,
    required this.planName,
    required this.status,
    required this.billingCycle,
    required this.startsAt,
    required this.endsAt,
    required this.trialEndsAt,
    required this.limitOverrides,
  });

  factory TenantSubscriptionInfo.fromMap(Map<String, dynamic> map) {
    return TenantSubscriptionInfo(
      tenantId: map['tenant_id']?.toString() ?? '',
      planId: map['plan_id']?.toString(),
      planKey: map['plan_key']?.toString(),
      planName: map['plan_name']?.toString(),
      status: map['status']?.toString() ?? 'none',
      billingCycle: map['billing_cycle']?.toString() ?? 'monthly',
      startsAt: DateTime.tryParse(map['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(map['ends_at']?.toString() ?? ''),
      trialEndsAt: DateTime.tryParse(map['trial_ends_at']?.toString() ?? ''),
      limitOverrides: map['limit_overrides'] is Map
          ? Map<String, dynamic>.from(map['limit_overrides'] as Map)
          : <String, dynamic>{},
    );
  }
}
