import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';
import '../../../services/inventory_service.dart';
import '../../../services/location_scope_service.dart';
import '../../../services/purchase_receiving_service.dart';
import '../../../services/stock_counting_service.dart';

/// Complete Smart Inventory Control Centre Overview Tab (Phase 14).
///
/// Features:
/// 1. Real-time Inventory Health KPIs (Total SKUs, Active/Inactive, Low Stock, Out of Stock, Valuation).
/// 2. Role-based financial privacy protection (Cost valuation masked for unauthorized roles).
/// 3. Operational pipeline status (Pending stock audits, receivable purchase orders).
/// 4. Actionable inventory alerts (Low stock warnings, missing barcodes requiring attention).
/// 5. Quick workspace launchers for immediate workflow navigation.
/// 6. Live hardware & wedge session scanning activity feed.
class SmartInventoryOverviewTab extends StatefulWidget {
  final ClientSession session;
  final ValueChanged<int> onSelectTab;

  const SmartInventoryOverviewTab({
    super.key,
    required this.session,
    required this.onSelectTab,
  });

  @override
  State<SmartInventoryOverviewTab> createState() =>
      _SmartInventoryOverviewTabState();
}

class _SmartInventoryOverviewTabState extends State<SmartInventoryOverviewTab> {
  final ClientSmartInventoryService _smartService =
      ClientSmartInventoryService.instance;
  final InventoryService _inventoryService = InventoryService();
  final StockCountingService _stockService = StockCountingService.instance;
  final PurchaseReceivingService _purchaseService =
      PurchaseReceivingService.instance;

  bool _isLoadingMetrics = false;
  int _totalProducts = 0;
  int _activeProducts = 0;
  int _inactiveProducts = 0;
  int _lowStockCount = 0;
  int _outOfStockCount = 0;
  int _missingBarcodeCount = 0;
  double _totalStockUnits = 0.0;
  double _inventoryValuation = 0.0;

  int _openPoCount = 0;
  int _pastCountsCount = 0;

  bool get _canViewCostPrice =>
      widget.session.hasPermission('inventory.view_cost') ||
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasRole('owner') ||
      widget.session.hasRole('admin');

  @override
  void initState() {
    super.initState();
    _loadLiveMetrics();
  }

