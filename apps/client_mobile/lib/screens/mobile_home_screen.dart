import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_logistics/thq_logistics.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/mobile_session.dart';
import '../services/device_installation_service.dart';
import '../services/mobile_auth_service.dart';
import '../services/mobile_client_service.dart';
import '../widgets/mobile_workspace_widgets.dart';
import 'mobile_entry_screen.dart';
import 'workspace/mobile_primary_tabs.dart';
import 'workspace/mobile_tools_pages.dart';

class MobileHomeScreen extends StatefulWidget {
  final MobileSession session;

  const MobileHomeScreen({super.key, required this.session});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  final _service = MobileClientService();
  int _index = 0;
  String? _locationId;
  String _period = 'today';
  late Future<Map<String, dynamic>> _dashboard;

  @override
  void initState() {
    super.initState();
    _locationId = widget.session.canViewAllLocations
        ? null
        : widget.session.locationId;
    _dashboard = _loadDashboard();
  }

  String get _locationLabel {
    if (_locationId == null) {
      return 'Entire business';
    }
    for (final location in widget.session.locations) {
      if (location.id == _locationId) {
        return location.name;
      }
    }
    if (_locationId == widget.session.locationId) {
      return widget.session.locationName;
    }
    return 'Selected store';
  }

  Future<Map<String, dynamic>> _loadDashboard() => _service.performance(
    widget.session,
    locationId: _locationId,
    period: _period,
  );

  void _setPeriod(String period) {
    if (_period == period) return;
    setState(() {
      _period = period;
      _dashboard = _loadDashboard();
    });
  }

  void _refreshDashboard() {
    setState(() {
      _dashboard = _loadDashboard();
    });
  }

