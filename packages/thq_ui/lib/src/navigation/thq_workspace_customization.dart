import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

import '../components/thq_buttons.dart';
import '../components/thq_dialog.dart';
import '../components/thq_notification_host.dart';
import '../components/thq_status_badge.dart';
import '../foundations/thq_tokens.dart';
import '../status/thq_status.dart';

/// Predefined workspace configurations tailored for specific business roles.
enum ThqWorkspacePreset {
  owner(
    name: 'Business Owner / Executive',
    description: 'Comprehensive business oversight, analytics, approvals, and core operations.',
    icon: Icons.shield_outlined,
    defaultLanding: 'dashboard',
    density: 'compact',
    favorites: {
      'dashboard',
      'sales',
      'purchases',
      'inventory',
      'accounting',
      'reports',
      'approvals',
      'audit_center',
    },
    hidden: {},
  ),
  cashier(
    name: 'Cashier / POS Operator',
    description: 'Fast-paced billing, cash drawer management, shifts, and customer lookups.',
    icon: Icons.point_of_sale_outlined,
    defaultLanding: 'pos',
    density: 'compact',
    favorites: {
      'pos',
      'sales',
      'customers',
      'cashier_shifts',
      'returns',
      'payments',
    },
    hidden: {
      'accounting',
      'audit_center',
      'settings',
      'logs',
      'backup',
      'bulk_import',
    },
  ),
  accountant(
    name: 'Accountant / Tax Auditor',
    description: 'Ledgers, double-entry journals, GST compliance, statements, and reconciliations.',
    icon: Icons.account_balance_outlined,
    defaultLanding: 'accounting',
    density: 'compact',
    favorites: {
      'accounting',
      'gst_compliance',
      'sales',
      'purchases',
      'customers',
      'suppliers',
      'expenses',
      'reports',
      'loans',
    },
    hidden: {
      'pos',
      'restaurant',
      'workshop',
    },
  ),
  yardOperator(
    name: 'Material Yard / Quarry Operator',
    description: 'Weighbridge loads, outward/inward dispatches, vehicle fleets, and daily rate boards.',
    icon: Icons.landscape_outlined,
    defaultLanding: 'aggregate_yard',
    density: 'compact',
    favorites: {
      'aggregate_yard',
      'daily_rate_board',
      'aggregate_loads',
      'aggregate_vehicles',
      'aggregate_direct_supply',
      'logistics_operations',
    },
    hidden: {
      'accounting',
      'pos',
      'restaurant',
      'audit_center',
      'loans',
    },
  ),
  storekeeper(
    name: 'Storekeeper / Inventory Manager',
    description: 'Stock inward, stock transfers, barcode tracking, batches, and reorder points.',
    icon: Icons.inventory_2_outlined,
    defaultLanding: 'inventory',
    density: 'compact',
    favorites: {
      'inventory',
      'stock_transfers',
      'purchases',
      'suppliers',
      'barcode',
      'tracking',
    },
    hidden: {
      'accounting',
      'pos',
      'restaurant',
      'audit_center',
      'loans',
    },
  );

  final String name;
  final String description;
  final IconData icon;
  final String defaultLanding;
  final String density;
  final Set<String> favorites;
  final Set<String> hidden;

  const ThqWorkspacePreset({
    required this.name,
    required this.description,
    required this.icon,
    required this.defaultLanding,
    required this.density,
    required this.favorites,
    required this.hidden,
  });

  ThqUserUiPreferences toPreferences(String appScope) {
    return ThqUserUiPreferences(
      appScope: ThqAppScope.canonicalKey(appScope),
      favorites: Set<String>.from(favorites),
      hiddenNodes: Set<String>.from(hidden),
      tableDensity: density,
      defaultLandingModule: defaultLanding,
      isDefault: false,
    );
  }
}

/// Centralized icon resolver for all THQ ERP modules and navigation nodes.
class ThqModuleIcons {
  const ThqModuleIcons._();

