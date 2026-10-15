import 'dart:convert';

/// Stable logical application scopes in THQ ERP.
enum ThqAppScope {
  businessDesktop('client', 'business_desktop', 'THQ Business (Desktop)'),
  posDesktop('pos', 'pos_desktop', 'THQ POS (Desktop)'),
  mobileErp('client_mobile', 'mobile_erp', 'THQ Mobile ERP'),
  posMobile('mobile_pos', 'pos_mobile', 'THQ Mobile POS'),
  admin('admin', 'admin', 'THQ Administration');

  final String key;
  final String logicalName;
  final String displayName;

  const ThqAppScope(this.key, this.logicalName, this.displayName);

  static ThqAppScope fromString(String? raw) {
    final clean = (raw ?? '').trim().toLowerCase();
    return switch (clean) {
      'pos' || 'pos_desktop' => ThqAppScope.posDesktop,
      'client_mobile' || 'mobile_erp' => ThqAppScope.mobileErp,
      'mobile_pos' || 'pos_mobile' => ThqAppScope.posMobile,
      'admin' => ThqAppScope.admin,
      _ => ThqAppScope.businessDesktop,
    };
  }

  static String canonicalKey(String? raw) => fromString(raw).key;
}

/// A standard module definition in the THQ ERP catalog.
class ThqModuleDefinition {
  final String key;
  final String name;
  final String description;
  final String category;
  final int sortOrder;
  final bool isCore;
  final bool isActive;
  final bool isBeta;
  final bool requiresConfiguration;
  final String? minimumPlanKey;
  final List<String> dependencies;
  final List<String> supportedScopes;

  const ThqModuleDefinition({
    required this.key,
    required this.name,
    this.description = '',
    this.category = 'General',
    this.sortOrder = 100,
    this.isCore = false,
    this.isActive = true,
    this.isBeta = false,
    this.requiresConfiguration = false,
    this.minimumPlanKey,
    this.dependencies = const [],
    this.supportedScopes = const [
      'client',
      'pos',
      'client_mobile',
      'mobile_pos',
    ],
  });

  bool supportsScope(String scope) {
    final canonical = ThqAppScope.canonicalKey(scope);
    return supportedScopes.isEmpty || supportedScopes.contains(canonical);
  }

