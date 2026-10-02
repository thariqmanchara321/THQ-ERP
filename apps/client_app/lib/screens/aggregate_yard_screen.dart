import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import 'aggregate_freight_screen.dart';
import 'aggregate_loads_screen.dart';
import 'aggregate_orders_screen.dart';
import 'aggregate_vehicles_screen.dart';
import 'customers_screen.dart';
import 'inventory_products_screen.dart';
import 'reports_screen.dart';
import 'suppliers_screen.dart';
import 'transport_logistics_hub_screen.dart';

/// Industry-specific front door for aggregate / bulk-material businesses.
///
/// Financial and stock figures come from THQ's authoritative ledgers/balances.
/// Load Tickets contribute operational tracking only.
class AggregateYardScreen extends StatefulWidget {
  final ClientSession session;

  const AggregateYardScreen({super.key, required this.session});

  @override
  State<AggregateYardScreen> createState() => _AggregateYardScreenState();
}

class _AggregateYardScreenState extends State<AggregateYardScreen> {
  final AggregateYardService _service = AggregateYardService();

  Map<String, dynamic> _dashboard = const {};
  bool _dashboardLoading = true;
  String? _dashboardError;

  ClientSession get session => widget.session;

  bool get _hasTransport =>
      session.hasModule('vehicle_logistics') ||
      session.hasModule('logistics_operations') ||
      session.hasModule('transport_service');

  String? get _locationId => LocationScopeService.selectedLocationId.value;

  List<Map<String, dynamic>> _rows(String key) =>
      (_dashboard[key] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  double _number(dynamic value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  int _integer(dynamic value) =>
      (value as num?)?.toInt() ?? int.tryParse(value?.toString() ?? '') ?? 0;

  String _qty(dynamic value, {int decimals = 2}) {
    final number = _number(value);
    if ((number - number.roundToDouble()).abs() < 0.000001) {
      return number.toStringAsFixed(0);
    }
    return number.toStringAsFixed(decimals);
  }

  String _money(dynamic value) {
    final amount = _number(value);
    if (session.currencyCode == 'INR') {
      return '₹${amount.toStringAsFixed(2)}';
    }
    return '${session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _dashboardLoading = true;
        _dashboardError = null;
      });
    }

    try {
      final result = await _service.dashboard(
        tenantId: session.business.id,
        locationId: _locationId,
        day: DateTime.now(),
      );
      if (!mounted) return;
      setState(() => _dashboard = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _dashboardError = error.toString());
    } finally {
      if (mounted) setState(() => _dashboardLoading = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = session.device;
    final locationName = device == null || device.locationName.isEmpty
        ? 'Current yard / store'
        : device.locationName;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final operationWidth = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 20) / 3;
        final metricWidth = compact
            ? constraints.maxWidth
            : constraints.maxWidth < 1250
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 20) / 3;
        final panelWidth = compact
            ? constraints.maxWidth
            : (constraints.maxWidth - 10) / 2;

        final receivablesVisible = _dashboard['receivables_visible'] == true;