  static IconData resolve(String key, [String? iconKey]) {
    final cleanIcon = (iconKey ?? '').trim().toLowerCase();
    if (cleanIcon.isNotEmpty) {
      final fromIconKey = _fromName(cleanIcon);
      if (fromIconKey != null) return fromIconKey;
    }

    final cleanKey = key.trim().toLowerCase();
    final fromKey = _fromName(cleanKey);
    if (fromKey != null) return fromKey;

    return Icons.extension_outlined;
  }

  static IconData? _fromName(String name) => switch (name) {
    'dashboard' || 'space_dashboard' => Icons.space_dashboard_outlined,
    'sales' || 'receipt_long' => Icons.receipt_long_outlined,
    'sales_details' || 'history' => Icons.history_outlined,
    'purchases' || 'shopping_cart' => Icons.shopping_cart_outlined,
    'purchase_details' || 'list_alt' => Icons.list_alt_outlined,
    'inventory' || 'inventory_2' => Icons.inventory_2_outlined,
    'inventory_reports' => Icons.analytics_outlined,
    'accounting' || 'account_balance' => Icons.account_balance_outlined,
    'gst' || 'gst_compliance' => Icons.receipt_outlined,
    'pos' || 'point_of_sale' => Icons.point_of_sale_outlined,
    'cashier_shifts' => Icons.wallet_outlined,
    'customers' || 'groups' => Icons.groups_outlined,
    'suppliers' || 'local_shipping' => Icons.local_shipping_outlined,
    'expenses' || 'payments' => Icons.payments_outlined,
    'reports' || 'insights' => Icons.insights_outlined,
    'audit_center' || 'audit' || 'policy' => Icons.policy_outlined,
    'aggregate_yard' || 'landscape' => Icons.landscape_outlined,
    'aggregate_loads' => Icons.scale_outlined,
    'aggregate_vehicles' => Icons.local_shipping_outlined,
    'aggregate_orders' => Icons.assignment_outlined,
    'aggregate_direct_supply' => Icons.alt_route_outlined,
    'daily_rate_board' => Icons.price_change_outlined,
    'logistics_operations' || 'route' => Icons.route_outlined,
    'vehicle_logistics' => Icons.directions_boat_outlined,
    'transport_service' => Icons.commute_outlined,
    'stock_transfers' || 'swap_horiz' => Icons.swap_horiz_outlined,
    'loans' || 'account_balance_wallet' => Icons.account_balance_wallet_outlined,
    'pricing' || 'sell' => Icons.sell_outlined,
    'barcode' || 'qr_code_scanner' => Icons.qr_code_scanner_outlined,
    'staff' || 'badge' => Icons.badge_outlined,
    'tasks' || 'task_alt' => Icons.task_alt_outlined,
    'approvals' || 'approval' => Icons.approval_outlined,
    'notifications' => Icons.notifications_outlined,
    'settings' || 'tune' => Icons.tune_outlined,
    'locations' || 'store_mall_directory' => Icons.store_mall_directory_outlined,
    'users' || 'manage_accounts' => Icons.manage_accounts_outlined,
    'backup' => Icons.backup_outlined,
    'logs' || 'bug_report' => Icons.bug_report_outlined,
    'bulk_import' || 'upload_file' => Icons.upload_file_outlined,
    'invoice_templates' || 'description' => Icons.description_outlined,
    'restaurant' => Icons.restaurant_outlined,
    'workshop' || 'build' => Icons.build_outlined,
    'operations_intelligence' || 'monitor_heart' => Icons.monitor_heart_outlined,
    'support' => Icons.support_agent_outlined,
    'production' || 'factory' => Icons.factory_outlined,
    'warranty' => Icons.verified_user_outlined,
    'folder' => Icons.folder_outlined,
    _ => null,
  };
}

/// Controller managing the state and actions of universal workspace personalization.
class ThqWorkspaceCustomizationController extends ChangeNotifier {
  final String appScope;
  final List<ThqNavigationNode> _allNodes;
  final List<ThqModuleDefinition> _availableModules;
  final ThqUserUiPreferences initialPreferences;

