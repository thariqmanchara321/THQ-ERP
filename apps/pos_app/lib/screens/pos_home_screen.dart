import 'dart:async';

import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/app_menu_node.dart';
import '../models/client_session.dart';
import '../services/client_auth_service.dart';
import '../services/client_session_service.dart';
import '../services/device_heartbeat_service.dart';
import '../services/location_scope_service.dart';
import '../services/navigation_service.dart';
import '../services/thq_api_service.dart';
import '../services/ui_design_service.dart';
import '../ui/v43_theme.dart';
import 'cashier_shift_screen.dart';
import 'customers_screen.dart';
import 'error_logs_screen.dart';
import 'expenses_screen.dart';
import 'inventory_products_screen.dart';
import 'loan_screen.dart';
import 'notifications_screen.dart';
import 'offline_pos_sync_screen.dart';
import 'pos_login_screen.dart';
import 'pos_screen.dart';
import 'pos_settings_screen.dart';
import 'purchases_screen.dart';
import 'restaurant_screen.dart';
import 'return_center_screen.dart';
import 'suppliers_screen.dart';
import 'support_screen.dart';
import 'terminal_day_screen.dart';

class PosHomeScreen extends StatefulWidget {
  final ClientSession session;
  const PosHomeScreen({super.key, required this.session});

  @override
  State<PosHomeScreen> createState() => _PosHomeScreenState();
}

class _PosPage {
  final String key;
  final String fallbackLabel;
  final IconData icon;
  final Widget screen;
  const _PosPage(this.key, this.fallbackLabel, this.icon, this.screen);
}