        return RefreshIndicator(
          onRefresh: _loadDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroCard(
                  businessName: session.business.name,
                  locationName: locationName,
                  onRefresh: _dashboardLoading ? null : _loadDashboard,
                ),
                if (_dashboardLoading) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_dashboardError != null) ...[
                  const SizedBox(height: 8),
                  _ErrorBanner(
                    message: _dashboardError!,
                    onRetry: _loadDashboard,
                  ),
                ],
                const SizedBox(height: 14),
                _SectionTitle(
                  title: 'Today at the yard',
                  subtitle:
                      'Operational loads plus authoritative THQ stock and receivables.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MetricCard(
                      width: metricWidth,
                      icon: Icons.south_west_rounded,
                      label: 'Today In',
                      value: '${_qty(_dashboard['today_in_cft'])} CFT',
                      helper:
                          '${_integer(_dashboard['today_in_loads'])} received loads',
                    ),
                    _MetricCard(
                      width: metricWidth,
                      icon: Icons.north_east_rounded,
                      label: 'Today Out',
                      value: '${_qty(_dashboard['today_out_cft'])} CFT',
                      helper:
                          '${_integer(_dashboard['today_out_loads'])} dispatched loads',
                    ),
                    _MetricCard(
                      width: metricWidth,
                      icon: Icons.inventory_2_outlined,
                      label: 'Available Stock',
                      value: '${_qty(_dashboard['stock_available_cft'])} CFT',
                      helper:
                          'On hand ${_qty(_dashboard['stock_on_hand_cft'])} CFT',
                    ),
                    _MetricCard(
                      width: metricWidth,
                      icon: Icons.local_shipping_outlined,
                      label: 'Trucks On Road',
                      value: '${_integer(_dashboard['trucks_on_road'])}',
                      helper:
                          '${_integer(_dashboard['active_trucks'])} active trucks',
                    ),
                    _MetricCard(
                      width: metricWidth,
                      icon: Icons.schedule_send_outlined,
                      label: 'Pending Delivery',
                      value: '${_qty(_dashboard['pending_delivery_cft'])} CFT',
                      helper:
                          '${_integer(_dashboard['pending_delivery_loads'])} open loads',
                    ),
                    _MetricCard(
                      width: metricWidth,
                      icon: Icons.assignment_outlined,
                      label: 'Open Orders',
                      value: '${_integer(_dashboard['open_order_count'])}',
                      helper:
                          '${_qty(_dashboard['open_order_cft'])} CFT remaining',
                    ),
                    _MetricCard(
                      width: metricWidth,
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Receivable',
                      value: receivablesVisible
                          ? _money(_dashboard['receivables'])
                          : 'Restricted',
                      helper: receivablesVisible
                          ? 'Authoritative customer outstanding'
                          : 'Requires sales/customer/accounting access',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionTitle(
                  title: 'Yard operations',
                  subtitle:
                      'Start with the truck/load, then let THQ post the commercial transaction.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ActionCard(
                      width: operationWidth,
                      icon: Icons.move_to_inbox_outlined,
                      title: 'Material Inward',
                      subtitle: 'Truck load → authoritative THQ Purchase',
                      onTap: () => _open(
                        AggregateLoadsScreen(
                          session: session,
                          initialCreateDirection: 'inbound',
                        ),
                      ),
                    ),
                    _ActionCard(
                      width: operationWidth,
                      icon: Icons.outbox_outlined,
                      title: 'Material Dispatch',
                      subtitle: 'Truck load → authoritative THQ Sale',
                      onTap: () => _open(
                        AggregateLoadsScreen(
                          session: session,
                          initialCreateDirection: 'outbound',
                        ),
                      ),
                    ),
                    _ActionCard(
                      width: operationWidth,
                      icon: Icons.receipt_long_outlined,
                      title: 'Load Register',
                      subtitle: 'Loads, CFT measurement, links and status',
                      onTap: () =>
                          _open(AggregateLoadsScreen(session: session)),
                    ),
                    _ActionCard(
                      width: operationWidth,
                      icon: Icons.assignment_outlined,
                      title: 'Customer Orders',
                      subtitle:
                          'Multi-load orders with delivered / remaining tracking',
                      onTap: () =>
                          _open(AggregateOrdersScreen(session: session)),
                    ),
                    _ActionCard(
                      width: operationWidth,
                      icon: Icons.inventory_2_outlined,
                      title: 'Yard Stock',
                      subtitle: 'Open authoritative THQ inventory',
                      onTap: () =>
                          _open(InventoryProductsScreen(session: session)),
                    ),
                    _ActionCard(
                      width: operationWidth,
                      icon: Icons.local_shipping_outlined,
                      title: 'Truck Setup',
                      subtitle:
                          'Dimensions, CFT capacity, ownership and freight',
                      onTap: () =>
                          _open(AggregateVehiclesScreen(session: session)),
                    ),
                    _ActionCard(
                      width: operationWidth,
                      icon: Icons.payments_outlined,
                      title: 'Freight & Profit',
                      subtitle:
                          'Transporter settlement and per-load contribution',
                      onTap: () =>
                          _open(AggregateFreightScreen(session: session)),
                    ),
                    _ActionCard(
                      width: operationWidth,
                      icon: Icons.route_outlined,
                      title: 'Trips & Vehicles',
                      subtitle: _hasTransport
                          ? 'Open existing THQ Transport & Logistics'
                          : 'Enable Vehicle Logistics for advanced tracking',
                      enabled: _hasTransport,
                      onTap: () =>
                          _open(TransportLogisticsHubScreen(session: session)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [
                    SizedBox(
                      width: panelWidth,
                      child: _StockPanel(
                        rows: _rows('stock_by_material'),
                        quantityText: _qty,
                      ),
                    ),
                    SizedBox(
                      width: panelWidth,
                      child: _ActiveLoadsPanel(
                        rows: _rows('active_loads'),
                        quantityText: _qty,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Masters & reports',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SmallAction(
                              icon: Icons.groups_outlined,
                              label: 'Customers',
                              onTap: () =>
                                  _open(CustomersScreen(session: session)),
                            ),
                            _SmallAction(
                              icon: Icons.factory_outlined,
                              label: 'Suppliers / Quarries',
                              onTap: () =>
                                  _open(SuppliersScreen(session: session)),
                            ),
                            _SmallAction(
                              icon: Icons.insights_outlined,
                              label: 'Reports',
                              onTap: () =>
                                  _open(ReportsScreen(session: session)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: .45,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Dashboard stock and receivables come from THQ '
                            'authoritative balances. Load Tickets remain '
                            'operational tracking only. CFT summary cards never '
                            'mix tonnes, pieces or other units into the same total.',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
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
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String businessName;
  final String locationName;
  final VoidCallback? onRefresh;

  const _HeroCard({
    required this.businessName,
    required this.locationName,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.landscape_outlined,
              color: scheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MATERIAL YARD',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: .80),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'THQ ERP CORE',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String helper;

  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  helper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockPanel extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String Function(dynamic value, {int decimals}) quantityText;

  const _StockPanel({required this.rows, required this.quantityText});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleRows = rows.take(8).toList(growable: false);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warehouse_outlined, size: 18),
                const SizedBox(width: 7),
                Text(
                  'Stock by material',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Authoritative location stock. Each material keeps its own base unit.',
              style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 9),
            if (visibleRows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No stock balance to display yet.')),
              )
            else
              ...visibleRows.map((row) {
                final variant = row['variant_name']?.toString().trim() ?? '';
                final product = row['product_name']?.toString() ?? '';
                final name =
                    variant.isEmpty ||
                        variant.toLowerCase() == 'default' ||
                        variant.toLowerCase() == 'standard'
                    ? product
                    : '$product • $variant';
                final unit = row['unit_code']?.toString() ?? '';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${quantityText(row['available'])} $unit',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'On hand ${quantityText(row['on_hand'])}',
                            style: TextStyle(
                              fontSize: 8.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            if (rows.length > visibleRows.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '+ ${rows.length - visibleRows.length} more materials',
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveLoadsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String Function(dynamic value, {int decimals}) quantityText;

  const _ActiveLoadsPanel({required this.rows, required this.quantityText});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleRows = rows.take(8).toList(growable: false);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_outlined, size: 18),
                const SizedBox(width: 7),
                Text(
                  'Active loads',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Loading, dispatched, in-transit and arrived trucks.',
              style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 9),
            if (visibleRows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('No active truck loads right now.')),
              )
            else
              ...visibleRows.map((row) {
                final direction = row['direction']?.toString() ?? '';
                final isInbound = direction == 'inbound';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(
                        isInbound
                            ? Icons.south_west_rounded
                            : Icons.north_east_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['load_number'] ?? ''} • '
                              '${row['product_name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${row['vehicle_registration'] ?? 'No truck'}'
                              ' • ${row['driver_name'] ?? 'No driver'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 8.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${quantityText(row['quantity'])} '
                            '${row['unit_code'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            (row['status'] ?? '').toString().replaceAll(
                              '_',
                              ' ',
                            ),
                            style: TextStyle(
                              fontSize: 8.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: scheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      Text(
        subtitle,
        style: TextStyle(
          fontSize: 10.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  const _ActionCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(
                      alpha: enabled ? .10 : .04,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: enabled
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: .45),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: enabled
                              ? null
                              : scheme.onSurfaceVariant.withValues(alpha: .55),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.25,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 16),
    label: Text(label),
  );
}
