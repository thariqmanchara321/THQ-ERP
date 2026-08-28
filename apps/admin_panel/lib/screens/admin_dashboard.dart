import 'package:flutter/material.dart';

import '../services/admin_auth_service.dart';
import '../services/platform_config_service.dart';
import 'app_versions_screen.dart';
import 'businesses_screen.dart';
import 'login_screen.dart';
import 'modules_screen.dart';
import 'platform_admins_screen.dart';
import 'platform_audit_screen.dart';
import 'platform_settings_screen.dart';
import 'platform_support_screen.dart';
import 'subscription_plans_screen.dart';
import 'templates_screen.dart';
import 'invoice_templates_screen.dart';
import 'platform_error_logs_screen.dart';
import 'ui_design_studio_screen.dart';
import 'transaction_control_screen.dart';
import 'menu_builder_screen.dart';
import '../ui/v43_theme.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late Future<Map<String, dynamic>> _overviewFuture;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _overviewFuture = PlatformConfigService().getOverview();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _overviewFuture = PlatformConfigService().getOverview();
    });
    try {
      await _overviewFuture;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('THQ Platform refreshed. Saved Admin changes are immediately available to Client/POS after their Refresh action.')),
        );
      }
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

  Future<void> _logout(BuildContext context) async {
    await AdminAuthService().signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final auth = AdminAuthService();
    return Scaffold(
      backgroundColor: UiDesignProfile.fallback('client').background,
      appBar: AppBar(
        title: const Text(
          'THQ Platform',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: FutureBuilder<String>(
                future: auth.currentUsername(),
                builder: (_, snapshot) => Text(
                  snapshot.data == null || snapshot.data!.isEmpty
                      ? 'Platform Admin'
                      : '@${snapshot.data}',
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh Platform',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Platform Control Centre',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Businesses, modules, design systems, subscriptions, security and global settings.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            FutureBuilder<Map<String, dynamic>>(
              future: _overviewFuture,
              builder: (context, snapshot) {
                final d = snapshot.data ?? const <String, dynamic>{};
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Metric('Businesses', d['businesses']?.toString() ?? '—'),
                    _Metric(
                      'Active',
                      d['active_businesses']?.toString() ?? '—',
                    ),
                    _Metric(
                      'Subscriptions',
                      d['active_subscriptions']?.toString() ?? '—',
                    ),
                    _Metric('Trials', d['trials']?.toString() ?? '—'),
                    _Metric('Modules', d['modules']?.toString() ?? '—'),
                    _Metric('Templates', d['templates']?.toString() ?? '—'),
                  ],
                );
              },
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 18,
              runSpacing: 18,
              children: [
                DashboardCard(
                  title: 'Businesses',
                  subtitle: 'Tenants, users, roles & modules',
                  icon: Icons.store_outlined,
                  onTap: () => _open(context, const BusinessesScreen()),
                ),
                DashboardCard(
                  title: 'Modules',
                  subtitle: 'Core, POS & industry features',
                  icon: Icons.extension_outlined,
                  onTap: () => _open(context, const ModulesScreen()),
                ),
                DashboardCard(
                  title: 'Menu Builder',
                  subtitle: 'Nested Client/POS menus & names',
                  icon: Icons.account_tree_outlined,
                  onTap: () => _open(context, const MenuBuilderScreen()),
                ),
                DashboardCard(
                  title: 'Templates',
                  subtitle: 'Reusable business presets',
                  icon: Icons.dashboard_customize_outlined,
                  onTap: () => _open(context, const TemplatesScreen()),
                ),
                DashboardCard(
                  title: 'Design Studio',
                  subtitle: 'Client/POS themes, colors & layouts',
                  icon: Icons.palette_outlined,
                  onTap: () => _open(context, const UiDesignStudioScreen()),
                ),
                DashboardCard(
                  title: 'Subscriptions',
                  subtitle: 'Plans, entitlements & limits',
                  icon: Icons.payments_outlined,
                  onTap: () => _open(context, const SubscriptionPlansScreen()),
                ),
                DashboardCard(
                  title: 'Platform Admins',
                  subtitle: 'Separated admin responsibilities',
                  icon: Icons.admin_panel_settings_outlined,
                  onTap: () => _open(context, const PlatformAdminsScreen()),
                ),
                DashboardCard(
                  title: 'Settings',
                  subtitle: 'Global platform defaults',
                  icon: Icons.settings_outlined,
                  onTap: () => _open(context, const PlatformSettingsScreen()),
                ),
                DashboardCard(
                  title: 'Audit Log',
                  subtitle: 'Platform security changes',
                  icon: Icons.history_outlined,
                  onTap: () => _open(context, const PlatformAuditScreen()),
                ),
                DashboardCard(
                  title: 'Transaction Control',
                  subtitle: 'Cross-business sales, purchases & expenses',
                  icon: Icons.manage_search_outlined,
                  onTap: () => _open(context, const TransactionControlScreen()),
                ),
                DashboardCard(
                  title: 'Invoice Templates',
                  subtitle: 'A4 & 80mm GST designs',
                  icon: Icons.receipt_long_outlined,
                  onTap: () => _open(context, const InvoiceTemplatesScreen()),
                ),
                DashboardCard(
                  title: 'Error Logs',
                  subtitle: 'Client, POS & backend issues',
                  icon: Icons.bug_report_outlined,
                  onTap: () => _open(context, const PlatformErrorLogsScreen()),
                ),
                DashboardCard(
                  title: 'App Versions',
                  subtitle: 'Releases, minimum versions & device status',
                  icon: Icons.system_update_alt_outlined,
                  onTap: () => _open(context, const AppVersionsScreen()),
                ),
                DashboardCard(
                  title: 'Support',
                  subtitle: 'Business tickets & diagnostics',
                  icon: Icons.support_agent_outlined,
                  onTap: () => _open(context, const PlatformSupportScreen()),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.security_outlined, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Security model',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Subscription entitlement → tenant module enabled → user permission. Flutter only uses the Supabase publishable key; privileged actions are protected by backend RPCs.',
                            style: TextStyle(color: Colors.grey.shade700),
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
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final p = UiDesignProfile.fallback('client');
    return Container(
      width: 162,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(p.radius),
        border: Border.all(color: p.border),
        boxShadow: [
          BoxShadow(
            color: p.primary.withValues(alpha: .04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -.4,
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  const DashboardCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = UiDesignProfile.fallback('client');
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(p.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(p.radius),
        child: Container(
          width: 286,
          height: 160,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(p.radius),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: p.primary.withValues(alpha: .04),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: p.primary),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
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
      ),
    );
  }
}
