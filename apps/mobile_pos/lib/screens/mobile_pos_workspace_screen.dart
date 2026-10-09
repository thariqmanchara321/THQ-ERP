import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:thq_logistics/thq_logistics.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';
import '../services/device_installation_service.dart';
import '../services/mobile_pos_auth_service.dart';
import '../services/mobile_pos_local_store.dart';
import '../services/mobile_pos_sync_service.dart';
import 'mobile_cashier_shift_screen.dart';
import 'mobile_party_payments_screen.dart';
import 'mobile_pos_entry_screen.dart';
import 'mobile_pos_expense_screen.dart';
import 'mobile_pos_home_screen.dart';
import 'mobile_pos_purchase_screen.dart';
import 'mobile_pos_report_screen.dart';
import 'offline_queue_screen.dart';

/// Production shell around the proven Mobile POS sale workspace.
///
/// Transaction posting remains owned by the existing v5.2 sale sync, purchase,
/// expense, restaurant and logistics services. This screen only orchestrates
/// navigation, local queue visibility and operational shortcuts.
class MobilePosWorkspaceScreen extends StatefulWidget {
  final PosSession session;

  const MobilePosWorkspaceScreen({super.key, required this.session});

  @override
  State<MobilePosWorkspaceScreen> createState() =>
      _MobilePosWorkspaceScreenState();
}

class _MobilePosWorkspaceScreenState extends State<MobilePosWorkspaceScreen> {
  final MobilePosLocalStore _local = MobilePosLocalStore.instance;
  final MobilePosSyncService _sync = MobilePosSyncService();

