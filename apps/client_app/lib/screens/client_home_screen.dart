import 'dart:async';

import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../features/gst/gst_v520_entry_screen.dart';
import '../models/app_menu_node.dart';
import '../services/client_auth_service.dart';
import '../services/client_session_service.dart';
import '../services/device_heartbeat_service.dart';
import '../services/location_scope_service.dart';
import '../services/navigation_service.dart';
import '../services/thq_api_service.dart';
import '../services/ui_design_service.dart';
import '../ui/v43_theme.dart';
import 'accounting_screen.dart';
import 'approvals_screen.dart';
import 'backup_export_screen.dart';
import 'bulk_import_screen.dart';
import 'business_settings_screen.dart';
import 'client_login_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'error_logs_screen.dart';
import 'expenses_screen.dart';
import 'global_search_screen.dart';
import 'workshop_screen.dart';
import 'industry_workspace_screen.dart';
import 'inventory_products_screen.dart';
import 'loan_screen.dart';
import 'tracking_workspace_screen.dart';
import 'invoice_designer_screen.dart';
import 'division_overview_screen.dart';
import 'barcode_workbench_screen.dart';
import 'locations_screen.dart';
import 'payment_center_screen.dart';
import 'production_screen.dart';
import 'purchases_screen.dart';
import 'purchasing_v2_screen.dart';
import 'pricing_screen.dart';
import 'reports_screen.dart';
import 'returns_register_screen.dart';
import 'stock_transfers_screen.dart';
import 'tasks_screen.dart';
import 'notifications_screen.dart';
import 'operations_intelligence_screen.dart';
import 'restaurant_screen.dart';
import 'sales_screen.dart';
import 'suppliers_screen.dart';
import 'support_screen.dart';
import 'team_access_screen.dart';
import 'transport_service_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  final ClientSession session;

  const ClientHomeScreen({super.key, required this.session});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final ClientAuthService _authService = ClientAuthService();
  final ClientSessionService _sessionService = ClientSessionService();
  final TextEditingController _menuSearch = TextEditingController();
  late ClientSession _session;
  bool _refreshing = false;
  int _contentGeneration = 0;
  late Future<UiDesignProfile> _designFuture;
  final NavigationService _navigationService = NavigationService();
  final ThqApiService _thqApi = ThqApiService();
  Timer? _syncTimer;
  ThqSyncVersions? _syncVersions;
  bool _updatesAvailable = false;
  List<AppMenuNode> _menuNodes = const [];
  final Set<String> _expandedGroups = <String>{};

  String? _selectedModuleKey;
  bool _navCollapsed = false;
  String _menuQuery = '';

  List<ClientModule> get _modules => _session.modules
      .where((module) => module.key != 'pos')
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    LocationScopeService.initialize(_session);
    _designFuture = UiDesignService().load(
      tenantId: _session.business.id,
      appKey: 'client',
    );
    unawaited(DeviceHeartbeatService().send(_session));
    unawaited(_loadNavigation());
    unawaited(_startSyncMonitor());
    final modules = _modules;
    if (modules.isNotEmpty) {
      _selectedModuleKey = modules
          .firstWhere(
            (module) => module.key == 'dashboard',
            orElse: () => modules.first,
          )
          .key;
    }
  }


  Future<void> _startSyncMonitor() async {
    try {
      _syncVersions = await _thqApi.syncVersions(_session.business.id);
    } catch (_) {
      // The manual Refresh path remains available if the API gateway is not yet deployed.
    }
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted || _refreshing) return;
      try {
        final latest = await _thqApi.syncVersions(_session.business.id);
        final previous = _syncVersions;
        _syncVersions = latest;
        if (previous != null && latest.anyChangedFrom(previous) && mounted) {
          setState(() => _updatesAvailable = true);
        }
      } catch (_) {
        // Quiet background detection; explicit Refresh shows actionable failures.
      }
    });
  }

  Future<void> _loadNavigation({bool strict = false}) async {
    try {
      final rows = await _navigationService.load(
        tenantId: _session.business.id,
        appKey: 'client',
      );
      if (!mounted) return;
      setState(() {
        _menuNodes = rows;
        _expandedGroups
          ..clear()
          ..addAll(
            rows
                .where((n) => n.isGroup && !n.collapsedByDefault)
                .map((n) => n.id),
          );
      });
    } catch (error) {
      if (strict) rethrow;
      // Safe fallback: the flat module list remains usable during initial startup.
    }
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    final previousLocation = LocationScopeService.selectedLocationId.value;
    setState(() => _refreshing = true);
    try {
      final businesses = await _sessionService.getAvailableBusinesses();
      final currentBusiness = businesses.firstWhere(
        (business) => business.id == _session.business.id,
        orElse: () => _session.business,
      );
      final refreshed = await _sessionService.loadSession(
        business: currentBusiness,
        requireRuntime: true,
      );
      if (!mounted) return;

      _session = refreshed;
      if (previousLocation != null && refreshed.canAccessLocation(previousLocation)) {
        LocationScopeService.selectedLocationId.value = previousLocation;
      } else {
        LocationScopeService.initialize(refreshed);
      }
      _designFuture = UiDesignService().load(
        tenantId: refreshed.business.id,
        appKey: 'client',
      );
      await _loadNavigation(strict: true);
      if (!mounted) return;

      final available = _modules;
      if (available.isNotEmpty &&
          !available.any((module) => module.key == _selectedModuleKey)) {
        _selectedModuleKey = available
            .firstWhere(
              (module) => module.key == 'dashboard',
              orElse: () => available.first,
            )
            .key;
      }
      try {
        _syncVersions = await _thqApi.syncVersions(refreshed.business.id);
      } catch (_) {}
      if (!mounted) return;
      _updatesAvailable = false;
      setState(() => _contentGeneration++);
      unawaited(DeviceHeartbeatService().send(refreshed));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('THQ refreshed with the latest business, store, module and data changes.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _moduleLabel(String key, String fallback) {
    for (final node in _menuNodes) {
      if (node.isModule && node.moduleKey == key) return node.label;
    }
    return fallback;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _menuSearch.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ClientLoginScreen()),
      (_) => false,
    );
  }

  void _openSearch([String query = '']) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GlobalSearchScreen(
          session: _session,
          initialQuery: query.trim(),
        ),
      ),
    );
  }

  IconData _moduleIcon(String key) => switch (key) {
    'dashboard' => Icons.space_dashboard_outlined,
    'operations_intelligence' => Icons.monitor_heart_outlined,
    'inventory' => Icons.inventory_2_outlined,
    'sales' => Icons.receipt_long_outlined,
    'sales_details' => Icons.history_outlined,
    'purchases' => Icons.shopping_cart_outlined,
    'purchase_details' => Icons.list_alt_outlined,
    'loans' => Icons.account_balance_wallet_outlined,
    'pricing' => Icons.sell_outlined,
    'customers' => Icons.groups_outlined,
    'suppliers' => Icons.local_shipping_outlined,
    'expenses' => Icons.payments_outlined,
    'accounting' => Icons.account_balance_outlined,
    'gst_compliance' => Icons.receipt_long_outlined,
    'reports' => Icons.insights_outlined,
    'barcode' => Icons.qr_code_scanner_outlined,
    'warranty' => Icons.verified_user_outlined,
    'vehicle_compatibility' => Icons.directions_car_outlined,
    'payments' => Icons.account_balance_wallet_outlined,
    'bulk_import' => Icons.upload_file_outlined,
    'logs' => Icons.bug_report_outlined,
    'invoice_templates' => Icons.description_outlined,
    'settings' => Icons.tune_outlined,
    'locations' => Icons.store_mall_directory_outlined,
    'users' => Icons.manage_accounts_outlined,
    'production' => Icons.factory_outlined,
    'transport_service' => Icons.local_shipping_outlined,
    'restaurant' || 'restaurant_orders' => Icons.restaurant_outlined,
    'stock_transfers' => Icons.swap_horiz_outlined,
    'cashier_shifts' => Icons.account_balance_wallet_outlined,
    'notifications' => Icons.notifications_outlined,
    'tasks' => Icons.task_alt_outlined,
    'approvals' => Icons.approval_outlined,
    'backup' => Icons.backup_outlined,
    'support' => Icons.support_agent_outlined,
    'workshop' => Icons.build_outlined,
    'healthcare' => Icons.local_hospital_outlined,
    'lab' => Icons.biotech_outlined,
    'pharmacy' => Icons.medication_outlined,
    _ => Icons.extension_outlined,
  };

  List<ClientModule> _filteredModules() {
    final query = _menuQuery.trim().toLowerCase();
    if (query.isEmpty) return _modules;
    return _modules
        .where(
          (module) =>
              module.name.toLowerCase().contains(query) ||
              module.key.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  ClientModule? _selectedModule() {
    final modules = _modules;
    if (modules.isEmpty) return null;
    return modules.firstWhere(
      (module) => module.key == _selectedModuleKey,
      orElse: () => modules.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedModule();
    if (selected == null) {
      return const Scaffold(
        body: Center(child: Text('No modules are enabled for this business.')),
      );
    }

    return FutureBuilder<UiDesignProfile>(
      future: _designFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data ?? UiDesignProfile.fallback('client');
        return UiDesignScope(
          profile: profile,
          child: Theme(
            data: profile.theme(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 900) {
                  return _desktop(selected, profile);
                }
                return _mobile(selected, profile);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _desktop(ClientModule selected, UiDesignProfile profile) {
    final width = _navCollapsed ? 64.0 : 224.0;
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            width: width,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: profile.sidebar,
              border: Border(right: BorderSide(color: profile.border)),
              boxShadow: profile.sidebarStyle == 'floating'
                  ? [
                      BoxShadow(
                        color: profile.primary.withValues(alpha: 0.045),
                        blurRadius: 28,
                        offset: const Offset(8, 0),
                      ),
                    ]
                  : const [],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _brandHeader(collapsed: _navCollapsed, profile: profile),
                  if (!_navCollapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                      child: TextField(
                        controller: _menuSearch,
                        onChanged: (value) =>
                            setState(() => _menuQuery = value),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) _openSearch(value);
                        },
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Find menu or search THQâ€¦',
                          prefixIcon: Icon(Icons.search, size: 20),
                        ),
                      ),
                    ),
                  Expanded(
                    child: _navList(collapsed: _navCollapsed, profile: profile),
                  ),
                  const Divider(height: 1),
                  _navAction(
                    icon: _navCollapsed
                        ? Icons.keyboard_double_arrow_right
                        : Icons.keyboard_double_arrow_left,
                    label: _navCollapsed ? 'Expand' : 'Collapse',
                    collapsed: _navCollapsed,
                    onTap: () => setState(() => _navCollapsed = !_navCollapsed),
                  ),
                  _navAction(
                    icon: Icons.logout,
                    label: 'Sign Out',
                    collapsed: _navCollapsed,
                    onTap: _logout,
                  ),
                  DesktopReleaseStatus(compact: _navCollapsed),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _topBar(selected, profile),
                _SubscriptionBanner(session: _session),
                Expanded(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: LocationScopeService.selectedLocationId,
                    builder: (_, locationId, _) => KeyedSubtree(
                      key: ValueKey('${selected.key}:${locationId ?? 'all'}:$_contentGeneration'),
                      child: _ModulePage(
                        module: selected,
                        session: _session,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobile(ClientModule selected, UiDesignProfile profile) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_moduleLabel(selected.key, selected.name)),
        actions: [
          IconButton(
            tooltip: 'Refresh THQ',
            onPressed: _refreshing ? null : _refreshAll,
            icon: _refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Search THQ',
            onPressed: () => _openSearch(),
            icon: const Icon(Icons.search),
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              _brandHeader(collapsed: false, profile: profile),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _menuSearch,
                  onChanged: (value) => setState(() => _menuQuery = value),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.of(context).pop();
                      _openSearch(value);
                    }
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Find menu or search THQâ€¦',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _navList(
                  collapsed: false,
                  closeDrawer: true,
                  profile: profile,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign Out'),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _mobileScopeBar(),
          _SubscriptionBanner(session: _session),
          Expanded(
            child: ValueListenableBuilder<String?>(
              valueListenable: LocationScopeService.selectedLocationId,
              builder: (_, locationId, _) => KeyedSubtree(
                key: ValueKey('${selected.key}:${locationId ?? 'all'}:$_contentGeneration'),
                child: _ModulePage(module: selected, session: _session),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandHeader({required bool collapsed, UiDesignProfile? profile}) {
    final device = _session.device;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 10 : 12,
        10,
        collapsed ? 10 : 12,
        8,
      ),
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  profile?.primary ?? Theme.of(context).colorScheme.primary,
                  profile?.accent ?? Theme.of(context).colorScheme.tertiary,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.grid_view_rounded, color: Colors.white),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _session.business.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device == null
                        ? 'THQ Business â€¢ v${ThqReleaseContract.appVersion}'
                        : '${device.locationCode} â€¢ ${device.deviceCode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _menuNodeAllowed(AppMenuNode node) {
    final roles = (node.metadata['roles'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    final permissions = (node.metadata['permissions'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    final roleOk = roles.isEmpty || roles.any(_session.hasRole);
    final permissionOk =
        permissions.isEmpty || permissions.any(_session.hasPermission);
    return roleOk && permissionOk;
  }

  List<AppMenuNode> _menuChildren(String? parentId) {
    final rows = _menuNodes
        .where((node) => node.parentId == parentId && _menuNodeAllowed(node))
        .toList();
    rows.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return rows;
  }

  bool _nodeMatchesQuery(
    AppMenuNode node,
    Map<String, ClientModule> moduleMap,
    String query,
  ) {
    if (query.isEmpty) return true;
    if (node.label.toLowerCase().contains(query) ||
        node.nodeKey.toLowerCase().contains(query)) {
      return true;
    }
    if (node.isModule) {
      final module = moduleMap[node.moduleKey];
      if (module != null &&
          (module.name.toLowerCase().contains(query) ||
              module.key.toLowerCase().contains(query))) {
        return true;
      }
    }
    return _menuChildren(
      node.id,
    ).any((child) => _nodeMatchesQuery(child, moduleMap, query));
  }

  List<Widget> _renderMenuLevel({
    required String? parentId,
    required Map<String, ClientModule> moduleMap,
    required String query,
    required bool closeDrawer,
    required UiDesignProfile? profile,
    int depth = 0,
  }) {
    final widgets = <Widget>[];
    for (final node in _menuChildren(parentId)) {
      if (!_nodeMatchesQuery(node, moduleMap, query)) continue;
      final descendants = _renderMenuLevel(
        parentId: node.id,
        moduleMap: moduleMap,
        query: query,
        closeDrawer: closeDrawer,
        profile: profile,
        depth: depth + 1,
      );
      if (node.isModule) {
        final module = moduleMap[node.moduleKey];
        if (module == null) continue;
        if (descendants.isEmpty) {
          widgets.add(
            _moduleTile(
              module,
              node.label,
              false,
              closeDrawer,
              profile,
              nested: depth > 0,
            ),
          );
        } else {
          final expanded =
              query.isNotEmpty || _expandedGroups.contains(node.id);
          widgets.add(
            Padding(
              padding: EdgeInsets.only(left: depth * 6.0),
              child: Row(
                children: [
                  Expanded(
                    child: _moduleTile(
                      module,
                      node.label,
                      false,
                      closeDrawer,
                      profile,
                      nested: depth > 0,
                    ),
                  ),
                  IconButton(
                    tooltip: expanded ? 'Collapse submenu' : 'Expand submenu',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(
                      () => expanded
                          ? _expandedGroups.remove(node.id)
                          : _expandedGroups.add(node.id),
                    ),
                    icon: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 17,
                    ),
                  ),
                ],
              ),
            ),
          );
          if (expanded) widgets.addAll(descendants);
        }
        continue;
      }
      if (descendants.isEmpty) continue;
      final expanded = query.isNotEmpty || _expandedGroups.contains(node.id);
      widgets.add(
        Padding(
          padding: EdgeInsets.only(bottom: 3, left: depth * 6.0),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(
                    () => expanded
                        ? _expandedGroups.remove(node.id)
                        : _expandedGroups.add(node.id),
                  ),
                  child: SizedBox(
                    height: 32,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Icon(
                          _iconFromKey(node.iconKey),
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            node.label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .35,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                      ],
                    ),
                  ),
                ),
                if (expanded) ...descendants,
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _navList({
    required bool collapsed,
    bool closeDrawer = false,
    UiDesignProfile? profile,
  }) {
    if (_menuNodes.isEmpty) {
      final modules = _filteredModules();
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        children: modules
            .map(
              (module) => _moduleTile(
                module,
                module.name,
                collapsed,
                closeDrawer,
                profile,
              ),
            )
            .toList(),
      );
    }
    final query = _menuQuery.trim().toLowerCase();
    final moduleMap = {for (final module in _modules) module.key: module};
    final visibleModules = _menuNodes
        .where(
          (node) =>
              node.isModule &&
              moduleMap.containsKey(node.moduleKey) &&
              _menuNodeAllowed(node),
        )
        .where((node) => _nodeMatchesQuery(node, moduleMap, query))
        .toList();
    if (collapsed) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        children: visibleModules
            .map(
              (node) => _moduleTile(
                moduleMap[node.moduleKey]!,
                node.label,
                true,
                closeDrawer,
                profile,
              ),
            )
            .toList(),
      );
    }
    final widgets = _renderMenuLevel(
      parentId: null,
      moduleMap: moduleMap,
      query: query,
      closeDrawer: closeDrawer,
      profile: profile,
    );
    if (widgets.isEmpty) return const Center(child: Text('No matching menu'));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      children: widgets,
    );
  }

  Widget _moduleTile(
    ClientModule module,
    String label,
    bool collapsed,
    bool closeDrawer,
    UiDesignProfile? profile, {
    bool nested = false,
  }) {
    final active = module.key == _selectedModuleKey;
    final primary = profile?.primary ?? Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: collapsed ? label : '',
      child: Padding(
        padding: EdgeInsets.only(bottom: 2, left: nested && !collapsed ? 9 : 0),
        child: Material(
          color: active ? primary.withValues(alpha: .10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() => _selectedModuleKey = module.key);
              if (closeDrawer) Navigator.of(context).pop();
            },
            child: SizedBox(
              height: 38,
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  if (!collapsed) const SizedBox(width: 10),
                  Icon(
                    _moduleIcon(module.key),
                    size: 18,
                    color: active
                        ? primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFromKey(String key) => switch (key) {
    'dashboard' => Icons.dashboard_outlined,
    'operations' => Icons.point_of_sale_outlined,
    'contacts' => Icons.groups_outlined,
    'finance' => Icons.account_balance_outlined,
    'industry' => Icons.widgets_outlined,
    'settings' => Icons.settings_outlined,
    'pos' => Icons.point_of_sale,
    'terminal' => Icons.monitor_outlined,
    _ => Icons.folder_outlined,
  };

  Widget _navAction({
    required IconData icon,
    required String label,
    required bool collapsed,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: collapsed ? label : '',
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: collapsed ? null : Text(label),
        onTap: onTap,
      ),
    );
  }

  Widget _topBar(ClientModule selected, UiDesignProfile? profile) {
    final device = _session.device;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: profile?.surface ?? Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: profile?.border ?? Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _session.business.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  [
                    _moduleLabel(selected.key, selected.name),
                    if (device != null && device.locationCode.isNotEmpty)
                      device.locationCode,
                    if (device != null && device.deviceName.isNotEmpty)
                      device.deviceName,
                  ].join(' â€¢ '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _scopeSelector(width: 280),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _refreshing ? null : _refreshAll,
            icon: _refreshing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 18),
            label: Text(_updatesAvailable ? 'Updates â€¢ Refresh' : 'Refresh'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () => _openSearch(),
            icon: const Icon(Icons.search, size: 19),
            label: const Text('Search'),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: '${_session.username} â€¢ ${_session.roleLabel}',
            child: Container(
              constraints: const BoxConstraints(maxWidth: 210),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 15,
                    child: Text(
                      _session.username.isEmpty
                          ? '?'
                          : _session.username
                                .substring(0, 1)
                                .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _session.username.isEmpty
                              ? 'User'
                              : _session.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _session.roleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileScopeBar() {
    if (_session.locations.length <= 1 &&
        !_session.canViewAllLocations) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: _scopeSelector(),
    );
  }

  Widget _scopeSelector({double? width}) {
    return ValueListenableBuilder<String?>(
      valueListenable: LocationScopeService.selectedLocationId,
      builder: (context, value, _) {
        final validIds = _session.locations.map((e) => e.id).toSet();
        final selected = value == null || validIds.contains(value)
            ? value
            : null;
        return SizedBox(
          width: width,
          child: DropdownButtonFormField<String?>(
            key: ValueKey(selected),
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Store scope',
              prefixIcon: Icon(Icons.store_outlined, size: 19),
            ),
            items: [
              if (_session.canViewAllLocations)
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All stores â€¢ merged'),
                ),
              ...LocationScopeService.orderedLocations(_session).map(
                (location) => DropdownMenuItem<String?>(
                  value: location.id,
                  child: Text(
                    '${location.code} â€¢ ${location.name} â€¢ ${location.roleLabel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (newValue) {
              if (newValue == null) {
                LocationScopeService.selectAll(_session);
              } else {
                LocationScopeService.select(_session, newValue);
              }
            },
          ),
        );
      },
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  final ClientSession session;
  const _SubscriptionBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final status = session.subscription.status;
    if (!session.subscription.hasPlan ||
        status == 'active' ||
        status == 'trial') {
      return const SizedBox.shrink();
    }
    final blocked = session.subscription.blocksAccess;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      color: blocked
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.tertiaryContainer,
      child: Row(
        children: [
          Icon(
            blocked ? Icons.block_outlined : Icons.warning_amber_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Subscription ${status.replaceAll('_', ' ')}${blocked ? ' â€” contact your administrator to restore module access.' : '.'}',
            ),
          ),
        ],
      ),
    );
  }
}

class _ModulePage extends StatelessWidget {
  final ClientModule module;
  final ClientSession session;

  const _ModulePage({required this.module, required this.session});

  @override
  Widget build(BuildContext context) {
    return switch (module.key) {
      'dashboard' => DashboardScreen(session: session),
      'operations_intelligence' => OperationsIntelligenceScreen(session: session),
      'inventory' => InventoryProductsScreen(session: session),
      'warranty' => TrackingWorkspaceScreen(session: session),
      'suppliers' => SuppliersScreen(session: session),
      'purchases' => PurchasesScreen(session: session, startInCreate: true),
      'purchase_details' => PurchasingV2Screen(session: session),
      'loans' => LoanScreen(session: session),
      'pricing' => PricingScreen(session: session),
      'customers' => CustomersScreen(session: session),
      'sales' => SalesScreen(session: session, startInCreate: true),
      'sales_details' => SalesScreen(
        session: session,
        historyOnly: true,
        titleOverride: 'Sales Details',
      ),
      'expenses' => ExpensesScreen(session: session),
      'accounting' => AccountingScreen(session: session),
      'gst_compliance' => GstV520EntryScreen(session: session),
      'reports' => ReportsScreen(session: session),
      'returns' => ReturnsRegisterScreen(session: session),
      'invoice_templates' => InvoiceDesignerScreen(session: session),
      'division_overview' => DivisionOverviewScreen(session: session),
      'barcode' => BarcodeWorkbenchScreen(session: session),
      'stock_transfers' => StockTransfersScreen(session: session),
      'notifications' => NotificationsScreen(session: session),
      'tasks' => TasksScreen(session: session),
      'approvals' => ApprovalsScreen(session: session),
      'backup' => BackupExportScreen(session: session),
      'support' => SupportScreen(session: session),
      'payments' => PaymentCenterScreen(session: session),
      'bulk_import' => BulkImportScreen(session: session),
      'logs' => ErrorLogsScreen(session: session),
      'settings' => BusinessSettingsScreen(session: session),
      'locations' => LocationsScreen(session: session),
      'users' => TeamAccessScreen(session: session),
      'production' => ProductionScreen(session: session),
      'transport_service' => TransportServiceScreen(session: session),
      'restaurant' || 'restaurant_orders' => RestaurantScreen(session: session),
      'workshop' => WorkshopScreen(session: session),
      'healthcare' ||
      'lab' ||
      'pharmacy' => IndustryWorkspaceScreen(session: session, module: module),
      _ => _ComingSoon(module: module, session: session),
    };
  }
}

class _ComingSoon extends StatelessWidget {
  final ClientModule module;
  final ClientSession session;
  const _ComingSoon({required this.module, required this.session});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.widgets_outlined,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    module.name,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    module.description ??
                        'This module is enabled for this business.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${session.currencyCode} â€¢ ${session.locale}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