  Future<void> _selectLocation() async {
    if (!widget.session.canViewAllLocations) {
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => _LocationSheet(
        selected: _locationId,
        locations: widget.session.locations,
      ),
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _locationId = selected == _LocationSheet.allSentinel ? null : selected;
      _dashboard = _loadDashboard();
    });
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileGlobalSearchPage(
          session: widget.session,
          service: _service,
          locationId: _locationId,
        ),
      ),
    );
  }

  void _openNotifications() {
    if (!widget.session.canViewNotifications) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MobileNotificationsPage(session: widget.session, service: _service),
      ),
    );
  }

  void _openApprovals() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MobileApprovalsPage(session: widget.session, service: _service),
      ),
    );
  }

  void _openTraceability() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileTraceabilityPage(
          session: widget.session,
          service: _service,
          locationId: _locationId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _OverviewTab(
        session: widget.session,
        dashboard: _dashboard,
        locationLabel: _locationLabel,
        period: _period,
        onPeriod: _setPeriod,
        onRefresh: _refreshDashboard,
        onLocation: _selectLocation,
        onSearch: _openSearch,
        onNotifications: widget.session.canViewNotifications
            ? _openNotifications
            : null,
        onSales: () => setState(() => _index = 1),
        onInventory: () => setState(() => _index = 2),
        onMoney: () => setState(() => _index = 3),
        onApprovals: _openApprovals,
        onPurchases: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobilePurchasesPage(
              session: widget.session,
              service: _service,
              locationId: _locationId,
            ),
          ),
        ),
        onTraceability: _openTraceability,
      ),
      MobileSalesWorkspace(
        session: widget.session,
        service: _service,
        locationId: _locationId,
      ),
      MobileInventoryWorkspace(
        session: widget.session,
        service: _service,
        locationId: _locationId,
        onOpenTraceability: widget.session.canViewTraceability
            ? _openTraceability
            : null,
      ),
      MobileMoneyWorkspace(
        session: widget.session,
        service: _service,
        locationId: _locationId,
      ),
      _MoreTab(
        session: widget.session,
        service: _service,
        locationId: _locationId,
        locationLabel: _locationLabel,
        onLocation: _selectLocation,
        onSearch: _openSearch,
        onNotifications: _openNotifications,
        onApprovals: _openApprovals,
        onTraceability: _openTraceability,
        onLogout: _logout,
        onDeactivate: _deactivate,
      ),
    ];

    const titles = ['Overview', 'Sales', 'Inventory', 'Money', 'More'];

    return Scaffold(
      appBar: _index == 0
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titles[_index]),
                  Text(
                    _locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                const ThqAppearanceButton(),
                const ThqMotionButton(),
                if (widget.session.canViewAllLocations)
                  IconButton(
                    tooltip: 'Change store scope',
                    onPressed: _selectLocation,
                    icon: const Icon(Icons.store_mall_directory_outlined),
                  ),
                IconButton(
                  tooltip: 'Search business',
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search_rounded),
                ),
                if (widget.session.canViewNotifications)
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: _openNotifications,
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                const SizedBox(width: 4),
              ],
            ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Overview',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Sales',
              ),
              NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2_rounded),
                label: 'Stock',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Money',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz_rounded),
                selectedIcon: Icon(Icons.more_horiz_rounded),
                label: 'More',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await MobileAuthService().signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MobileEntryScreen()),
      (_) => false,
    );
  }

  Future<void> _deactivate() async {
    final confirmed = await showThqDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate this phone?'),
        content: const Text(
          'This removes the local activation from this phone. The business data in THQ is not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await MobileAuthService().signOut();
    await DeviceInstallationService().clearActivation();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MobileEntryScreen()),
      (_) => false,
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final MobileSession session;
  final Future<Map<String, dynamic>> dashboard;
  final String locationLabel;
  final String period;
  final ValueChanged<String> onPeriod;
  final VoidCallback onRefresh;
  final VoidCallback onLocation;
  final VoidCallback onSearch;
  final VoidCallback? onNotifications;
  final VoidCallback onSales;
  final VoidCallback onInventory;
  final VoidCallback onMoney;
  final VoidCallback onApprovals;
  final VoidCallback onPurchases;
  final VoidCallback onTraceability;

  const _OverviewTab({
    required this.session,
    required this.dashboard,
    required this.locationLabel,
    required this.period,
    required this.onPeriod,
    required this.onRefresh,
    required this.onLocation,
    required this.onSearch,
    required this.onNotifications,
    required this.onSales,
    required this.onInventory,
    required this.onMoney,
    required this.onApprovals,
    required this.onPurchases,
    required this.onTraceability,
  });

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => onRefresh(),
    child: FutureBuilder<Map<String, dynamic>>(
      future: dashboard,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final attention = data['attention'] is Map
            ? Map<String, dynamic>.from(data['attention'] as Map)
            : <String, dynamic>{};

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            WorkspaceHero(
              session: session,
              locationLabel: locationLabel,
              netSales: snapshot.hasData
                  ? workspaceMoney(session, data['net_sales'])
                  : '—',
              grossProfit: snapshot.hasData
                  ? workspaceMoney(session, data['gross_profit'])
                  : '—',
              invoices: snapshot.hasData
                  ? '${data['invoice_count'] ?? 0}'
                  : '—',
              approvals: snapshot.hasData
                  ? '${data['pending_approvals'] ?? 0}'
                  : '—',
              onSearch: onSearch,
              onNotifications: onNotifications,
              onRefresh: onRefresh,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (session.release.updateAvailable) ...[
                    ThqMobileUpdateBanner(
                      latestVersion: session.release.latestVersion,
                      notes: session.release.releaseNotes,
                      mandatory: session.release.updateRequired,
                      onTap: () => _showRelease(context, session.release),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'today',
                        label: Text('Today'),
                        icon: Icon(Icons.today_outlined),
                      ),
                      ButtonSegment<String>(
                        value: 'all_time',
                        label: Text('All time'),
                        icon: Icon(Icons.all_inclusive_rounded),
                      ),
                    ],
                    selected: <String>{period},
                    onSelectionChanged: (selection) =>
                        onPeriod(selection.first),
                  ),
                  const SizedBox(height: 10),
                  if (session.canViewAllLocations) ...[
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: const Icon(
                          Icons.store_mall_directory_outlined,
                        ),
                        title: const Text('Business / store scope'),
                        subtitle: Text(locationLabel),
                        trailing: const Icon(Icons.unfold_more_rounded),
                        onTap: onLocation,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (snapshot.connectionState != ConnectionState.done) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 12),
                  ],
                  if (snapshot.hasError) ...[
                    ThqMobileInlineMessage(
                      message: 'Dashboard could not refresh: ${snapshot.error}',
                      error: true,
                    ),
                    const SizedBox(height: 12),
                  ],
                  ThqMobileSectionHeader(
                    title: period == 'today'
                        ? 'Today performance'
                        : 'All-time performance',
                    subtitle: locationLabel,
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Sales',
                          value: workspaceMoney(session, data['sales']),
                          icon: Icons.point_of_sale_rounded,
                          onTap: onSales,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Purchases',
                          value: workspaceMoney(session, data['purchases']),
                          icon: Icons.shopping_bag_outlined,
                          onTap: onPurchases,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Expenses',
                          value: workspaceMoney(session, data['expenses']),
                          icon: Icons.receipt_long_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Net profit',
                          value: workspaceMoney(session, data['net_profit']),
                          icon: Icons.trending_up_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Gross profit',
                          value: workspaceMoney(session, data['gross_profit']),
                          icon: Icons.insights_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Stock value',
                          value: workspaceMoney(session, data['stock_value']),
                          icon: Icons.inventory_2_outlined,
                          onTap: onInventory,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Receivables',
                          value: workspaceMoney(session, data['receivables']),
                          icon: Icons.account_balance_wallet_outlined,
                          onTap: onMoney,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Payables',
                          value: workspaceMoney(session, data['payables']),
                          icon: Icons.payments_outlined,
                          onTap: onMoney,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const ThqMobileSectionHeader(
                    title: 'Workspaces',
                    subtitle: 'Fast access to day-to-day business activity.',
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: WorkspaceQuickAction(
                          label: 'Sales',
                          subtitle: 'Invoices & dues',
                          icon: Icons.point_of_sale_rounded,
                          onTap: onSales,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: WorkspaceQuickAction(
                          label: 'Inventory',
                          subtitle: 'Stock & value',
                          icon: Icons.inventory_2_outlined,
                          onTap: onInventory,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: WorkspaceQuickAction(
                          label: 'Money',
                          subtitle: 'Due & payments',
                          icon: Icons.account_balance_wallet_outlined,
                          onTap: onMoney,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: WorkspaceQuickAction(
                          label: 'Purchases',
                          subtitle: 'Supplier activity',
                          icon: Icons.shopping_bag_outlined,
                          onTap: onPurchases,
                        ),
                      ),
                    ],
                  ),
                  if (session.canApprove || session.canViewTraceability) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (session.canApprove)
                          Expanded(
                            child: WorkspaceQuickAction(
                              label: 'Approvals',
                              subtitle: 'Pending actions',
                              icon: Icons.approval_outlined,
                              onTap: onApprovals,
                            ),
                          ),
                        if (session.canApprove && session.canViewTraceability)
                          const SizedBox(width: 8),
                        if (session.canViewTraceability)
                          Expanded(
                            child: WorkspaceQuickAction(
                              label: 'Traceability',
                              subtitle: 'Serial & batch',
                              icon: Icons.qr_code_scanner_rounded,
                              onTap: onTraceability,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const ThqMobileSectionHeader(
                    title: 'Outstanding',
                    subtitle: 'Current receivable and payable position.',
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Customer due',
                          value: workspaceMoney(
                            session,
                            data['customer_outstanding'],
                          ),
                          icon: Icons.account_balance_wallet_outlined,
                          onTap: onMoney,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ThqMobileMetricCard(
                          label: 'Supplier due',
                          value: workspaceMoney(
                            session,
                            data['supplier_outstanding'],
                          ),
                          icon: Icons.payments_outlined,
                          onTap: onMoney,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const ThqMobileSectionHeader(
                    title: 'Attention',
                    subtitle: 'Items that may need action today.',
                  ),
                  const SizedBox(height: 9),
                  Card(
                    child: Column(
                      children: [
                        _AttentionTile(
                          icon: Icons.warning_amber_rounded,
                          title: 'Low stock',
                          value: '${attention['low_stock'] ?? 0}',
                          onTap: onInventory,
                        ),
                        const Divider(indent: 52),
                        _AttentionTile(
                          icon: Icons.remove_shopping_cart_outlined,
                          title: 'Out of stock',
                          value: '${attention['out_of_stock'] ?? 0}',
                          onTap: onInventory,
                        ),
                        const Divider(indent: 52),
                        _AttentionTile(
                          icon: Icons.schedule_rounded,
                          title: 'Overdue receivables',
                          value: workspaceMoney(
                            session,
                            attention['overdue_receivables'],
                          ),
                          onTap: onMoney,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  static Future<void> _showRelease(
    BuildContext context,
    ThqMobileReleaseStatus release,
  ) async {
    await showThqDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          release.updateRequired ? 'Update required' : 'Update available',
        ),
        content: Text(
          release.releaseNotes.isEmpty
              ? 'A newer Client Mobile build is available.'
              : release.releaseNotes,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _MoreTab extends StatelessWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;
  final String locationLabel;
  final VoidCallback onLocation;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final VoidCallback onApprovals;
  final VoidCallback onTraceability;
  final Future<void> Function() onLogout;
  final Future<void> Function() onDeactivate;

  const _MoreTab({
    required this.session,
    required this.service,
    required this.locationId,
    required this.locationLabel,
    required this.onLocation,
    required this.onSearch,
    required this.onNotifications,
    required this.onApprovals,
    required this.onTraceability,
    required this.onLogout,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                child: Text(
                  session.username.isEmpty
                      ? 'U'
                      : session.username.substring(0, 1).toUpperCase(),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.username,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${session.businessName} • $locationLabel',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      const ThqMobileSectionHeader(
        title: 'Business tools',
        subtitle: 'Reports, controls and operational workspaces.',
      ),
      const SizedBox(height: 8),
      _MoreAction(
        icon: Icons.manage_search_rounded,
        title: 'Search business',
        subtitle: 'Sales, purchases, stock and parties',
        onTap: onSearch,
      ),
      _MoreAction(
        icon: Icons.shopping_bag_outlined,
        title: 'Purchases',
        subtitle: 'Recent supplier documents and balances',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobilePurchasesPage(
              session: session,
              service: service,
              locationId: locationId,
            ),
          ),
        ),
      ),
      _MoreAction(
        icon: Icons.storefront_outlined,
        title: 'Store performance',
        subtitle: 'Sales, profit, stock and dues by store',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                MobileStorePerformancePage(session: session, service: service),
          ),
        ),
      ),
      _MoreAction(
        icon: Icons.analytics_outlined,
        title: 'Reports',
        subtitle: 'Business summary by date range',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileReportsPage(
              session: session,
              service: service,
              locationId: locationId,
            ),
          ),
        ),
      ),
      if (session.canApprove)
        _MoreAction(
          icon: Icons.approval_outlined,
          title: 'Approvals',
          subtitle: 'Review and decide pending requests',
          onTap: onApprovals,
        ),
      if (session.canViewNotifications)
        _MoreAction(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications',
          subtitle: 'Business alerts and reminders',
          onTap: onNotifications,
        ),
      if (session.canViewAudit)
        _MoreAction(
          icon: Icons.shield_outlined,
          title: 'Audit Center',
          subtitle: 'High risk, review and normal activity',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MobileAuditPage(
                session: session,
                service: service,
                locationId: locationId,
              ),
            ),
          ),
        ),
      if (session.canViewTraceability)
        _MoreAction(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Serial, batch & warranty',
          subtitle: 'Trace stock from receipt through sale',
          onTap: onTraceability,
        ),
      _MoreAction(
        icon: Icons.route_outlined,
        title: 'Logistics operations',
        subtitle: 'Trips, movement and logistics execution',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LogisticsOperationsWorkspace(
              tenantId: session.tenantId,
              locationId: locationId,
            ),
          ),
        ),
      ),
      _MoreAction(
        icon: Icons.local_shipping_outlined,
        title: 'Vehicle logistics',
        subtitle: 'Vehicle stock movement reporting',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VehicleLogisticsReportWorkspace(
              tenantId: session.tenantId,
              locationId: locationId,
            ),
          ),
        ),
      ),
      if (session.canViewAllLocations)
        _MoreAction(
          icon: Icons.store_mall_directory_outlined,
          title: 'Change store scope',
          subtitle: locationLabel,
          onTap: onLocation,
        ),
      if (session.release.updateAvailable) ...[
        ThqMobileReleaseBanner(
          currentVersion: ThqClientMobileReleaseContract.appVersion,
          latestVersion: session.release.latestVersion,
          notes: session.release.releaseNotes,
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 14),
      const ThqMobileSectionHeader(
        title: 'Device',
        subtitle: 'Current installation and release information.',
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.deviceName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Text(
                '${session.deviceCode} • ${session.locationName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'THQ Client Mobile ${ThqClientMobileReleaseContract.versionLabel}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (session.release.latestVersion.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Release service: ${session.release.status} • latest ${session.release.latestVersion}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: onLogout,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: onDeactivate,
        icon: const Icon(Icons.phonelink_erase_outlined),
        label: const Text('Deactivate this phone'),
      ),
    ],
  );
}

class _AttentionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _AttentionTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    onTap: onTap,
    leading: Icon(icon, size: 21),
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right_rounded, size: 19),
      ],
    ),
  );
}

class _MoreAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    ),
  );
}

class _LocationSheet extends StatelessWidget {
  static const allSentinel = '__all__';

  final String? selected;
  final List<MobileLocation> locations;

  const _LocationSheet({required this.selected, required this.locations});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ThqMobileSectionHeader(
          title: 'Store scope',
          subtitle: 'Choose the location used by workspace views.',
        ),
        const SizedBox(height: 10),
        ListTile(
          leading: const Icon(Icons.public_rounded),
          title: const Text('All accessible stores'),
          trailing: selected == null ? const Icon(Icons.check_rounded) : null,
          onTap: () => Navigator.pop(context, allSentinel),
        ),
        ...locations.map(
          (location) => ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(location.name),
            subtitle: location.code.isEmpty ? null : Text(location.code),
            trailing: selected == location.id
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context, location.id),
          ),
        ),
      ],
    ),
  );
}