  int _index = 0;
  int _refreshKey = 0;
  bool _syncing = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _refreshSummary(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refreshSummary() {
    if (mounted) setState(() => _refreshKey++);
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await _sync.sync(widget.session, includeConflicts: true);
      if (!mounted) return;
      _refreshSummary();
      final text = result.conflicts > 0
          ? '${result.synced} synced â€¢ ${result.conflicts} conflict(s) need review'
          : result.pending > 0
          ? '${result.synced} synced â€¢ ${result.pending} still waiting'
          : '${result.synced} synced â€¢ queue checked';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sync unavailable: $error')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<T?> _push<T>(Widget page) async {
    final result = await Navigator.of(context)
        .push<T>(MaterialPageRoute(builder: (_) => page));
    if (mounted) _refreshSummary();
    return result;
  }

  void _goSell([String? notice]) {
    setState(() => _index = 0);
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(notice)));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      MobilePosHomeScreen(session: widget.session),
      _OrdersWorkspace(
        key: ValueKey('orders-$_refreshKey'),
        session: widget.session,
        local: _local,
        syncing: _syncing,
        onSync: _syncNow,
        onOpenQueue: () => _push(OfflineQueueScreen(session: widget.session)),
        onOpenReport: () =>
            _push(MobilePosReportScreen(session: widget.session)),
      ),
      _OperationsWorkspace(
        session: widget.session,
        onPurchase: () => _push(
          MobilePosPurchaseScreen(session: widget.session, offlineMode: false),
        ),
        onExpense: () => _push(
          MobilePosExpenseScreen(session: widget.session, offlineMode: false),
        ),
        onCashier: () =>
            _push(MobileCashierShiftScreen(session: widget.session)),
        onPartyPayments: () =>
            _push(MobilePartyPaymentsScreen(session: widget.session)),
        onLogistics: () => _push(
          LogisticsOperationsWorkspace(
            tenantId: widget.session.tenantId,
            locationId: widget.session.locationId,
          ),
        ),
        onVehicleLogistics: () => _push(
          VehicleLogisticsReportWorkspace(
            tenantId: widget.session.tenantId,
            locationId: widget.session.locationId,
          ),
        ),
        onQueue: () => _push(OfflineQueueScreen(session: widget.session)),
        onRestaurant: () => _goSell(
          'Restaurant / KOT continues inside Sell so the existing billing and GST route stay unchanged.',
        ),
      ),
      _ReportsWorkspace(
        key: ValueKey('reports-$_refreshKey'),
        session: widget.session,
        local: _local,
        onOpenReport: () =>
            _push(MobilePosReportScreen(session: widget.session)),
        onOpenQueue: () => _push(OfflineQueueScreen(session: widget.session)),
      ),
      _MoreWorkspace(
        session: widget.session,
        syncing: _syncing,
        onSync: _syncNow,
        onOpenQueue: () => _push(OfflineQueueScreen(session: widget.session)),
        onOpenReport: () =>
            _push(MobilePosReportScreen(session: widget.session)),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _WorkspaceNavigation(
        index: _index,
        onChanged: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _WorkspaceNavigation extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _WorkspaceNavigation({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: onChanged,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon: Icon(Icons.point_of_sale_rounded),
                label: 'Sell',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Orders',
              ),
              NavigationDestination(
                icon: Icon(Icons.widgets_outlined),
                selectedIcon: Icon(Icons.widgets_rounded),
                label: 'Operations',
              ),
              NavigationDestination(
                icon: Icon(Icons.analytics_outlined),
                selectedIcon: Icon(Icons.analytics_rounded),
                label: 'Reports',
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
}

class _WorkspacePage extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  const _WorkspacePage({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _OrdersWorkspace extends StatefulWidget {
  final PosSession session;
  final MobilePosLocalStore local;
  final bool syncing;
  final Future<void> Function() onSync;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenReport;

  const _OrdersWorkspace({
    super.key,
    required this.session,
    required this.local,
    required this.syncing,
    required this.onSync,
    required this.onOpenQueue,
    required this.onOpenReport,
  });

  @override
  State<_OrdersWorkspace> createState() => _OrdersWorkspaceState();
}

class _OrdersWorkspaceState extends State<_OrdersWorkspace> {
  late Future<List<LocalInvoice>> _future;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<LocalInvoice>> _load() => widget.local.queue(
    widget.session.tenantId,
    widget.session.deviceId,
    limit: 80,
  );

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LocalInvoice>>(
      future: _future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <LocalInvoice>[];
        final pending = rows
            .where(
              (row) =>
                  row.status == 'pending' ||
                  row.status == 'error' ||
                  row.status == 'syncing',
            )
            .length;
        final conflicts = rows.where((row) => row.status == 'conflict').length;
        final synced = rows.where((row) => row.status == 'synced').length;
        final visibleRows = rows
            .where((row) {
              switch (_filter) {
                case 'waiting':
                  return row.status == 'pending' ||
                      row.status == 'error' ||
                      row.status == 'syncing';
                case 'conflict':
                  return row.status == 'conflict';
                case 'synced':
                  return row.status == 'synced';
                default:
                  return true;
              }
            })
            .toList(growable: false);

        return _WorkspacePage(
          eyebrow: 'Mobile POS',
          title: 'Orders',
          subtitle:
              'Local invoice queue, sync state and recent terminal sales.',
          icon: Icons.receipt_long_rounded,
          trailing: IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: 'Waiting',
                    value: '$pending',
                    icon: Icons.schedule_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: 'Conflicts',
                    value: '$conflicts',
                    icon: Icons.warning_amber_rounded,
                    attention: conflicts > 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: 'Synced',
                    value: '$synced',
                    icon: Icons.cloud_done_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.syncing ? null : widget.onSync,
                    icon: widget.syncing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(widget.syncing ? 'Syncingâ€¦' : 'Sync now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenQueue,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('Sync center'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'waiting', label: Text('Waiting')),
                  ButtonSegment(value: 'conflict', label: Text('Conflicts')),
                  ButtonSegment(value: 'synced', label: Text('Synced')),
                ],
                selected: <String>{_filter},
                onSelectionChanged: (value) =>
                    setState(() => _filter = value.first),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 16),
            _SectionHeading(
              title: 'Recent terminal orders',
              action: TextButton(
                onPressed: widget.onOpenReport,
                child: const Text('Daily report'),
              ),
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState != ConnectionState.done)
              const _LoadingCard()
            else if (snapshot.hasError)
              _ErrorCard(message: snapshot.error.toString())
            else if (visibleRows.isEmpty)
              const _EmptyCard(
                icon: Icons.receipt_long_outlined,
                title: 'No local orders yet',
                message: 'New Mobile POS sales will appear here immediately.',
              )
            else
              ...visibleRows
                  .take(20)
                  .map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OrderCard(
                        invoice: row,
                        currencyCode: widget.session.currencyCode,
                      ),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _OperationsWorkspace extends StatelessWidget {
  final PosSession session;
  final VoidCallback onPurchase;
  final VoidCallback onExpense;
  final VoidCallback onCashier;
  final VoidCallback onPartyPayments;
  final VoidCallback onLogistics;
  final VoidCallback onVehicleLogistics;
  final VoidCallback onQueue;
  final VoidCallback onRestaurant;

  const _OperationsWorkspace({
    required this.session,
    required this.onPurchase,
    required this.onExpense,
    required this.onCashier,
    required this.onPartyPayments,
    required this.onLogistics,
    required this.onVehicleLogistics,
    required this.onQueue,
    required this.onRestaurant,
  });

  bool _allowed(String module) =>
      session.allowedModules.isEmpty || session.hasDeviceModule(module);

  @override
  Widget build(BuildContext context) {
    return _WorkspacePage(
      eyebrow: 'Mobile POS',
      title: 'Operations',
      subtitle: 'Fast operational actions for this terminal and store.',
      icon: Icons.widgets_rounded,
      children: [
        _OperationCard(
          icon: Icons.shopping_bag_outlined,
          title: 'Purchase',
          subtitle: _allowed('purchases')
              ? 'Create an authoritative online purchase.'
              : 'Purchases is not enabled for this terminal.',
          onTap: _allowed('purchases') ? onPurchase : null,
        ),
        const SizedBox(height: 8),
        _OperationCard(
          icon: Icons.receipt_outlined,
          title: 'Expense',
          subtitle: _allowed('expenses')
              ? 'Record an expense with accounting checks.'
              : 'Expenses is not enabled for this terminal.',
          onTap: _allowed('expenses') ? onExpense : null,
        ),
        const SizedBox(height: 8),
        _OperationCard(
          icon: Icons.badge_outlined,
          title: 'Cashier shift',
          subtitle: 'Open, review and close the active terminal cash shift.',
          onTap: onCashier,
        ),
        const SizedBox(height: 8),
        _OperationCard(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Party payments',
          subtitle: 'Receive customers, pay suppliers, or close balances with Discount / Write-off.',
          onTap: onPartyPayments,
        ),
        const SizedBox(height: 8),
        if (session.restaurantEnabled) ...[
          _OperationCard(
            icon: Icons.restaurant_menu_rounded,
            title: 'Restaurant / KOT',
            subtitle: 'Use the proven restaurant flow inside Sell; billing authority stays unchanged.',
            onTap: onRestaurant,
          ),
          const SizedBox(height: 8),
        ],
        _OperationCard(
          icon: Icons.route_outlined,
          title: 'Logistics operations',
          subtitle: 'Trips, movement and operational logistics workflow.',
          onTap: onLogistics,
        ),
        const SizedBox(height: 8),
        _OperationCard(
          icon: Icons.local_shipping_outlined,
          title: 'Vehicle logistics',
          subtitle: 'Vehicle stock movement tracking and reporting.',
          onTap: onVehicleLogistics,
        ),
        const SizedBox(height: 8),
        _OperationCard(
          icon: Icons.sync_alt_rounded,
          title: 'Offline & sync center',
          subtitle: 'Review pending, failed or conflicting local invoices.',
          onTap: onQueue,
        ),
      ],
    );
  }
}

class _ReportsWorkspace extends StatefulWidget {
  final PosSession session;
  final MobilePosLocalStore local;
  final VoidCallback onOpenReport;
  final VoidCallback onOpenQueue;

  const _ReportsWorkspace({
    super.key,
    required this.session,
    required this.local,
    required this.onOpenReport,
    required this.onOpenQueue,
  });

  @override
  State<_ReportsWorkspace> createState() => _ReportsWorkspaceState();
}

class _ReportsWorkspaceState extends State<_ReportsWorkspace> {
  late Future<List<LocalInvoice>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.local.queue(
      widget.session.tenantId,
      widget.session.deviceId,
      limit: 1000,
    );
  }

  bool _today(LocalInvoice row) {
    final now = DateTime.now();
    final value = row.createdAt.toLocal();
    return now.year == value.year &&
        now.month == value.month &&
        now.day == value.day;
  }

  double _amount(LocalInvoice row) {
    final raw = row.payload['total'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String _money(double value) =>
      '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LocalInvoice>>(
      future: _future,
      builder: (context, snapshot) {
        final today = (snapshot.data ?? const <LocalInvoice>[])
            .where(_today)
            .toList(growable: false);
        final total = today.fold<double>(0, (sum, row) => sum + _amount(row));
        final waiting = today
            .where((row) => row.status != 'synced' && row.status != 'cancelled')
            .length;

        return _WorkspacePage(
          eyebrow: 'Mobile POS',
          title: 'Reports',
          subtitle:
              'Terminal-level visibility with local fallback when offline.',
          icon: Icons.analytics_rounded,
          children: [
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: 'Local invoices today',
                    value: '${today.length}',
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: 'Local total',
                    value: _money(total),
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MetricTile(
              label: 'Not yet synchronized today',
              value: '$waiting',
              icon: Icons.cloud_off_outlined,
              attention: waiting > 0,
            ),
            const SizedBox(height: 14),
            _OperationCard(
              icon: Icons.bar_chart_rounded,
              title: 'Terminal daily report',
              subtitle: 'Server summary, invoice drill-down, payments, purchases and expenses.',
              onTap: widget.onOpenReport,
            ),
            const SizedBox(height: 8),
            _OperationCard(
              icon: Icons.sync_alt_rounded,
              title: 'Sync diagnostics',
              subtitle: 'Inspect the local queue before relying on final server totals.',
              onTap: widget.onOpenQueue,
            ),
          ],
        );
      },
    );
  }
}

class _MoreWorkspace extends StatelessWidget {
  final PosSession session;
  final bool syncing;
  final Future<void> Function() onSync;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenReport;

  const _MoreWorkspace({
    required this.session,
    required this.syncing,
    required this.onSync,
    required this.onOpenQueue,
    required this.onOpenReport,
  });

  Future<void> _signOut(BuildContext context) async {
    await MobilePosAuthService().signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MobilePosEntryScreen()),
      (_) => false,
    );
  }

  Future<void> _deactivate(BuildContext context) async {
    final confirmed = await showThqDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate this terminal?'),
        content: const Text(
          'This removes the local activation from this phone. It does not delete server transactions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await MobilePosAuthService().signOut();
    await DeviceInstallationService().clearActivation();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MobilePosEntryScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final release = session.release;
    final releaseText =
        release.updateAvailable && release.latestVersion.isNotEmpty
        ? 'Update available: ${release.latestVersion}'
        : 'Release status: ${release.status}';

    return _WorkspacePage(
      eyebrow: 'Terminal',
      title: 'More',
      subtitle: 'Identity, release, sync and secure terminal actions.',
      icon: Icons.more_horiz_rounded,
      children: [
        if (release.updateAvailable) ...[
          ThqMobileReleaseBanner(
            currentVersion: ThqPosMobileReleaseContract.appVersion,
            latestVersion: release.latestVersion,
            notes: release.releaseNotes,
          ),
          const SizedBox(height: 10),
        ],
        _IdentityCard(
          title: session.businessName,
          logoUrl: session.logoUrl,
          rows: [
            ('User', session.username),
            ('Store', '${session.locationName} â€¢ ${session.locationCode}'),
            ('Terminal', '${session.deviceName} â€¢ ${session.deviceCode}'),
            ('Version', ThqPosMobileReleaseContract.versionLabel),
            ('Release', releaseText),
          ],
        ),
        const SizedBox(height: 10),
        _OperationCard(
          icon: Icons.sync_rounded,
          title: syncing ? 'Synchronizingâ€¦' : 'Sync now',
          subtitle: 'Retry the authoritative Mobile POS queue and refresh local stock after successful sync.',
          onTap: syncing ? null : onSync,
        ),
        const SizedBox(height: 8),
        _OperationCard(
          icon: Icons.sync_alt_rounded,
          title: 'Offline & sync center',
          subtitle: 'Inspect queue status, conflicts and local invoices.',
          onTap: onOpenQueue,
        ),
        const SizedBox(height: 8),
        _OperationCard(
          icon: Icons.analytics_outlined,
          title: 'Terminal report',
          subtitle: 'Open the daily terminal report workspace.',
          onTap: onOpenReport,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _signOut(context),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _deactivate(context),
          icon: const Icon(Icons.phonelink_erase_outlined),
          label: const Text('Deactivate this terminal'),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool attention;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = attention ? scheme.errorContainer : scheme.surface;
    final foreground = attention ? scheme.onErrorContainer : scheme.primary;
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: attention
              ? scheme.error.withValues(alpha: 0.18)
              : scheme.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _OperationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: scheme.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: enabled
                      ? scheme.primaryContainer
                      : scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: enabled ? scheme.onPrimaryContainer : scheme.outline,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (enabled) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final LocalInvoice invoice;
  final String currencyCode;

  const _OrderCard({required this.invoice, required this.currencyCode});

  double get _total {
    final raw = invoice.payload['total'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String get _customer =>
      invoice.payload['customer_name']?.toString().trim().isNotEmpty == true
      ? invoice.payload['customer_name'].toString()
      : 'Customer';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = invoice.status.toLowerCase();
    final problem = status == 'conflict' || status == 'error';
    final statusBg = problem
        ? scheme.errorContainer
        : status == 'synced'
        ? Theme.of(context).colorScheme.primaryContainer
        : scheme.primaryContainer;
    final statusFg = problem
        ? scheme.onErrorContainer
        : status == 'synced'
        ? const Color(0xFF16734A)
        : scheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoice.serverResponse?['sale_number']?.toString() ??
                      invoice.localNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: statusFg,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  _customer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                '$currencyCode ${_total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('dd MMM â€¢ hh:mm a')
                .format(invoice.createdAt.toLocal()),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (invoice.conflictMessage.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              invoice.conflictMessage,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.error, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final String title;
  final String? logoUrl;
  final List<(String, String)> rows;

  const _IdentityCard({
    required this.title,
    this.logoUrl,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (logoUrl != null && logoUrl!.trim().isNotEmpty) ...[
                ThqBusinessLogo(
                  logoUrl: logoUrl,
                  size: 38,
                  borderRadius: BorderRadius.circular(10),
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < rows.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    rows[index].$1,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[index].$2,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (index < rows.length - 1) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionHeading({required this.title, this.action});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      ?action,
    ],
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 110,
    child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
  );
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
