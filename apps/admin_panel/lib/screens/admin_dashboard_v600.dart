import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../services/admin_auth_service.dart';
import '../services/platform_config_service.dart';
import 'app_versions_screen.dart';
import 'businesses_screen.dart';
import 'invoice_templates_screen.dart';
import 'login_screen.dart';
import 'menu_builder_screen.dart';
import 'modules_screen.dart';
import 'platform_admins_screen.dart';
import 'platform_audit_screen.dart';
import 'platform_error_logs_screen.dart';
import 'platform_settings_screen.dart';
import 'platform_support_screen.dart';
import 'subscription_plans_screen.dart';
import 'templates_screen.dart';
import 'transaction_control_screen.dart';
import 'ui_design_studio_screen.dart';

/// v6 desktop-first Admin control centre.
///
/// This screen changes presentation only. Existing services, permissions,
/// navigation targets and backend writers remain authoritative.
class AdminDashboardV600 extends StatefulWidget {
  const AdminDashboardV600({super.key});

  @override
  State<AdminDashboardV600> createState() => _AdminDashboardV600State();
}

class _AdminDashboardV600State extends State<AdminDashboardV600> {
  final AdminAuthService _auth = AdminAuthService();
  late Future<Map<String, dynamic>> _overviewFuture;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  bool _refreshing = false;
  bool _navCollapsed = false;