  factory ThqModuleDefinition.fromMap(Map<String, dynamic> map) {
    return ThqModuleDefinition(
      key: (map['key']?.toString() ?? '').trim().toLowerCase(),
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      category: map['category']?.toString() ?? 'General',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 100,
      isCore: map['is_core'] == true,
      isActive: map['is_active'] != false,
      isBeta: map['is_beta'] == true,
      requiresConfiguration: map['requires_configuration'] == true,
      minimumPlanKey: map['minimum_plan_key']?.toString(),
      dependencies: (map['dependencies'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      supportedScopes: (map['supported_scopes'] as List? ?? const [])
          .map((e) => ThqAppScope.canonicalKey(e.toString()))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'key': key,
    'name': name,
    'description': description,
    'category': category,
    'sort_order': sortOrder,
    'is_core': isCore,
    'is_active': isActive,
    'is_beta': isBeta,
    'requires_configuration': requiresConfiguration,
    'minimum_plan_key': minimumPlanKey,
    'dependencies': dependencies,
    'supported_scopes': supportedScopes,
  };
}

/// Navigation node for the dynamic multi-scope navigation tree.
class ThqNavigationNode {
  final String id;
  final String nodeKey;
  final String nodeType; // 'group' or 'module'
  final String? moduleKey;
  final String? parentId;
  final String label;
  final String? iconKey;
  final int sortOrder;
  final bool enabled;
  final bool collapsedByDefault;
  final Map<String, dynamic> metadata;

  const ThqNavigationNode({
    required this.id,
    required this.nodeKey,
    required this.nodeType,
    this.moduleKey,
    this.parentId,
    required this.label,
    this.iconKey,
    this.sortOrder = 100,
    this.enabled = true,
    this.collapsedByDefault = false,
    this.metadata = const {},
  });

  bool get isGroup => nodeType == 'group';
  bool get isModule => nodeType == 'module';
  String get category => metadata['category']?.toString() ?? 'Operations';

  factory ThqNavigationNode.fromMap(Map<String, dynamic> map) {
    return ThqNavigationNode(
      id: map['id']?.toString() ?? '',
      nodeKey: map['node_key']?.toString() ?? '',
      nodeType: map['node_type']?.toString() ?? 'module',
      moduleKey: map['module_key']?.toString(),
      parentId: map['parent_id']?.toString(),
      label: map['label']?.toString() ?? '',
      iconKey: map['icon_key']?.toString(),
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 100,
      enabled: map['enabled'] != false,
      collapsedByDefault: map['collapsed_by_default'] == true,
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'node_key': nodeKey,
    'node_type': nodeType,
    'module_key': moduleKey,
    'parent_id': parentId,
    'label': label,
    'icon_key': iconKey,
    'sort_order': sortOrder,
    'enabled': enabled,
    'collapsed_by_default': collapsedByDefault,
    'metadata': metadata,
  };

  ThqNavigationNode copyWith({
    String? id,
    String? nodeKey,
    String? nodeType,
    String? moduleKey,
    String? parentId,
    String? label,
    String? iconKey,
    int? sortOrder,
    bool? enabled,
    bool? collapsedByDefault,
    Map<String, dynamic>? metadata,
  }) {
    return ThqNavigationNode(
      id: id ?? this.id,
      nodeKey: nodeKey ?? this.nodeKey,
      nodeType: nodeType ?? this.nodeType,
      moduleKey: moduleKey ?? this.moduleKey,
      parentId: parentId ?? this.parentId,
      label: label ?? this.label,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      enabled: enabled ?? this.enabled,
      collapsedByDefault: collapsedByDefault ?? this.collapsedByDefault,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// User UI personalization preferences (Concept E in Section 3.3).
class ThqUserUiPreferences {
  final String appScope;
  final Set<String> favorites;
  final Set<String> hiddenNodes;
  final Map<String, int> sortOrder;
  final Set<String> quickActions;
  final String tableDensity;
  final String? defaultLandingModule;
  final List<String> dashboardWidgets;
  final bool isDefault;

  const ThqUserUiPreferences({
    required this.appScope,
    this.favorites = const <String>{},
    this.hiddenNodes = const <String>{},
    this.sortOrder = const <String, int>{},
    this.quickActions = const <String>{},
    this.tableDensity = 'compact',
    this.defaultLandingModule,
    this.dashboardWidgets = const <String>[],
    this.isDefault = true,
  });

  bool isFavorite(String key) => favorites.contains(key);
  bool isHidden(String key) => hiddenNodes.contains(key);

  ThqUserUiPreferences toggleFavorite(String key) {
    final next = Set<String>.from(favorites);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    return copyWith(favorites: next, isDefault: false);
  }

  ThqUserUiPreferences toggleHidden(String key) {
    final next = Set<String>.from(hiddenNodes);
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    return copyWith(hiddenNodes: next, isDefault: false);
  }

  factory ThqUserUiPreferences.defaults(String appScope) {
    return ThqUserUiPreferences(
      appScope: ThqAppScope.canonicalKey(appScope),
      isDefault: true,
    );
  }

  factory ThqUserUiPreferences.fromMap(Map<String, dynamic> map) {
    final sortMap = <String, int>{};
    if (map['sort_order'] is Map) {
      for (final entry in (map['sort_order'] as Map).entries) {
        if (entry.value is num) {
          sortMap[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }

    return ThqUserUiPreferences(
      appScope: ThqAppScope.canonicalKey(map['app_scope']?.toString()),
      favorites: (map['favorites'] as List? ?? const [])
          .map((e) => e.toString())
          .toSet(),
      hiddenNodes: (map['hidden_nodes'] as List? ?? const [])
          .map((e) => e.toString())
          .toSet(),
      sortOrder: sortMap,
      quickActions: (map['quick_actions'] as List? ?? const [])
          .map((e) => e.toString())
          .toSet(),
      tableDensity: map['table_density']?.toString() ?? 'compact',
      defaultLandingModule: map['default_landing_module']?.toString(),
      dashboardWidgets: (map['dashboard_widgets'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      isDefault: map['is_default'] == true,
    );
  }

  Map<String, dynamic> toMap() => {
    'app_scope': appScope,
    'favorites': favorites.toList(),
    'hidden_nodes': hiddenNodes.toList(),
    'sort_order': sortOrder,
    'quick_actions': quickActions.toList(),
    'table_density': tableDensity,
    'default_landing_module': defaultLandingModule,
    'dashboard_widgets': dashboardWidgets,
  };

  String toJson() => jsonEncode(toMap());

  ThqUserUiPreferences copyWith({
    String? appScope,
    Set<String>? favorites,
    Set<String>? hiddenNodes,
    Map<String, int>? sortOrder,
    Set<String>? quickActions,
    String? tableDensity,
    String? defaultLandingModule,
    List<String>? dashboardWidgets,
    bool? isDefault,
  }) {
    return ThqUserUiPreferences(
      appScope: appScope ?? this.appScope,
      favorites: favorites ?? this.favorites,
      hiddenNodes: hiddenNodes ?? this.hiddenNodes,
      sortOrder: sortOrder ?? this.sortOrder,
      quickActions: quickActions ?? this.quickActions,
      tableDensity: tableDensity ?? this.tableDensity,
      defaultLandingModule: defaultLandingModule ?? this.defaultLandingModule,
      dashboardWidgets: dashboardWidgets ?? this.dashboardWidgets,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