  late ThqUserUiPreferences _preferences;
  late List<ThqNavigationNode> _orderedNodes;
  String _searchQuery = '';
  String? _selectedCategory;
  bool _showOnlyFavorites = false;
  bool _isSaving = false;
  String? _errorMessage;

  ThqWorkspaceCustomizationController({
    required String appScope,
    required List<ThqNavigationNode> allNodes,
    required this.initialPreferences,
    List<ThqModuleDefinition> availableModules = const [],
  })  : appScope = ThqAppScope.canonicalKey(appScope),
        _allNodes = List.unmodifiable(allNodes),
        _availableModules = List.unmodifiable(availableModules) {
    _preferences = initialPreferences.copyWith();
    _recomputeOrderedNodes();
  }

  ThqUserUiPreferences get preferences => _preferences;
  List<ThqNavigationNode> get allNodes => _allNodes;
  String get searchQuery => _searchQuery;
  String? get selectedCategory => _selectedCategory;
  bool get showOnlyFavorites => _showOnlyFavorites;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  bool get hasUnsavedChanges {
    return _preferences.appScope != initialPreferences.appScope ||
        _preferences.tableDensity != initialPreferences.tableDensity ||
        _preferences.defaultLandingModule != initialPreferences.defaultLandingModule ||
        !_setEquals(_preferences.favorites, initialPreferences.favorites) ||
        !_setEquals(_preferences.hiddenNodes, initialPreferences.hiddenNodes) ||
        !_mapEquals(_preferences.sortOrder, initialPreferences.sortOrder);
  }

  int get favoritesCount => _preferences.favorites.length;
  int get hiddenCount => _preferences.hiddenNodes.length;

  List<String> get categories {
    final set = <String>{};
    for (final node in _allNodes) {
      final cat = _categoryForNode(node);
      if (cat.isNotEmpty) set.add(cat);
    }
    final sorted = set.toList()..sort();
    return sorted;
  }