  Future<void> _loadLiveMetrics() async {
    if (!mounted) return;
    setState(() => _isLoadingMetrics = true);

    try {
      // Guard against uninitialized Supabase client in test environment
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null &&
          client.rest.headers['apikey'] == null) {
        // Test or offline mode without live backend
        if (mounted) setState(() => _isLoadingMetrics = false);
        return;
      }

      final tenantId = widget.session.business.id;
      final locationId = LocationScopeService.selectedLocationId.value ??
          LocationScopeService.currentForRead(widget.session);

      // Fetch products for catalogue health
      final products = await _inventoryService.getProducts(
        tenantId: tenantId,
        locationId: locationId,
      );

      var active = 0;
      var inactive = 0;
      var low = 0;
      var out = 0;
      var missingBc = 0;
      var units = 0.0;
      var valuation = 0.0;

      for (final p in products) {
        if (p.productStatus == 'active' && p.variantStatus == 'active') {
          active++;
        } else {
          inactive++;
        }

        if (p.barcode == null || p.barcode!.trim().isEmpty) {
          missingBc++;
        }

        if (p.itemType == 'stock') {
          units += p.stockQuantity;
          valuation += p.costPrice * p.stockQuantity;

          if (p.stockQuantity <= 0) {
            out++;
          } else if (p.reorderLevel > 0 && p.stockQuantity <= p.reorderLevel) {
            low++;
          }
        }
      }

      // Fetch open receivable purchase orders
      var poCount = 0;
      try {
        final pos = await _purchaseService.listReceivablePurchaseOrders(
          tenantId: tenantId,
          locationId: locationId,
          limit: 100,
        );
        poCount = pos.length;
      } catch (_) {}

      // Fetch past stock counts count
      var countsCount = 0;
      try {
        final counts = await _stockService.listPastCounts(
          tenantId: tenantId,
          locationId: locationId,
          limit: 50,
        );
        countsCount = counts.length;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _totalProducts = products.length;
          _activeProducts = active;
          _inactiveProducts = inactive;
          _lowStockCount = low;
          _outOfStockCount = out;
          _missingBarcodeCount = missingBc;
          _totalStockUnits = units;
          _inventoryValuation = valuation;
          _openPoCount = poCount;
          _pastCountsCount = countsCount;
          _isLoadingMetrics = false;
        });
      }
    } catch (_) {
      // Gracefully handle offline or mock environments
      if (mounted) {
        setState(() => _isLoadingMetrics = false);
      }
    }
  }

  String _formatMoney(double amount) {
    if (!_canViewCostPrice) {
      return '• • • • (Restricted)';
    }
    final formatted = NumberFormat('#,##0.00').format(amount);
    return widget.session.currencyCode == 'INR'
        ? '₹$formatted'
        : '${widget.session.currencyCode} $formatted';
  }

  @override
  Widget build(BuildContext context) {
    final activity = _smartService.recentActivity;
    final totalScans = activity.length;
    final successfulScans = activity
        .where((e) => e.status == ProductIdentificationStatus.exactMatch)
        .length;
    final unresolvedScans = activity
        .where((e) => e.status != ProductIdentificationStatus.exactMatch)
        .length;
    final activeBulk = _smartService.activeBulkSession;

    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Control Centre Header Card
          ThqCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.inventory_2_rounded,
                        color: colors.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'THQ Smart Inventory Control Centre',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            if (_isLoadingMetrics) ...[
                              const SizedBox(width: 8),
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Executive dashboard: catalogue health, stock valuation, operational audits, and hardware scanning.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh Inventory Statistics',
                    onPressed: _isLoadingMetrics ? null : _loadLiveMetrics,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Inventory Health Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Catalogue & Stock Health',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (_totalProducts > 0)
                Text(
                  '$_totalProducts Items • ${NumberFormat('#,##0').format(_totalStockUnits)} Units on hand',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Real-time Inventory Health KPI Tiles
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              final tiles = [
                _StatTile(
                  label: 'Catalogue Items',
                  value: _totalProducts > 0
                      ? '$_totalProducts Items'
                      : 'Active Catalogue',
                  detail: _totalProducts > 0
                      ? '$_activeProducts active • $_inactiveProducts inactive'
                      : 'Live product count',
                  icon: Icons.category_outlined,
                  color: colors.primary,
                  onTap: () => widget.onSelectTab(2),
                ),
                _StatTile(
                  label: 'Low Stock Alerts',
                  value: '$_lowStockCount SKUs',
                  detail: _lowStockCount > 0
                      ? 'Reorder threshold reached'
                      : 'Stock levels healthy',
                  icon: Icons.warning_amber_rounded,
                  color: _lowStockCount > 0 ? Colors.amber[800]! : Colors.green,
                  onTap: () => widget.onSelectTab(2),
                ),
                _StatTile(
                  label: 'Out of Stock',
                  value: '$_outOfStockCount SKUs',
                  detail: _outOfStockCount > 0
                      ? 'Action required: 0 balance'
                      : 'All items stocked',
                  icon: Icons.remove_shopping_cart_outlined,
                  color: _outOfStockCount > 0 ? Colors.red : Colors.green,
                  onTap: () => widget.onSelectTab(2),
                ),
                _StatTile(
                  label: 'Inventory Valuation',
                  value: _formatMoney(_inventoryValuation),
                  detail: _canViewCostPrice
                      ? 'Cost-basis on-hand valuation'
                      : 'Permission restricted',
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.teal,
                  onTap: () => widget.onSelectTab(2),
                ),
              ];

              if (isWide) {
                return Row(
                  children: tiles
                      .map((t) => Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: t,
                            ),
                          ))
                      .toList(),
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: tiles
                    .map((t) => SizedBox(
                          width: (constraints.maxWidth - 10) / 2,
                          child: t,
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 16),

          // Operational Pipeline Bar (Stock Counts, Goods Inward, Barcode Quality)
          if (_openPoCount > 0 ||
              _pastCountsCount > 0 ||
              _missingBarcodeCount > 0)
            ThqCard(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.assignment_turned_in_outlined,
                        color: colors.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Operations Pipeline: ${_openPoCount > 0 ? '$_openPoCount open Purchase Order(s) awaiting receipt • ' : ''}'
                        '${_pastCountsCount > 0 ? '$_pastCountsCount past stock audit(s) • ' : ''}'
                        '${_missingBarcodeCount > 0 ? '$_missingBarcodeCount product(s) missing primary barcode' : 'All products have barcodes'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    if (_openPoCount > 0)
                      TextButton(
                        onPressed: () => widget.onSelectTab(8),
                        child: const Text('View Receiving',
                            style: TextStyle(fontSize: 12)),
                      ),
                    if (_missingBarcodeCount > 0)
                      TextButton(
                        onPressed: () => widget.onSelectTab(6),
                        child: const Text('Print Labels',
                            style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Scanning & Session Metrics Bar
          Text(
            'Hardware & Scan Activity',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final tiles = [
                _StatTile(
                  label: 'Session Scans',
                  value: totalScans.toString(),
                  detail: 'Hardware wedge & camera',
                  icon: Icons.barcode_reader,
                  color: colors.primary,
                  onTap: () => widget.onSelectTab(1),
                ),
                _StatTile(
                  label: 'Identified Products',
                  value: successfulScans.toString(),
                  detail: totalScans > 0
                      ? '${((successfulScans / totalScans) * 100).toStringAsFixed(0)}% resolution rate'
                      : 'Exact catalogue matches',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  onTap: () => widget.onSelectTab(1),
                ),
                _StatTile(
                  label: 'Unresolved / Misses',
                  value: unresolvedScans.toString(),
                  detail: unresolvedScans > 0
                      ? 'Candidates or unknown codes'
                      : 'No unresolved barcodes',
                  icon: Icons.help_outline,
                  color: unresolvedScans > 0
                      ? Colors.orange
                      : colors.onSurfaceVariant,
                  onTap: () => widget.onSelectTab(4),
                ),
                _StatTile(
                  label: 'Bulk Session',
                  value: activeBulk != null
                      ? '${activeBulk.totalDistinctProducts} items'
                      : 'Idle',
                  detail: activeBulk != null
                      ? '${activeBulk.totalScans} total units counted'
                      : 'Start batch scan audit',
                  icon: Icons.format_list_numbered,
                  color:
                      activeBulk != null ? Colors.blue : colors.onSurfaceVariant,
                  onTap: () => widget.onSelectTab(3),
                ),
              ];

              if (isWide) {
                return Row(
                  children: tiles
                      .map((t) => Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
                              child: t,
                            ),
                          ))
                      .toList(),
                );
              }
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: tiles
                    .map((t) => SizedBox(
                          width: (constraints.maxWidth - 10) / 2,
                          child: t,
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 24),

          // Action Launchers Section
          Text(
            'Quick Workspaces',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _ActionCard(
                  title: 'Scan Center',
                  subtitle:
                      'Point camera or use USB/Bluetooth barcode gun to immediately identify single products.',
                  icon: Icons.camera_alt_outlined,
                  buttonText: 'Open Scan Center',
                  onTap: () => widget.onSelectTab(1),
                ),
                _ActionCard(
                  title: 'Product Lookup',
                  subtitle:
                      'Search by name, SKU, manufacturer code, supplier part number or alternate identifiers.',
                  icon: Icons.search,
                  buttonText: 'Search Catalog',
                  onTap: () => widget.onSelectTab(2),
                ),
                _ActionCard(
                  title: 'Bulk Scanning',
                  subtitle:
                      'Continuously scan crates or shipments into a temporary audit list without altering stock.',
                  icon: Icons.playlist_add_check,
                  buttonText: 'Start Bulk Scan',
                  onTap: () => widget.onSelectTab(3),
                ),
                _ActionCard(
                  title: 'Product Import',
                  subtitle:
                      'Batch import product catalogues from Excel (.xlsx) or CSV with intelligent auto-mapping.',
                  icon: Icons.upload_file_outlined,
                  buttonText: 'Import Products',
                  onTap: () => widget.onSelectTab(5),
                ),
                _ActionCard(
                  title: 'Barcode Studio',
                  subtitle:
                      'Design, generate, and print thermal barcode labels and A4 multi-label sheets with GS1 check digits.',
                  icon: Icons.print_outlined,
                  buttonText: 'Open Barcode Studio',
                  onTap: () => widget.onSelectTab(6),
                ),
                _ActionCard(
                  title: 'Stock Counting',
                  subtitle:
                      'Perform physical stock audits, reconcile shortages or excess, and post approved count adjustments.',
                  icon: Icons.inventory_2_outlined,
                  buttonText: 'Start Stock Count',
                  onTap: () => widget.onSelectTab(7),
                ),
                _ActionCard(
                  title: 'Purchase Receiving',
                  subtitle:
                      'Inward supplier deliveries against purchase orders or direct receipts, verify quantities, and post goods receipts.',
                  icon: Icons.call_received,
                  buttonText: 'Receive Goods',
                  onTap: () => widget.onSelectTab(8),
                ),
                _ActionCard(
                  title: 'Product Intelligence',
                  subtitle:
                      'Lookup products against GS1 Registry and open catalogues, resolve conflicts side-by-side, and enrich catalogue data.',
                  icon: Icons.auto_awesome,
                  buttonText: 'Lookup Intelligence',
                  onTap: () => widget.onSelectTab(9),
                ),
              ];

              final width = constraints.maxWidth;
              final crossAxisCount = width > 1100 ? 4 : (width > 650 ? 2 : 1);
              if (crossAxisCount > 1) {
                final cardWidth =
                    (width - ((crossAxisCount - 1) * 12)) / crossAxisCount;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards
                      .map((c) => SizedBox(
                            width: cardWidth,
                            child: c,
                          ))
                      .toList(),
                );
              }
              return Column(
                children: cards
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: c,
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 28),

          // Recent Activity Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Scan Activity',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (activity.isNotEmpty)
                Text(
                  '${activity.length} recorded',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (activity.isEmpty)
            ThqCard(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.barcode_reader,
                        size: 40, color: colors.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'No scans performed yet in this session',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect a USB barcode gun, click Scan Center, or search catalog to begin.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ThqCard(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activity.length > 8 ? 8 : activity.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = activity[index];
                  final isSuccess = item.isSuccess;
                  final timeStr = DateFormat('HH:mm:ss').format(item.timestamp);

                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isSuccess
                          ? Colors.green.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      child: Icon(
                        isSuccess ? Icons.check : Icons.help_outline,
                        size: 16,
                        color: isSuccess ? Colors.green : Colors.orange,
                      ),
                    ),
                    title: Text(
                      isSuccess
                          ? item.productName ?? 'Product Found'
                          : 'Unresolved Code',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: Text(
                      'Code: ${item.rawCode}${item.sku != null ? ' • SKU: ${item.sku}' : ''}',
                      style: TextStyle(
                          fontSize: 11, color: colors.onSurfaceVariant),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ThqStatusBadge(
                          status: isSuccess
                              ? ThqStatus.completed
                              : ThqStatus.pending,
                          label: item.status.name,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          timeStr,
                          style: TextStyle(
                              fontSize: 11, color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatTile({
    required this.label,
    required this.value,
    this.detail,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ThqCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail!,
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String buttonText;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.buttonText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ThqCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.primary, size: 26),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
                height: 1.3,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ThqSecondaryButton(
                label: buttonText,
                onPressed: onTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
