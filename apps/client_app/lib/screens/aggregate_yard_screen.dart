import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/material_measurement_engine.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import 'aggregate_direct_supply_screen.dart';
import 'aggregate_freight_screen.dart';
import 'aggregate_loads_screen.dart';
import 'aggregate_orders_screen.dart';
import 'aggregate_vehicles_screen.dart';
import 'customers_screen.dart';
import 'aggregate_yard_stock_screen.dart';
import 'daily_material_rate_board_screen.dart';
import 'driver_master_screen.dart';
import 'material_yard_crusher_report_screen.dart';
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

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  int _integer(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

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

  Future<void> _openWorkspace(String title, Widget page) async {
    await _open(
      Scaffold(
        appBar: AppBar(toolbarHeight: 46, title: Text(title)),
        body: SafeArea(child: page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = session.device;
    final locationName = device == null || device.locationName.isEmpty
        ? 'Current yard / store'
        : device.locationName;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        const horizontalPadding = 28.0; // 14.0 left + 14.0 right
        final usableWidth = (constraints.maxWidth - horizontalPadding).clamp(280.0, 5000.0);
        final kpiColumns = usableWidth >= 1150
            ? 4
            : usableWidth >= 650
                ? 2
                : 1;
        final actionColumns = usableWidth >= 1150
            ? 3
            : usableWidth >= 750
                ? 2
                : 1;
        final kpiWidth = (usableWidth - ((kpiColumns - 1) * gap)) / kpiColumns;
        final actionWidth = (usableWidth - ((actionColumns - 1) * gap)) / actionColumns;
        final receivablesVisible = _dashboard['receivables_visible'] == true;
        final payablesVisible = _dashboard['payables_visible'] == true;
        final isDesktopWide = usableWidth >= 1050;

        return RefreshIndicator(
          onRefresh: _loadDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP COMPACT HEADER
                _CompactTopBar(
                  businessName: session.business.name,
                  locationName: locationName,
                  isLoading: _dashboardLoading,
                  onRefresh: _dashboardLoading ? null : _loadDashboard,
                  onNewInward: () => _open(
                    AggregateLoadsScreen(
                      session: session,
                      initialDirection: 'inbound',
                    ),
                  ),
                  onNewOutward: () => _open(
                    AggregateLoadsScreen(
                      session: session,
                      initialDirection: 'outbound',
                    ),
                  ),
                  onRateBoard: () => _open(
                    DailyMaterialRateBoardScreen(session: session),
                  ),
                ),

                if (_dashboardLoading) ...[
                  const SizedBox(height: 4),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_dashboardError != null) ...[
                  const SizedBox(height: 8),
                  _ErrorBanner(
                    message: _dashboardError!,
                    onRetry: _loadDashboard,
                  ),
                ],

                const SizedBox(height: 10),

                // 2. IMPORTANT OPERATIONAL KPI ROW (8 authoritative metrics)
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    // 1. Today's Inward Loads
                    _CompactKpiCard(
                      width: kpiWidth,
                      icon: Icons.south_west_rounded,
                      iconColor: const Color(0xFF00875A),
                      label: "Today's Inward Loads",
                      value: '${_integer(_dashboard['today_in_loads'])} loads',
                      secondary: '${MaterialMeasurementEngine.formatQuantity(_dashboard['today_in_cft'] ?? 0, 'CFT')} received',
                    ),
                    // 2. Today's Outward Loads
                    _CompactKpiCard(
                      width: kpiWidth,
                      icon: Icons.north_east_rounded,
                      iconColor: const Color(0xFF635BFF),
                      label: "Today's Outward Loads",
                      value: '${_integer(_dashboard['today_out_loads'])} loads',
                      secondary: '${MaterialMeasurementEngine.formatQuantity(_dashboard['today_out_cft'] ?? 0, 'CFT')} dispatched',
                    ),
                    // 3. Today's Purchase Value
                    _CompactKpiCard(
                      width: kpiWidth,
                      icon: Icons.shopping_cart_checkout_outlined,
                      iconColor: const Color(0xFF0D9488),
                      label: "Today's Purchase Value",
                      value: _money(_dashboard['today_purchase_value'] ?? 0),
                      secondary: '${_integer(_dashboard['today_in_loads'])} quarry bills',
                    ),
                    // 4. Today's Sales Value
                    _CompactKpiCard(
                      width: kpiWidth,
                      icon: Icons.point_of_sale_outlined,
                      iconColor: const Color(0xFF7C3AED),
                      label: "Today's Sales Value",
                      value: _money(_dashboard['today_sales_value'] ?? 0),
                      secondary: '${_integer(_dashboard['today_out_loads'])} sales orders',
                    ),
                    // 5. Available Bulk Stock
                    _CompactKpiCard(
                      width: kpiWidth,
                      icon: Icons.inventory_2_outlined,
                      iconColor: const Color(0xFF0052CC),
                      label: 'Available Bulk Stock',
                      value: MaterialMeasurementEngine.formatQuantity(_dashboard['stock_available_cft'] ?? 0, 'CFT'),
                      secondary: 'On hand ${MaterialMeasurementEngine.formatQuantity(_dashboard['stock_on_hand_cft'] ?? 0, 'CFT')}',
                    ),
                    // 6. Customer Receivables
                    _CompactKpiCard(
                      width: kpiWidth,
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: const Color(0xFFD97706),
                      label: 'Customer Receivables',
                      value: receivablesVisible
                          ? _money(_dashboard['receivables'])
                          : 'Restricted',
                      secondary: receivablesVisible
                          ? 'Ledger outstanding'
                          : 'Finance permission needed',
                    ),
                    // 7. Supplier Payables
                    _CompactKpiCard(
                      width: kpiWidth,
                      icon: Icons.payments_outlined,
                      iconColor: const Color(0xFFDC2626),
                      label: 'Supplier Payables',
                      value: payablesVisible
                          ? _money(_dashboard['payables'])
                          : 'Restricted',
                      secondary: payablesVisible
                          ? 'Quarry outstanding'
                          : 'Finance permission needed',
                    ),
                    // 8. Pending Deliveries
                    _CompactKpiCard(
                      width: kpiWidth,
                      icon: Icons.pending_actions_outlined,
                      iconColor: const Color(0xFFEA580C),
                      label: 'Pending Orders',
                      value: '${_integer(_dashboard['open_order_count'])} orders',
                      secondary:
                          '${MaterialMeasurementEngine.formatQuantity(_dashboard['pending_delivery_cft'] ?? _dashboard['open_order_cft'] ?? 0, 'CFT')} remaining',
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 3. MAIN OPERATIONAL ACTIONS
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _SectionHeader(
                      title: 'Operational Actions',
                      subtitle: 'Primary workflows for yard operators and managers',
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => _open(AggregateLoadsScreen(session: session)),
                      icon: const Icon(Icons.table_rows_outlined, size: 15),
                      label: const Text('Open Load Register', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    _CompactActionTile(
                      width: actionWidth,
                      icon: Icons.south_west_rounded,
                      iconColor: const Color(0xFF00875A),
                      title: 'Purchase / Inward Load',
                      subtitle: 'Quarry loads, weighment, dimensional CFT & receipt.',
                      onTap: () => _open(
                        AggregateLoadsScreen(
                          session: session,
                          initialDirection: 'inbound',
                        ),
                      ),
                    ),
                    _CompactActionTile(
                      width: actionWidth,
                      icon: Icons.north_east_rounded,
                      iconColor: const Color(0xFF635BFF),
                      title: 'Sales / Outward Load',
                      subtitle: 'Customer dispatches, delivery slip & invoicing.',
                      onTap: () => _open(
                        AggregateLoadsScreen(
                          session: session,
                          initialDirection: 'outbound',
                        ),
                      ),
                    ),
                    _CompactActionTile(
                      width: actionWidth,
                      icon: Icons.price_change_outlined,
                      iconColor: const Color(0xFFD97706),
                      title: 'Daily Rate Board',
                      subtitle: 'Effective buy/sell rates with margin guardrails.',
                      onTap: () => _open(DailyMaterialRateBoardScreen(session: session)),
                    ),
                    _CompactActionTile(
                      width: actionWidth,
                      icon: Icons.compare_arrows_rounded,
                      iconColor: const Color(0xFF0284C7),
                      title: 'Direct Supply',
                      subtitle: 'Direct quarry to customer transit without yard holding.',
                      onTap: () => _open(AggregateDirectSupplyScreen(session: session)),
                    ),
                    _CompactActionTile(
                      width: actionWidth,
                      icon: Icons.assignment_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                      title: 'Customer Orders',
                      subtitle: 'Book orders and fulfill across multiple truck loads.',
                      onTap: () => _open(AggregateOrdersScreen(session: session)),
                    ),
                    _CompactActionTile(
                      width: actionWidth,
                      icon: Icons.local_shipping_outlined,
                      iconColor: const Color(0xFF475569),
                      title: 'Truck & Driver Setup',
                      subtitle: 'Vehicles, tare weight, capacity, driver assignment.',
                      onTap: () => _open(AggregateVehiclesScreen(session: session)),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 4. LOWER OPERATIONAL PANELS: VISIBLE LIVE DATA WITHOUT HIDDEN EXPANSION TILES
                if (isDesktopWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _ActiveLoadsSection(
                          rows: _rows('active_loads'),
                          quantityText: _qty,
                          onViewAll: () => _open(AggregateLoadsScreen(session: session)),
                          onOpenLoad: (row) => _open(
                            AggregateLoadsScreen(
                              session: session,
                              initialLoadId: row['load_id']?.toString(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 5,
                        child: _StockSection(
                          rows: _rows('stock_by_material'),
                          quantityText: _qty,
                          onViewAll: () => _open(AggregateYardStockScreen(session: session)),
                        ),
                      ),
                    ],
                  )
                else ...[
                  _ActiveLoadsSection(
                    rows: _rows('active_loads'),
                    quantityText: _qty,
                    onViewAll: () => _open(AggregateLoadsScreen(session: session)),
                    onOpenLoad: (row) => _open(
                      AggregateLoadsScreen(
                        session: session,
                        initialLoadId: row['load_id']?.toString(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _StockSection(
                    rows: _rows('stock_by_material'),
                    quantityText: _qty,
                    onViewAll: () => _open(AggregateYardStockScreen(session: session)),
                  ),
                ],

                const SizedBox(height: 16),

                // 5. SECONDARY MASTERS & REPORTS TOOLBAR
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 15,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Masters, Reports & Logistics',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _CompactChipBtn(
                            icon: Icons.table_chart_outlined,
                            label: 'Crusher Register',
                            onTap: () => _open(
                              MaterialYardCrusherReportScreen(session: session),
                            ),
                          ),
                          _CompactChipBtn(
                            icon: Icons.inventory_2_outlined,
                            label: 'Yard Stock Balances',
                            onTap: () => _open(
                              AggregateYardStockScreen(session: session),
                            ),
                          ),
                          _CompactChipBtn(
                            icon: Icons.badge_outlined,
                            label: 'Driver Master',
                            onTap: () => _open(DriverMasterScreen(session: session)),
                          ),
                          _CompactChipBtn(
                            icon: Icons.monetization_on_outlined,
                            label: 'Yard Profitability',
                            onTap: () => _open(AggregateFreightScreen(session: session)),
                          ),
                          _CompactChipBtn(
                            icon: Icons.factory_outlined,
                            label: 'Quarries / Suppliers',
                            onTap: () => _openWorkspace(
                              'Suppliers / Quarries',
                              SuppliersScreen(session: session),
                            ),
                          ),
                          _CompactChipBtn(
                            icon: Icons.groups_outlined,
                            label: 'Customers',
                            onTap: () => _openWorkspace(
                              'Customers',
                              CustomersScreen(session: session),
                            ),
                          ),
                          _CompactChipBtn(
                            icon: Icons.insights_outlined,
                            label: 'Reports Center',
                            onTap: () => _openWorkspace(
                              'Reports',
                              ReportsScreen(session: session),
                            ),
                          ),
                          if (_hasTransport)
                            _CompactChipBtn(
                              icon: Icons.route_outlined,
                              label: 'Trips & Transport',
                              onTap: () => _open(
                                TransportLogisticsHubScreen(session: session),
                              ),
                            ),
                        ],
                      ),
                    ],
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

// ==========================================
// COMPACT TOP APP BAR / HEADER
// ==========================================
class _CompactTopBar extends StatelessWidget {
  final String businessName;
  final String locationName;
  final bool isLoading;
  final VoidCallback? onRefresh;
  final VoidCallback onNewInward;
  final VoidCallback onNewOutward;
  final VoidCallback onRateBoard;

  const _CompactTopBar({
    required this.businessName,
    required this.locationName,
    required this.isLoading,
    required this.onRefresh,
    required this.onNewInward,
    required this.onNewOutward,
    required this.onRateBoard,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          // Left Badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.landscape_rounded,
              color: scheme.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'MATERIAL YARD',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Icon(Icons.storefront_outlined, size: 12, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
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
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Action Buttons
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            onPressed: onRateBoard,
            icon: const Icon(Icons.price_change_outlined, size: 14),
            label: const Text('Rate Board', style: TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 6),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: onNewOutward,
            icon: const Icon(Icons.north_east_rounded, size: 14),
            label: const Text('+ Outward Load', style: TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            ),
            onPressed: onNewInward,
            icon: const Icon(Icons.south_west_rounded, size: 14),
            label: const Text('+ Inward Load', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Refresh yard data',
            onPressed: onRefresh,
            icon: Icon(
              Icons.refresh_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// COMPACT KPI METRIC CARD
// ==========================================
class _CompactKpiCard extends StatelessWidget {
  final double width;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String secondary;

  const _CompactKpiCard({
    required this.width,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// COMPACT ACTION TILE
// ==========================================
class _CompactActionTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CompactActionTile({
    required this.width,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: width,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ACTIVE LOADS SECTION (TABLE FORMAT)
// ==========================================
class _ActiveLoadsSection extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String Function(dynamic value, {int decimals}) quantityText;
  final VoidCallback onViewAll;
  final void Function(Map<String, dynamic> row) onOpenLoad;

  const _ActiveLoadsSection({
    required this.rows,
    required this.quantityText,
    required this.onViewAll,
    required this.onOpenLoad,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleRows = rows.take(6).toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.route_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Active & Dispatched Loads (${rows.length})',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              InkWell(
                onTap: onViewAll,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'View all →',
                    style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (visibleRows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No active loads in transit or loading right now.', style: TextStyle(fontSize: 11)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleRows.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                thickness: 0.5,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              itemBuilder: (context, i) {
                final row = visibleRows[i];
                final isInbound = row['direction'] == 'inbound';
                final status = (row['status'] ?? '').toString().replaceAll('_', ' ').toUpperCase();

                return InkWell(
                  onTap: () => onOpenLoad(row),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isInbound
                                ? const Color(0xFF00875A).withValues(alpha: 0.1)
                                : const Color(0xFF635BFF).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            isInbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                            size: 13,
                            color: isInbound ? const Color(0xFF00875A) : const Color(0xFF635BFF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['load_number'] ?? ''}  •  ${row['product_name'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${row['vehicle_registration'] ?? 'No truck'} • ${row['driver_name'] ?? 'No driver'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${quantityText(row['quantity'])} ${row['unit_code'] ?? 'CFT'}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ==========================================
// STOCK SECTION (COMPACT TABLE FORMAT)
// ==========================================
class _StockSection extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String Function(dynamic value, {int decimals}) quantityText;
  final VoidCallback onViewAll;

  const _StockSection({
    required this.rows,
    required this.quantityText,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibleRows = rows.take(6).toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.warehouse_outlined, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Yard Material Stock (${rows.length})',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              InkWell(
                onTap: onViewAll,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'View all →',
                    style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (visibleRows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No stock balances recorded in this yard.', style: TextStyle(fontSize: 11)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleRows.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                thickness: 0.5,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              itemBuilder: (context, i) {
                final row = visibleRows[i];
                final variant = row['variant_name']?.toString().trim() ?? '';
                final product = row['product_name']?.toString() ?? '';
                final name = variant.isEmpty ||
                        variant.toLowerCase() == 'default' ||
                        variant.toLowerCase() == 'standard'
                    ? product
                    : '$product • $variant';
                final unit = row['unit_code']?.toString() ?? 'CFT';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${quantityText(row['available'])} $unit',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'On hand ${quantityText(row['on_hand'])}',
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ==========================================
// CHIP BUTTON HELPER
// ==========================================
class _CompactChipBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CompactChipBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
    );
  }
}

// ==========================================
// SECTION HEADER HELPER
// ==========================================
class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        Text(
          subtitle,
          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ==========================================
// ERROR BANNER
// ==========================================
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onErrorContainer),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
