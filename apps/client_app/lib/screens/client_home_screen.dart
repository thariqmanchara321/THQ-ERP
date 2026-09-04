import 'dart:async';

import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../features/gst/gst_v520_entry_screen.dart';
import '../features/audit_intelligence/audit_intelligence_screen.dart';
import '../models/app_menu_node.dart';
import '../services/client_auth_service.dart';
import '../services/client_session_service.dart';
import '../services/device_heartbeat_service.dart';
import '../services/location_scope_service.dart';
import '../services/navigation_service.dart';
import '../services/thq_api_service.dart';
import '../services/ui_design_service.dart';
import '../ui/v43_theme.dart';
import '../ui/v600_client_theme.dart';
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
  final FocusScopeNode _workspaceFocusScope = FocusScopeNode(
    debugLabel: 'THQ Client workspace',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  late ClientSession _session;
  bool _refreshing = false;
  int _contentGeneration = 0;
  final UiDesignProfile _fallbackProfile = UiDesignProfile.fallback('client');
  UiDesignProfile? _themeProfile;
  ThemeData? _themeCache;
  late Future<UiDesignProfile> _designFuture;
  final NavigationService _navigationService = NavigationService();
  final ThqApiService _thqApi = ThqApiService();
  Timer? _syncWarmupTimer;
  Timer? _syncTimer;
  bool _syncCheckBusy = false;
  ThqSyncVersions? _syncVersions;
  bool _updatesAvailable = false;
  List<AppMenuNode> _menuNodes = const [];
  Map<String?, List<AppMenuNode>> _menuChildrenIndex = const {};
  List<ClientModule> _moduleCache = const [];
  Map<String, ClientModule> _moduleMap = const {};
  final Set<String> _expandedGroups = <String>{};

  String? _selectedModuleKey;
  bool _navCollapsed = false;
  String _menuQuery = '';

  List<ClientModule> get _modules => _moduleCache;

  void _rebuildSessionCaches() {
    final modules = _session.modules
        .where((module) => module.key != 'pos')
        .toList(growable: false);
    _moduleCache = modules;
    _moduleMap = {for (final module in modules) module.key: module};
  }

  Map<String?, List<AppMenuNode>> _indexMenu(List<AppMenuNode> rows) {
    final index = <String?, List<AppMenuNode>>{};
    for (final node in rows) {
      if (!_menuNodeAllowed(node)) continue;
      index.putIfAbsent(node.parentId, () => <AppMenuNode>[]).add(node);
    }
    for (final children in index.values) {
      children.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
      });
    }
    return index;
  }

  ThemeData _themeFor(UiDesignProfile profile) {
    final cached = _themeCache;
    if (cached != null && identical(_themeProfile, profile)) return cached;
    final resolved = ClientV600Theme.apply(profile.theme(), profile);
    _themeProfile = profile;
    _themeCache = resolved;
    return resolved;
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _rebuildSessionCaches();
    LocationScopeService.initialize(_session);
    _designFuture = UiDesignService().load(
      tenantId: _session.business.id,
      appKey: 'client',
    );
    unawaited(DeviceHeartbeatService().send(_session));
    unawaited(_loadNavigation());
    _startSyncMonitor();
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

  void _startSyncMonitor() {
    _syncWarmupTimer?.cancel();
    _syncTimer?.cancel();

    // Do not compete with first paint and the first module's data load.
    _syncWarmupTimer = Timer(const Duration(seconds: 15), () {
      unawaited(_checkSyncVersions());
    });
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_checkSyncVersions());
    });
  }

  Future<void> _checkSyncVersions() async {
    if (!mounted || _refreshing || _syncCheckBusy) return;
    _syncCheckBusy = true;
    try {
      final latest = await _thqApi.syncVersions(_session.business.id);
      final previous = _syncVersions;
      _syncVersions = latest;

      if (previous != null && mounted) {
        final configurationChanged =
            latest.configuration != previous.configuration;
        final transactionWorkspace = <String>{
          'sales',
          'purchases',
          'stock_transfers',
          'loans',
          'expenses',
          'production',
          'transport_service',
          'restaurant',
          'restaurant_orders',
        }.contains(_selectedModuleKey);

        if (configurationChanged && !transactionWorkspace) {
          await _refreshAll();
          return;
        }

        if (latest.anyChangedFrom(previous)) {
          setState(() => _updatesAvailable = true);
        }
      }
    } catch (_) {
      // Quiet background detection; explicit Refresh shows actionable failures.
    } finally {
      _syncCheckBusy = false;
    }
  }

  Future<void> _loadNavigation({bool strict = false}) async {
    try {
      final rows = await _navigationService.load(
        tenantId: _session.business.id,
        appKey: 'client',
      );
      if (!mounted) return;
      final menuIndex = _indexMenu(rows);
      setState(() {
        _menuNodes = rows;
        _menuChildrenIndex = menuIndex;
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
      _rebuildSessionCaches();
      if (previousLocation != null &&
          refreshed.canAccessLocation(previousLocation)) {
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
        const SnackBar(
          content: Text(
            'THQ refreshed with the latest business, store, module and data changes.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Refresh failed: $error')));
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
    _syncWarmupTimer?.cancel();
    _syncTimer?.cancel();
    _workspaceFocusScope.dispose();
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
        builder: (_) =>
            GlobalSearchScreen(session: _session, initialQuery: query.trim()),
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
    'audit_center' => Icons.policy_outlined,
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
        final profile = snapshot.data ?? _fallbackProfile;
        return UiDesignScope(
          profile: profile,
          child: Theme(
            data: _themeFor(profile),
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
    final width = _navCollapsed ? 56.0 : 208.0;
    final workspaceBackground = Color.alphaBlend(
      profile.primary.withValues(alpha: .035),
      profile.background,
    );
    final sidebarBackground = Color.alphaBlend(
      profile.primary.withValues(alpha: .055),
      profile.surface,
    );

    return Scaffold(
      backgroundColor: workspaceBackground,
      body: Row(
        children: [
          AnimatedContainer(
            width: width,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: sidebarBackground,
              border: Border(right: BorderSide(color: profile.border)),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _brandHeader(collapsed: _navCollapsed, profile: profile),
                  if (!_navCollapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                      child: SizedBox(
                        height: 34,
                        child: TextField(
                          controller: _menuSearch,
                          onChanged: (value) =>
                              setState(() => _menuQuery = value),
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) _openSearch(value);
                          },
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Find anything...',
                            prefixIcon: Icon(Icons.search, size: 17),
                          ),
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
                    icon: Icons.logout_rounded,
                    label: 'Sign Out',
                    collapsed: _navCollapsed,
                    onTap: _logout,
                  ),
                  if (!_navCollapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                      child: Text(
                        'v${ThqReleaseContract.appVersion}  |  Build ${ThqReleaseContract.buildNumber}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 6),
                ],
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: workspaceBackground,
              child: Column(
                children: [
                  _topBar(selected, profile),
                  _SubscriptionBanner(session: _session),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: profile.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: profile.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .035),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: ValueListenableBuilder<String?>(
                            valueListenable:
                                LocationScopeService.selectedLocationId,
                            builder: (_, locationId, _) => FocusScope(
                              node: _workspaceFocusScope,
                              child: FocusTraversalGroup(
                                policy: WidgetOrderTraversalPolicy(),
                                child: KeyedSubtree(
                                  key: ValueKey(
                                    '${selected.key}:${locationId ?? 'all'}:$_contentGeneration',
                                  ),
                                  child: _ModulePage(
                                    module: selected,
                                    session: _session,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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

  Widget _mobile(ClientModule selected, UiDesignProfile profile) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_moduleLabel(selected.key, selected.name)),
        actions: [
          IconButton(
            tooltip: 'Refresh THQ',
            onPressed: _refreshing ? null : _refreshAll,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
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
                    hintText: 'Find menu or search THQ...',
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
              Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign Out'),
                  onTap: _logout,
                ),
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
                key: ValueKey(
                  '${selected.key}:${locationId ?? 'all'}:$_contentGeneration',
                ),
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
                        ? 'THQ Business | v${ThqReleaseContract.appVersion}'
                        : '${device.locationCode} | ${device.deviceCode}',
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

  List<AppMenuNode> _menuChildren(String? parentId) =>
      _menuChildrenIndex[parentId] ?? const [];

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
    final moduleMap = _moduleMap;
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
    final scheme = Theme.of(context).colorScheme;
    final primary = profile?.primary ?? scheme.primary;
    final inactive = scheme.onSurfaceVariant;

    final tile = Material(
      color: active
          ? Color.alphaBlend(primary.withValues(alpha: .12), scheme.surface)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() => _selectedModuleKey = module.key);
          if (closeDrawer) Navigator.of(context).pop();
        },
        child: SizedBox(
          height: 34,
          child: Row(
            children: [
              Container(
                width: 3,
                height: double.infinity,
                color: active ? primary : Colors.transparent,
              ),
              if (!collapsed) const SizedBox(width: 7),
              Expanded(
                flex: collapsed ? 1 : 0,
                child: Align(
                  alignment: collapsed
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Icon(
                    _moduleIcon(module.key),
                    size: 17,
                    color: active ? primary : inactive,
                  ),
                ),
              ),
              if (!collapsed) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? scheme.onSurface : inactive,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: collapsed ? label : '',
      child: Padding(
        padding: EdgeInsets.only(bottom: 2, left: nested && !collapsed ? 8 : 0),
        child: tile,
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
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          leading: Icon(icon),
          title: collapsed ? null : Text(label),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _topBar(ClientModule selected, UiDesignProfile? profile) {
    final device = _session.device;
    final scheme = Theme.of(context).colorScheme;
    final border = profile?.border ?? Theme.of(context).dividerColor;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: profile?.surface ?? scheme.surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: profile?.primary ?? scheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _moduleLabel(selected.key, selected.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.15,
                  ),
                ),
                Text(
                  [
                    _session.business.name,
                    if (device != null && device.locationCode.isNotEmpty)
                      device.locationCode,
                    if (device != null && device.deviceName.isNotEmpty)
                      device.deviceName,
                  ].join('  |  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _scopeSelector(width: 238),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _updatesAvailable
                ? 'Updates available - Refresh'
                : 'Refresh',
            visualDensity: VisualDensity.compact,
            onPressed: _refreshing ? null : _refreshAll,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    isLabelVisible: _updatesAvailable,
                    child: const Icon(Icons.refresh_rounded, size: 19),
                  ),
          ),
          IconButton(
            tooltip: 'Search THQ',
            visualDensity: VisualDensity.compact,
            onPressed: () => _openSearch(),
            icon: const Icon(Icons.search_rounded, size: 19),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: '${_session.username} | ${_session.roleLabel}',
            child: Container(
              constraints: const BoxConstraints(maxWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 12,
                    child: Text(
                      _session.username.isEmpty
                          ? '?'
                          : _session.username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _session.username.isEmpty ? 'User' : _session.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
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
    if (_session.locations.length <= 1 && !_session.canViewAllLocations) {
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
                  child: Text('All stores | merged'),
                ),
              ...LocationScopeService.orderedLocations(_session).map(
                (location) => DropdownMenuItem<String?>(
                  value: location.id,
                  child: Text(
                    '${location.code} | ${location.name} | ${location.roleLabel}',
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
              'Subscription ${status.replaceAll('_', ' ')}${blocked ? ' - contact your administrator to restore module access.' : '.'}',
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
      'operations_intelligence' => OperationsIntelligenceScreen(
        session: session,
      ),
      'inventory' => InventoryProductsScreen(session: session),
      'warranty' => TrackingWorkspaceScreen(session: session),
      'suppliers' => SuppliersScreen(session: session),
      'purchases' => PurchasesScreen(session: session, startInCreate: true),
      'purchase_details' => PurchasesScreen(
        session: session,
        historyOnly: true,
      ),
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
      'audit_center' => AuditIntelligenceScreen(session: session),
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
                    '${session.currencyCode} | ${session.locale}',
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