  static const List<ThqNavDestination> _destinations = [
    ThqNavDestination(
      keyName: 'overview',
      label: 'Overview',
      icon: Icons.space_dashboard_outlined,
    ),
    ThqNavDestination(
      keyName: 'businesses',
      label: 'Businesses',
      icon: Icons.store_outlined,
    ),
    ThqNavDestination(
      keyName: 'modules',
      label: 'Modules',
      icon: Icons.extension_outlined,
    ),
    ThqNavDestination(
      keyName: 'menu',
      label: 'Menu Builder',
      icon: Icons.account_tree_outlined,
    ),
    ThqNavDestination(
      keyName: 'design',
      label: 'Design Studio',
      icon: Icons.palette_outlined,
    ),
    ThqNavDestination(
      keyName: 'subscriptions',
      label: 'Subscriptions',
      icon: Icons.payments_outlined,
    ),
    ThqNavDestination(
      keyName: 'transactions',
      label: 'Transactions',
      icon: Icons.manage_search_outlined,
    ),
    ThqNavDestination(
      keyName: 'settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
    ),
    ThqNavDestination(
      keyName: 'support',
      label: 'Support',
      icon: Icons.support_agent_outlined,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _overviewFuture = PlatformConfigService().getOverview();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _overviewFuture = PlatformConfigService().getOverview();
    });
    try {
      await _overviewFuture;
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        const SnackBar(
          content: Text(
            'THQ Platform refreshed. Saved Admin changes are available to Client/POS after Refresh.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('Refresh failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openDestination(String key) {
    switch (key) {
      case 'overview':
        return;
      case 'businesses':
        _open(const BusinessesScreen());
        return;
      case 'modules':
        _open(const ModulesScreen());
        return;
      case 'menu':
        _open(const MenuBuilderScreen());
        return;
      case 'design':
        _open(const UiDesignStudioScreen());
        return;
      case 'subscriptions':
        _open(const SubscriptionPlansScreen());
        return;
      case 'transactions':
        _open(const TransactionControlScreen());
        return;
      case 'settings':
        _open(const PlatformSettingsScreen());
        return;
      case 'support':
        _open(const PlatformSupportScreen());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < ThqBreakpoints.compact;
    return ThqDesktopShell(
      destinations: _destinations,
      selectedKey: 'overview',
      onDestinationSelected: _openDestination,
      collapsed: _navCollapsed,
      onCollapsedChanged: (value) => setState(() => _navCollapsed = value),
      brand: const _AdminBrand(),
      mobileDrawerHeader: const _AdminBrand(),
      sidebarFooter: _AdminFooter(
        now: _now,
        collapsed: _navCollapsed,
        onLogout: _logout,
      ),
      topBar: ThqTopBar(
        title: 'Platform Control Centre',
        subtitle: 'THQ ERP administration and governance',
        leading: mobile
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: 'Open navigation',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
              )
            : null,
        scope: FutureBuilder<String>(
          future: _auth.currentUsername(),
          builder: (_, snapshot) {
            final value = snapshot.data;
            return Text(
              value == null || value.isEmpty ? 'Platform Admin' : '@$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Platform',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ThqPageFrame(
        title: 'Overview',
        subtitle:
            'Businesses, modules, subscriptions, design, security and platform operations.',
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _metrics()),
            const SliverToBoxAdapter(
              child: SizedBox(height: ThqTokens.space16),
            ),
            const SliverToBoxAdapter(
              child: ThqSectionHeader(
                title: 'Platform workspaces',
                subtitle:
                    'Open a control area without leaving the Admin context.',
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: ThqTokens.space10),
            ),
            SliverToBoxAdapter(child: _commands()),
            const SliverToBoxAdapter(
              child: SizedBox(height: ThqTokens.space16),
            ),
            SliverToBoxAdapter(child: _securityCard()),
            const SliverToBoxAdapter(
              child: SizedBox(height: ThqTokens.space12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metrics() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _overviewFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        return ThqResponsiveWrap(
          minItemWidth: 155,
          maxColumns: 7,
          spacing: ThqTokens.space8,
          runSpacing: ThqTokens.space8,
          children: [
            ThqMetricCard(
              label: 'Release',
              value:
                  'v${ThqReleaseContract.appVersion} • B${ThqReleaseContract.buildNumber}',
              icon: Icons.code_outlined,
            ),
            ThqMetricCard(
              label: 'Businesses',
              value: data['businesses']?.toString() ?? '—',
              icon: Icons.store_outlined,
            ),
            ThqMetricCard(
              label: 'Active',
              value: data['active_businesses']?.toString() ?? '—',
              icon: Icons.check_circle_outline,
            ),
            ThqMetricCard(
              label: 'Subscriptions',
              value: data['active_subscriptions']?.toString() ?? '—',
              icon: Icons.payments_outlined,
            ),
            ThqMetricCard(
              label: 'Trials',
              value: data['trials']?.toString() ?? '—',
              icon: Icons.hourglass_bottom_outlined,
            ),
            ThqMetricCard(
              label: 'Modules',
              value: data['modules']?.toString() ?? '—',
              icon: Icons.extension_outlined,
            ),
            ThqMetricCard(
              label: 'Templates',
              value: data['templates']?.toString() ?? '—',
              icon: Icons.dashboard_customize_outlined,
            ),
          ],
        );
      },
    );
  }

  Widget _commands() {
    return ThqResponsiveWrap(
      minItemWidth: 235,
      maxColumns: 4,
      children: [
        ThqCommandCard(
          title: 'Businesses',
          subtitle: 'Tenants, users, roles and modules',
          icon: Icons.store_outlined,
          onTap: () => _open(const BusinessesScreen()),
        ),
        ThqCommandCard(
          title: 'Modules',
          subtitle: 'Core, POS and industry capabilities',
          icon: Icons.extension_outlined,
          onTap: () => _open(const ModulesScreen()),
        ),
        ThqCommandCard(
          title: 'Menu Builder',
          subtitle: 'Nested Client/POS navigation and names',
          icon: Icons.account_tree_outlined,
          onTap: () => _open(const MenuBuilderScreen()),
        ),
        ThqCommandCard(
          title: 'Templates',
          subtitle: 'Reusable business configuration presets',
          icon: Icons.dashboard_customize_outlined,
          onTap: () => _open(const TemplatesScreen()),
        ),
        ThqCommandCard(
          title: 'Design Studio',
          subtitle: 'Client/POS themes, colors and layouts',
          icon: Icons.palette_outlined,
          onTap: () => _open(const UiDesignStudioScreen()),
        ),
        ThqCommandCard(
          title: 'Subscriptions',
          subtitle: 'Plans, entitlements and limits',
          icon: Icons.payments_outlined,
          onTap: () => _open(const SubscriptionPlansScreen()),
        ),
        ThqCommandCard(
          title: 'Platform Admins',
          subtitle: 'Separated administrative responsibilities',
          icon: Icons.admin_panel_settings_outlined,
          onTap: () => _open(const PlatformAdminsScreen()),
        ),
        ThqCommandCard(
          title: 'Settings',
          subtitle: 'Global platform defaults and controls',
          icon: Icons.settings_outlined,
          onTap: () => _open(const PlatformSettingsScreen()),
        ),
        ThqCommandCard(
          title: 'Audit Log',
          subtitle: 'Platform security and configuration changes',
          icon: Icons.history_outlined,
          onTap: () => _open(const PlatformAuditScreen()),
        ),
        ThqCommandCard(
          title: 'Transaction Control',
          subtitle: 'Cross-business sales, purchases and expenses',
          icon: Icons.manage_search_outlined,
          onTap: () => _open(const TransactionControlScreen()),
        ),
        ThqCommandCard(
          title: 'Invoice Templates',
          subtitle: 'A4 and 80mm GST invoice designs',
          icon: Icons.receipt_long_outlined,
          onTap: () => _open(const InvoiceTemplatesScreen()),
        ),
        ThqCommandCard(
          title: 'Error Logs',
          subtitle: 'Client, POS and backend diagnostics',
          icon: Icons.bug_report_outlined,
          onTap: () => _open(const PlatformErrorLogsScreen()),
        ),
        ThqCommandCard(
          title: 'App Versions',
          subtitle: 'Releases, minimum versions and device status',
          icon: Icons.system_update_alt_outlined,
          onTap: () => _open(const AppVersionsScreen()),
        ),
        ThqCommandCard(
          title: 'Support',
          subtitle: 'Business tickets and diagnostics',
          icon: Icons.support_agent_outlined,
          onTap: () => _open(const PlatformSupportScreen()),
        ),
      ],
    );
  }

  Widget _securityCard() {
    return const ThqCard(
      padding: EdgeInsets.all(ThqTokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.security_outlined, size: ThqTokens.iconLarge),
          SizedBox(width: ThqTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Security model',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: ThqTokens.space4),
                Text(
                  'Subscription entitlement → tenant module enabled → user permission. Privileged actions remain protected by backend RPCs.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminBrand extends StatelessWidget {
  const _AdminBrand();

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: ThqTokens.controlStandard,
      height: ThqTokens.controlStandard,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(ThqTokens.radiusMedium),
      ),
      child: Text(
        'T',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 100) {
          return Center(child: badge);
        }
        return Row(
          children: [
            badge,
            const SizedBox(width: ThqTokens.space10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'THQ ERP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Platform Admin',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AdminFooter extends StatelessWidget {
  const _AdminFooter({
    required this.now,
    required this.collapsed,
    required this.onLogout,
  });

  final DateTime now;
  final bool collapsed;
  final VoidCallback onLogout;

  String get _time {
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          Tooltip(
            message: 'Sign Out',
            child: IconButton(
              onPressed: onLogout,
              icon: const Icon(Icons.logout),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        ListTile(
          dense: true,
          minTileHeight: ThqTokens.controlStandard,
          leading: const Icon(Icons.logout, size: ThqTokens.iconMedium),
          title: const Text('Sign Out'),
          onTap: onLogout,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThqTokens.space12,
            0,
            ThqTokens.space12,
            ThqTokens.space10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'v${ThqReleaseContract.appVersion} • B${ThqReleaseContract.buildNumber}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(_time, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