  List<ThqNavigationNode> get filteredNodes {
    final query = _searchQuery.trim().toLowerCase();
    return _orderedNodes.where((node) {
      if (_showOnlyFavorites && !_preferences.isFavorite(node.nodeKey)) {
        return false;
      }
      if (_selectedCategory != null &&
          _selectedCategory!.isNotEmpty &&
          _categoryForNode(node) != _selectedCategory) {
        return false;
      }
      if (query.isNotEmpty) {
        final labelMatch = node.label.toLowerCase().contains(query);
        final keyMatch = node.nodeKey.toLowerCase().contains(query);
        final moduleKeyMatch =
            node.moduleKey?.toLowerCase().contains(query) ?? false;
        if (!labelMatch && !keyMatch && !moduleKeyMatch) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _categoryForNode(ThqNavigationNode node) {
    if (node.metadata['category'] != null) {
      return node.metadata['category'].toString();
    }
    for (final mod in _availableModules) {
      if (mod.key == node.moduleKey || mod.key == node.nodeKey) {
        return mod.category;
      }
    }
    // Heuristic categorization based on key
    final k = node.moduleKey ?? node.nodeKey;
    if (k.contains('sale') || k.contains('pos') || k.contains('customer') || k == 'returns') {
      return 'Sales & POS';
    }
    if (k.contains('purchase') || k.contains('supplier')) {
      return 'Purchases';
    }
    if (k.contains('inventory') || k.contains('stock') || k.contains('barcode')) {
      return 'Inventory & Stock';
    }
    if (k.contains('account') || k.contains('gst') || k.contains('expense') || k.contains('loan') || k.contains('payment')) {
      return 'Finance & Accounts';
    }
    if (k.contains('aggregate') || k.contains('yard') || k.contains('logistics') || k.contains('transport')) {
      return 'Material Yard & Fleet';
    }
    if (k.contains('report') || k.contains('audit') || k.contains('intelligence')) {
      return 'Reports & Audit';
    }
    if (k.contains('setting') || k.contains('location') || k.contains('user') || k.contains('backup') || k.contains('log')) {
      return 'Administration';
    }
    return 'General';
  }

  void setSearch(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void setCategory(String? category) {
    if (_selectedCategory == category) return;
    _selectedCategory = category;
    notifyListeners();
  }

  void toggleFavoritesFilter() {
    _showOnlyFavorites = !_showOnlyFavorites;
    notifyListeners();
  }

  void toggleFavorite(String nodeKey) {
    _preferences = _preferences.toggleFavorite(nodeKey);
    notifyListeners();
  }

  void toggleVisibility(String nodeKey) {
    _preferences = _preferences.toggleHidden(nodeKey);
    notifyListeners();
  }

  void setTableDensity(String density) {
    if (_preferences.tableDensity == density) return;
    _preferences = _preferences.copyWith(tableDensity: density, isDefault: false);
    notifyListeners();
  }

  void setDefaultLandingModule(String? moduleKey) {
    if (_preferences.defaultLandingModule == moduleKey) return;
    _preferences = _preferences.copyWith(defaultLandingModule: moduleKey, isDefault: false);
    notifyListeners();
  }

  void reorderNodes(int oldIndex, int newIndex) {
    final currentList = filteredNodes;
    if (oldIndex < 0 || oldIndex >= currentList.length) return;
    if (newIndex < 0 || newIndex > currentList.length) return;

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = currentList[oldIndex];

    // Find actual index in _orderedNodes
    final actualOld = _orderedNodes.indexOf(item);
    if (actualOld == -1) return;

    _orderedNodes.removeAt(actualOld);
    final targetNode = newIndex < currentList.length ? currentList[newIndex] : null;
    final actualNew = targetNode != null ? _orderedNodes.indexOf(targetNode) : _orderedNodes.length;
    _orderedNodes.insert(actualNew < 0 ? _orderedNodes.length : actualNew, item);

    // Update sort order map
    final newSortMap = Map<String, int>.from(_preferences.sortOrder);
    for (int i = 0; i < _orderedNodes.length; i++) {
      newSortMap[_orderedNodes[i].nodeKey] = (i + 1) * 10;
    }
    _preferences = _preferences.copyWith(sortOrder: newSortMap, isDefault: false);
    notifyListeners();
  }

  void applyPreset(ThqWorkspacePreset preset) {
    final p = preset.toPreferences(appScope);
    _preferences = _preferences.copyWith(
      favorites: p.favorites,
      hiddenNodes: p.hiddenNodes,
      tableDensity: p.tableDensity,
      defaultLandingModule: p.defaultLandingModule,
      isDefault: false,
    );
    _recomputeOrderedNodes();
    notifyListeners();
  }

  void resetToDefaults() {
    _preferences = ThqUserUiPreferences.defaults(appScope);
    _recomputeOrderedNodes();
    notifyListeners();
  }

  Future<bool> save(Future<void> Function(ThqUserUiPreferences) onSave) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await onSave(_preferences);
      _isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isSaving = false;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void _recomputeOrderedNodes() {
    final list = List<ThqNavigationNode>.from(_allNodes);
    list.sort((a, b) {
      final orderA = _preferences.sortOrder[a.nodeKey] ?? a.sortOrder;
      final orderB = _preferences.sortOrder[b.nodeKey] ?? b.sortOrder;
      final c = orderA.compareTo(orderB);
      return c != 0 ? c : a.label.compareTo(b.label);
    });
    _orderedNodes = list;
  }

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// A compact, rich, adaptive screen and dialog component for customizing THQ workspace navigation,
/// favorites, hidden modules, table density, and landing defaults.
class ThqWorkspaceCustomizationView extends StatelessWidget {
  final ThqWorkspaceCustomizationController controller;
  final Future<void> Function(ThqUserUiPreferences) onSave;
  final VoidCallback? onDismiss;
  final bool isModal;

  const ThqWorkspaceCustomizationView({
    super.key,
    required this.controller,
    required this.onSave,
    this.onDismiss,
    this.isModal = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final scopeEnum = ThqAppScope.fromString(controller.appScope);

        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            elevation: 0,
            toolbarHeight: 48,
            title: Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined, size: 20),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Workspace & Module Customization',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                ThqStatusBadge(
                  status: ThqStatus.neutral,
                  label: scopeEnum.displayName,
                  compact: true,
                ),
              ],
            ),
            actions: [
              if (isModal)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss ?? () => Navigator.of(context).pop(),
                ),
            ],
          ),
          body: Column(
            children: [
              // Error banner if any
              if (controller.errorMessage != null)
                Container(
                  width: double.infinity,
                  color: scheme.errorContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.errorMessage!,
                          style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Control & Preset Header
              _buildTopControls(context, scheme),

              const Divider(height: 1),

              // Search & Category Filters
              _buildFilterBar(context, scheme),

              const Divider(height: 1),

              // Summary Stats Row
              _buildStatsBar(context, scheme),

              // Reorderable / Filtered Node List
              Expanded(
                child: _buildNodesList(context, scheme),
              ),

              const Divider(height: 1),

              // Bottom Action Footer
              _buildBottomActions(context, scheme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopControls(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: scheme.surfaceContainerLowest,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Table Density Selector
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Table Density:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'compact',
                    label: Text('Compact'),
                    icon: Icon(Icons.density_small_rounded, size: 14),
                  ),
                  ButtonSegment(
                    value: 'comfortable',
                    label: Text('Comfortable'),
                    icon: Icon(Icons.density_medium_rounded, size: 14),
                  ),
                  ButtonSegment(
                    value: 'dense',
                    label: Text('Dense'),
                    icon: Icon(Icons.density_large_rounded, size: 14),
                  ),
                ],
                selected: {controller.preferences.tableDensity},
                onSelectionChanged: (val) => controller.setTableDensity(val.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),

          // Role Presets
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Role Preset:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ThqWorkspacePreset>(
                tooltip: 'Apply role preset',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                    color: scheme.surfaceContainerLow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_fix_high_rounded, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'Choose Preset',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
                onSelected: (preset) {
                  controller.applyPreset(preset);
                  ThqNotify.info(context, 'Applied preset: ${preset.name}');
                },
                itemBuilder: (context) => ThqWorkspacePreset.values.map((p) {
                  return PopupMenuItem(
                    value: p,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(p.icon, size: 18),
                      title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(p.description, style: const TextStyle(fontSize: 11)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Search input
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search modules or shortcuts...',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: controller.searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => controller.setSearch(''),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: controller.setSearch,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Filter Favorites toggle button
              FilterChip(
                selected: controller.showOnlyFavorites,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      controller.showOnlyFavorites ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 16,
                      color: controller.showOnlyFavorites ? Colors.amber[700] : null,
                    ),
                    const SizedBox(width: 4),
                    const Text('Pinned Only', style: TextStyle(fontSize: 12)),
                  ],
                ),
                onSelected: (_) => controller.toggleFavoritesFilter(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Category chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All Categories', style: TextStyle(fontSize: 11)),
                  selected: controller.selectedCategory == null,
                  onSelected: (val) => controller.setCategory(null),
                ),
                const SizedBox(width: 6),
                ...controller.categories.map((cat) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat, style: const TextStyle(fontSize: 11)),
                      selected: controller.selectedCategory == cat,
                      onSelected: (val) => controller.setCategory(val ? cat : null),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: scheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '${controller.filteredNodes.length} items shown',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            Text(
              '•  ${controller.favoritesCount} pinned to favorites',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Text(
              '•  ${controller.hiddenCount} hidden from menu',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 24),
            const Text(
              'Drag handle on left to reorder navigation',
              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodesList(BuildContext context, ColorScheme scheme) {
    final nodes = controller.filteredNodes;

    if (nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: scheme.outline),
            const SizedBox(height: 8),
            Text(
              'No modules match the filter',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Try clearing search or changing category selection',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      itemCount: nodes.length,
      buildDefaultDragHandles: false,
      onReorder: controller.reorderNodes,
      itemBuilder: (context, index) {
        final node = nodes[index];
        final isFavorite = controller.preferences.isFavorite(node.nodeKey);
        final isHidden = controller.preferences.isHidden(node.nodeKey);
        final isDefaultLanding = controller.preferences.defaultLandingModule == (node.moduleKey ?? node.nodeKey);
        final icon = ThqModuleIcons.resolve(node.moduleKey ?? node.nodeKey, node.iconKey);

        return Container(
          key: ValueKey(node.nodeKey),
          decoration: BoxDecoration(
            color: isHidden
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
                : scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                // Drag handle
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.drag_indicator_rounded, size: 18, color: scheme.outline),
                  ),
                ),

                // Icon preview
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isFavorite
                        ? Colors.amber.withValues(alpha: 0.15)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(ThqTokens.radiusSmall),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isFavorite ? Colors.amber[800] : scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),

                // Title & Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              node.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                decoration: isHidden ? TextDecoration.lineThrough : null,
                                color: isHidden ? scheme.onSurfaceVariant : scheme.onSurface,
                              ),
                            ),
                          ),
                          if (isDefaultLanding) ...[
                            const SizedBox(width: 8),
                            const ThqStatusBadge(
                              status: ThqStatus.completed,
                              label: 'Landing Tab',
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            node.nodeKey,
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          if (node.moduleKey != null && node.moduleKey != node.nodeKey) ...[
                            const SizedBox(width: 6),
                            Text(
                              '→ ${node.moduleKey}',
                              style: TextStyle(fontSize: 10, color: scheme.outline),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Default Landing Page Selector
                IconButton(
                  tooltip: isDefaultLanding ? 'Current Landing Screen' : 'Set as Startup Screen',
                  icon: Icon(
                    isDefaultLanding ? Icons.home_rounded : Icons.home_outlined,
                    size: 19,
                    color: isDefaultLanding ? scheme.primary : scheme.outline,
                  ),
                  onPressed: () => controller.setDefaultLandingModule(
                    isDefaultLanding ? null : (node.moduleKey ?? node.nodeKey),
                  ),
                ),

                // Favorite / Pin button
                IconButton(
                  tooltip: isFavorite ? 'Unpin from Favorites' : 'Pin to Favorites',
                  icon: Icon(
                    isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 20,
                    color: isFavorite ? Colors.amber[700] : scheme.outline,
                  ),
                  onPressed: () => controller.toggleFavorite(node.nodeKey),
                ),

                // Visibility toggle button
                IconButton(
                  tooltip: isHidden ? 'Show in navigation' : 'Hide from navigation',
                  icon: Icon(
                    isHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 20,
                    color: isHidden ? scheme.error : scheme.primary,
                  ),
                  onPressed: () => controller.toggleVisibility(node.nodeKey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomActions(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.surfaceContainerLowest,
      child: Row(
        children: [
          // Reset button
          TextButton.icon(
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('Reset Defaults'),
            onPressed: controller.isSaving ? null : controller.resetToDefaults,
          ),
          const Spacer(),

          // Cancel if modal
          if (isModal) ...[
            ThqSecondaryButton(
              label: 'Cancel',
              onPressed: onDismiss ?? () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
          ],

          // Save Button
          ThqPrimaryButton(
            label: 'Save Workspace',
            busyLabel: 'Saving...',
            busy: controller.isSaving,
            icon: Icons.save_rounded,
            onPressed: controller.isSaving
                ? null
                : () async {
                    final ok = await controller.save(onSave);
                    if (ok && context.mounted) {
                      ThqNotify.success(context, 'Workspace saved', message: 'Workspace preferences updated.');
                      if (isModal) {
                        Navigator.of(context).pop(true);
                      }
                    }
                  },
          ),
        ],
      ),
    );
  }
}

/// Helper function to display the workspace customization screen as a responsive dialog.
Future<bool?> showThqWorkspaceCustomizationDialog({
  required BuildContext context,
  required ThqWorkspaceCustomizationController controller,
  required Future<void> Function(ThqUserUiPreferences) onSave,
}) {
  return showThqDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThqTokens.radiusLarge)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: ThqWorkspaceCustomizationView(
          controller: controller,
          onSave: onSave,
          isModal: true,
        ),
      ),
    ),
  );
}