class _PosHomeScreenState extends State<PosHomeScreen> {
  late ClientSession _session;
  final ClientSessionService _sessionService = ClientSessionService();
  String? _selectedKey;
  bool _refreshing = false;
  int _contentGeneration = 0;
  bool _expanded = true;
  late Future<UiDesignProfile> _designFuture;
  final NavigationService _navigation = NavigationService();
  final ThqApiService _thqApi = ThqApiService();
  Timer? _syncTimer;
  ThqSyncVersions? _syncVersions;
  bool _updatesAvailable = false;
  List<AppMenuNode> _menu = const [];
  final Set<String> _expandedGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    LocationScopeService.initialize(_session);
    _designFuture = UiDesignService().load(
      tenantId: _session.business.id,
      appKey: 'pos',
    );
    final locationId = _session.device?.locationId;
    if (locationId != null && locationId.isNotEmpty) {
      LocationScopeService.selectedLocationId.value = locationId;
    }
    unawaited(DeviceHeartbeatService().send(_session));
    unawaited(_loadMenu());
    unawaited(_startSyncMonitor());
  }

  Future<void> _startSyncMonitor() async {
    try {
      _syncVersions = await _thqApi.syncVersions(_session.business.id);
    } catch (_) {
      // Manual Refresh remains available if the API gateway is temporarily unavailable.
    }
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || _refreshing) return;
      try {
        final latest = await _thqApi.syncVersions(_session.business.id);
        final previous = _syncVersions;
        _syncVersions = latest;
        // Apply Admin module/config changes automatically when it is safe.
        // Billing is deliberately protected because rebuilding it can discard
        // an unheld cart; in that case the existing Refresh action remains explicit.
        if (previous != null && mounted) {
          final configurationChanged =
              latest.configuration != previous.configuration;
          if (configurationChanged && _selectedKey != 'sales') {
            await _refreshAll();
            return;
          }
          if (latest.configurationOrMasterChangedFrom(previous)) {
            setState(() => _updatesAvailable = true);
          }
        }
      } catch (_) {
        // Background drift detection is intentionally non-blocking.
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMenu({bool strict = false}) async {
    try {
      final rows = await _navigation.load(
        tenantId: _session.business.id,
        appKey: 'pos',
      );
      if (!mounted) return;
      setState(() {
        _menu = rows;
        _expandedGroups
          ..clear()
          ..addAll(
            rows
                .where((node) => node.isGroup && !node.collapsedByDefault)
                .map((node) => node.id),
          );
      });
    } catch (error) {
      if (strict) rethrow;
      // Flat/default navigation remains available during initial startup.
    }
  }

  bool _allowed(String key) {
    final device = _session.device;
    if (device == null) return false;
    if (key == 'returns') {
      return (device.allowedModules.contains('returns') ||
              device.allowedModules.contains('sales') ||
              device.allowedModules.contains('purchases')) &&
          (_session.hasModule('returns') ||
              _session.hasModule('sales') ||
              _session.hasModule('purchases'));
    }
    return device.allowedModules.contains(key) && _session.hasModule(key);
  }

  bool _nodeAllowed(AppMenuNode node) {
    final roles = (node.metadata['roles'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    final permissions = (node.metadata['permissions'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    return (roles.isEmpty || roles.any(_session.hasRole)) &&
        (permissions.isEmpty || permissions.any(_session.hasPermission));
  }

  Map<String, _PosPage> get _available {
    final session = _session;
    final pages = <String, _PosPage>{};
    if (_allowed('sales')) {
      pages['sales'] = _PosPage(
        'sales',
        'Billing',
        Icons.point_of_sale,
        PosScreen(session: session),
      );
      pages['offline_sync'] = _PosPage(
        'offline_sync',
        'Offline Sync',
        Icons.cloud_sync_outlined,
        OfflinePosSyncScreen(session: session),
      );
    }
    if (_allowed('returns')) {
      pages['returns'] = _PosPage(
        'returns',
        'Returns',
        Icons.assignment_return_outlined,
        ReturnCenterScreen(session: session),
      );
    }
    if (_allowed('cashier_shifts')) {
      pages['cashier_shifts'] = _PosPage(
        'cashier_shifts',
        'Cashier Shift',
        Icons.account_balance_wallet_outlined,
        CashierShiftScreen(session: session),
      );
    }
    if (_allowed('terminal_day')) {
      pages['terminal_day'] = _PosPage(
        'terminal_day',
        'Terminal Daily',
        Icons.summarize_outlined,
        TerminalDayScreen(session: session),
      );
    }
    if (_allowed('restaurant')) {
      pages['restaurant'] = _PosPage(
        'restaurant',
        'Restaurant',
        Icons.restaurant_outlined,
        RestaurantScreen(session: session),
      );
    }
    if (_allowed('inventory')) {
      pages['inventory'] = _PosPage(
        'inventory',
        'Products',
        Icons.inventory_2_outlined,
        InventoryProductsScreen(session: session),
      );
    }
    if (_allowed('customers')) {
      pages['customers'] = _PosPage(
        'customers',
        'Customers',
        Icons.groups_outlined,
        CustomersScreen(session: session),
      );
    }
    if (_allowed('suppliers')) {
      pages['suppliers'] = _PosPage(
        'suppliers',
        'Suppliers',
        Icons.local_shipping_outlined,
        SuppliersScreen(session: session),
      );
    }
    if (_allowed('purchases')) {
      pages['purchases'] = _PosPage(
        'purchases',
        'Purchases',
        Icons.shopping_cart_outlined,
        PurchasesScreen(session: session),
      );
    }
    if (_allowed('loans')) {
      pages['loans'] = _PosPage(
        'loans',
        'Loans',
        Icons.account_balance_wallet_outlined,
        LoanScreen(session: session),
      );
    }
    if (_allowed('expenses')) {
      pages['expenses'] = _PosPage(
        'expenses',
        'Expenses',
        Icons.payments_outlined,
        ExpensesScreen(session: session),
      );
    }
    if (_allowed('notifications')) {
      pages['notifications'] = _PosPage(
        'notifications',
        'Notifications',
        Icons.notifications_outlined,
        NotificationsScreen(session: session),
      );
    }
    if (_allowed('support')) {
      pages['support'] = _PosPage(
        'support',
        'Support',
        Icons.support_agent_outlined,
        SupportScreen(session: session),
      );
    }
    if (_allowed('logs')) {
      pages['logs'] = _PosPage(
        'logs',
        'Logs',
        Icons.bug_report_outlined,
        ErrorLogsScreen(session: session, reportAppKey: 'pos'),
      );
    }
    if (session.hasRole('owner') || session.hasPermission('settings.manage')) {
      pages['settings'] = _PosPage(
        'settings',
        'Settings',
        Icons.settings_outlined,
        PosSettingsScreen(session: session),
      );
    }
    return pages;
  }

  List<_PosPage> get _orderedPages {
    final pages = _available;
    if (_menu.isEmpty) return pages.values.toList();
    final ordered = <_PosPage>[];
    final modules =
        _menu.where((node) => node.isModule && _nodeAllowed(node)).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final node in modules) {
      final page = pages[node.moduleKey];
      if (page != null && !ordered.any((item) => item.key == page.key)) {
        ordered.add(page);
      }
    }
    for (final page in pages.values) {
      if (!ordered.any((item) => item.key == page.key)) ordered.add(page);
    }
    return ordered;
  }

  String _label(String key, String fallback) {
    for (final node in _menu) {
      if (node.isModule && node.moduleKey == key && _nodeAllowed(node)) {
        return node.label;
      }
    }
    return fallback;
  }

  List<AppMenuNode> _children(String? parentId) {
    final rows = _menu
        .where((node) => node.parentId == parentId && _nodeAllowed(node))
        .toList();
    rows.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return rows;
  }

  List<Widget> _renderLevel(
    Map<String, _PosPage> pages,
    UiDesignProfile profile,
    String? parentId,
    int depth,
  ) {
    final widgets = <Widget>[];
    for (final node in _children(parentId)) {
      final children = _renderLevel(pages, profile, node.id, depth + 1);
      if (node.isModule) {
        final page = pages[node.moduleKey];
        if (page == null) continue;
        if (children.isEmpty) {
          widgets.add(
            Padding(
              padding: EdgeInsets.only(left: depth * 6.0),
              child: _tile(page, node.label, true, profile),
            ),
          );
        } else {
          final open = _expandedGroups.contains(node.id);
          widgets.add(
            Padding(
              padding: EdgeInsets.only(left: depth * 6.0),
              child: Row(
                children: [
                  Expanded(child: _tile(page, node.label, true, profile)),
                  IconButton(
                    tooltip: open ? 'Collapse submenu' : 'Expand submenu',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(
                      () => open
                          ? _expandedGroups.remove(node.id)
                          : _expandedGroups.add(node.id),
                    ),
                    icon: Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
          if (open) widgets.addAll(children);
        }
        continue;
      }
      if (children.isEmpty) continue;
      final open = _expandedGroups.contains(node.id);
      widgets.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 5.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => setState(
              () => open
                  ? _expandedGroups.remove(node.id)
                  : _expandedGroups.add(node.id),
            ),
            child: SizedBox(
              height: 29,
              child: Row(
                children: [
                  const SizedBox(width: 7),
                  Icon(_groupIcon(node.iconKey), size: 13),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      node.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 15),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      );
      if (open) widgets.addAll(children);
    }
    return widgets;
  }

  Future<void> _requestRefresh() async {
    if (_refreshing) return;
    if (_selectedKey == 'sales') {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Refresh POS?'),
          content: const Text(
            'Refresh reloads Billing. Complete or Hold any current cart first so unheld items are not lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    await _refreshAll();
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
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
      LocationScopeService.initialize(refreshed);
      _designFuture = UiDesignService().load(
        tenantId: refreshed.business.id,
        appKey: 'pos',
      );
      await _loadMenu(strict: true);
      if (!mounted) return;
      final availableKeys = _available.keys.toSet();
      if (_selectedKey == null || !availableKeys.contains(_selectedKey)) {
        _selectedKey = _orderedPages.isEmpty ? null : _orderedPages.first.key;
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
            'POS refreshed with the latest store, modules, products and configuration.',
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

  Future<void> _logout() async {
    await ClientAuthService().signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PosLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _orderedPages;
    if (pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('THQ POS')),
        body: Center(child: Text('No POS modules assigned to this terminal.')),
      );
    }
    _selectedKey ??= pages.first.key;
    if (!pages.any((page) => page.key == _selectedKey)) {
      _selectedKey = pages.first.key;
    }
    final page = pages.firstWhere((page) => page.key == _selectedKey);
    final narrow = MediaQuery.sizeOf(context).width < 860;
    final expanded = !narrow && _expanded;
    return FutureBuilder<UiDesignProfile>(
      future: _designFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data ?? UiDesignProfile.fallback('pos');
        return UiDesignScope(
          profile: profile,
          child: Theme(
            data: profile.theme(),
            child: Scaffold(
              body: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: expanded ? 190 : 56,
                    decoration: BoxDecoration(
                      color: profile.sidebar,
                      border: Border(right: BorderSide(color: profile.border)),
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          _brand(expanded, profile),
                          const Divider(height: 1),
                          Expanded(child: _nav(expanded, profile)),
                          const Divider(height: 1),
                          _user(expanded),
                          if (!narrow)
                            _action(
                              expanded
                                  ? Icons.keyboard_double_arrow_left
                                  : Icons.keyboard_double_arrow_right,
                              expanded ? 'Collapse' : 'Expand',
                              expanded,
                              () => setState(() => _expanded = !_expanded),
                            ),
                          _action(
                            Icons.refresh,
                            _refreshing
                                ? 'Refreshing…'
                                : (_updatesAvailable
                                      ? 'Updates • Refresh'
                                      : 'Refresh'),
                            expanded,
                            _refreshing ? () {} : _requestRefresh,
                          ),
                          _action(Icons.logout, 'Sign Out', expanded, _logout),
                          DesktopReleaseStatus(compact: !expanded),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey('${page.key}:$_contentGeneration'),
                      child: page.screen,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _brand(bool expanded, UiDesignProfile profile) {
    final logo = _session.setting('business.logo_url', '')?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.all(7),
      child: Row(
        mainAxisAlignment: expanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: profile.primary.withValues(alpha: .10),
            ),
            child: logo.isNotEmpty
                ? Image.network(
                    logo,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.point_of_sale, color: profile.primary),
                  )
                : Icon(Icons.point_of_sale, color: profile.primary),
          ),
          if (expanded) ...[
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _session.business.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${_session.device?.locationCode ?? ''} • ${_session.device?.deviceCode ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _nav(bool expanded, UiDesignProfile profile) {
    final pages = _available;
    if (_menu.isEmpty || !expanded) {
      return ListView(
        padding: const EdgeInsets.all(5),
        children: _orderedPages
            .map(
              (page) => _tile(
                page,
                _label(page.key, page.fallbackLabel),
                expanded,
                profile,
              ),
            )
            .toList(),
      );
    }
    final widgets = _renderLevel(pages, profile, null, 0);
    return ListView(padding: const EdgeInsets.all(5), children: widgets);
  }

  Widget _tile(
    _PosPage page,
    String label,
    bool expanded,
    UiDesignProfile profile,
  ) {
    final active = page.key == _selectedKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: expanded ? '' : label,
        child: Material(
          color: active
              ? profile.primary.withValues(alpha: .10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => setState(() => _selectedKey = page.key),
            child: SizedBox(
              height: 36,
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  if (expanded) const SizedBox(width: 8),
                  Icon(
                    page.icon,
                    size: 17,
                    color: active ? profile.primary : null,
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _user(bool expanded) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    child: Row(
      mainAxisAlignment: expanded
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 13,
          child: Text(
            _session.username.isEmpty
                ? '?'
                : _session.username[0].toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
        if (expanded) ...[
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _session.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _session.roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _action(
    IconData icon,
    String label,
    bool expanded,
    VoidCallback onTap,
  ) => Tooltip(
    message: expanded ? '' : label,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 34,
        child: Row(
          mainAxisAlignment: expanded
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            if (expanded) const SizedBox(width: 10),
            Icon(icon, size: 17),
            if (expanded) ...[
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 10.5)),
            ],
          ],
        ),
      ),
    ),
  );

  IconData _groupIcon(String key) => switch (key) {
    'pos' => Icons.point_of_sale,
    'terminal' => Icons.monitor_outlined,
    'inventory' => Icons.inventory_2_outlined,
    'settings' => Icons.settings_outlined,
    _ => Icons.folder_outlined,
  };
}
