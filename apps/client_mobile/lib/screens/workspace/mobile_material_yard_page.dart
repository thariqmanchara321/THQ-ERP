import 'package:flutter/material.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import 'material_yard/material_yard_detail_sheet.dart';
import 'material_yard/material_yard_load_sheet.dart';
import 'material_yard/material_yard_more_views.dart';
import 'material_yard/material_yard_types.dart';

class MobileMaterialYardPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileMaterialYardPage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileMaterialYardPage> createState() => _MobileMaterialYardPageState();
}

class _MobileMaterialYardPageState extends State<MobileMaterialYardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _currentLocationId;

  // Search & Filter state
  final _inwardSearchCtrl = TextEditingController();
  final _outwardSearchCtrl = TextEditingController();
  final _stockSearchCtrl = TextEditingController();

  String _inwardStatusFilter = 'all';
  String _outwardStatusFilter = 'all';

  // Futures
  late Future<Map<String, dynamic>> _dashboardFuture;
  late Future<List<Map<String, dynamic>>> _inwardLoadsFuture;
  late Future<List<Map<String, dynamic>>> _outwardLoadsFuture;
  late Future<List<Map<String, dynamic>>> _stockFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _currentLocationId = widget.locationId ?? widget.session.locationId;
    _reloadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inwardSearchCtrl.dispose();
    _outwardSearchCtrl.dispose();
    _stockSearchCtrl.dispose();
    super.dispose();
  }

  void _reloadAll() {
    _dashboardFuture = widget.service.materialYardDashboard(
      widget.session,
      locationId: _currentLocationId,
      day: DateTime.now(),
    );
    _inwardLoadsFuture = widget.service.materialLoads(
      widget.session,
      locationId: _currentLocationId,
      direction: 'inbound',
      status: _inwardStatusFilter == 'all' ? null : _inwardStatusFilter,
    );
    _outwardLoadsFuture = widget.service.materialLoads(
      widget.session,
      locationId: _currentLocationId,
      direction: 'outbound',
      status: _outwardStatusFilter == 'all' ? null : _outwardStatusFilter,
    );
    _stockFuture = widget.service.materialYardStock(
      widget.session,
      locationId: _currentLocationId,
    );
  }

  Future<void> _refresh() async {
    setState(_reloadAll);
    await Future.wait([
      _dashboardFuture,
      _inwardLoadsFuture,
      _outwardLoadsFuture,
      _stockFuture,
    ]);
  }

  void _openNewLoad({required String direction}) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MobileMaterialLoadSheet(
        session: widget.session,
        service: widget.service,
        initialDirection: direction,
        initialLocationId: _currentLocationId,
        onSaved: _refresh,
      ),
    );
    if (created == true && mounted) {
      _refresh();
    }
  }

  void _openLoadDetail(String loadId) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MobileMaterialLoadDetailSheet(
        session: widget.session,
        service: widget.service,
        loadId: loadId,
        onChanged: _refresh,
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Material Yard & Quarry'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
            Tab(icon: Icon(Icons.south_west_rounded), text: 'Inward'),
            Tab(icon: Icon(Icons.north_east_rounded), text: 'Outward'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Stock'),
            Tab(icon: Icon(Icons.more_horiz_rounded), text: 'More'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(),
          _buildInwardTab(),
          _buildOutwardTab(),
          _buildStockTab(),
          _buildMoreTab(),
        ],
      ),
    );
  }

  // ==========================================================================
  // TAB 1: DASHBOARD
  // ==========================================================================
  Widget _buildDashboardTab() {
    final currency = widget.session.currency;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text('Failed to load dashboard: ${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final db = snapshot.data ?? {};
          final inLoads = db['today_inward_loads'] ?? db['today_in_loads'] ?? 0;
          final inCft = db['today_inward_qty_cft'] ?? db['today_in_cft'] ?? 0;
          final outLoads = db['today_outward_loads'] ?? db['today_out_loads'] ?? 0;
          final outCft = db['today_outward_qty_cft'] ?? db['today_out_cft'] ?? 0;
          final purchaseVal = db['today_purchase_value'] ?? 0;
          final salesVal = db['today_sales_value'] ?? 0;
          final stockAvailable = db['available_stock_cft'] ?? db['stock_available_cft'] ?? 0;
          final stockOnHand = db['stock_on_hand_cft'] ?? stockAvailable;
          final receivables = db['receivables'];
          final payables = db['payables'];
          final receivablesVisible = db['receivables_visible'] == true || widget.session.canViewReceivables;
          final payablesVisible = db['payables_visible'] == true || widget.session.canViewPayables;
          final openOrders = db['open_order_count'] ?? 0;
          final pendingDeliveryCft = db['pending_delivery_cft'] ?? 0;
          final recentLoads = (db['recent_loads'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
            children: [
              // Prominent Action Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF00875A), // Green
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _openNewLoad(direction: 'inbound'),
                      icon: const Icon(Icons.south_west_rounded, size: 20),
                      label: const Text('+ New Inward', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF635BFF), // Purple/Indigo
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _openNewLoad(direction: 'outbound'),
                      icon: const Icon(Icons.north_east_rounded, size: 20),
                      label: const Text('+ New Outward', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // 8 Authoritative KPI Cards Grid
              const Text('Today\'s Yard Operations', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.55,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildKpiCard(
                    icon: Icons.south_west_rounded,
                    iconColor: const Color(0xFF00875A),
                    label: "Today's Inward",
                    value: '$inLoads loads',
                    subtext: '${MaterialYardFormat.cft(inCft)} received',
                  ),
                  _buildKpiCard(
                    icon: Icons.north_east_rounded,
                    iconColor: const Color(0xFF635BFF),
                    label: "Today's Outward",
                    value: '$outLoads loads',
                    subtext: '${MaterialYardFormat.cft(outCft)} dispatched',
                  ),
                  _buildKpiCard(
                    icon: Icons.shopping_bag_outlined,
                    iconColor: const Color(0xFF0D9488),
                    label: "Today's Purchase",
                    value: MaterialYardFormat.money(purchaseVal, currency: currency),
                    subtext: '$inLoads quarry bills',
                  ),
                  _buildKpiCard(
                    icon: Icons.point_of_sale_outlined,
                    iconColor: const Color(0xFF7C3AED),
                    label: "Today's Sales",
                    value: MaterialYardFormat.money(salesVal, currency: currency),
                    subtext: '$outLoads sales loads',
                  ),
                  _buildKpiCard(
                    icon: Icons.inventory_2_outlined,
                    iconColor: const Color(0xFF0052CC),
                    label: 'Available Bulk Stock',
                    value: MaterialYardFormat.cft(stockAvailable),
                    subtext: 'On-hand ${MaterialYardFormat.cft(stockOnHand)}',
                  ),
                  _buildKpiCard(
                    icon: Icons.pending_actions_outlined,
                    iconColor: const Color(0xFFEA580C),
                    label: 'Pending Orders',
                    value: '$openOrders orders',
                    subtext: '${MaterialYardFormat.cft(pendingDeliveryCft)} remaining',
                  ),
                  _buildKpiCard(
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: const Color(0xFFD97706),
                    label: 'Customer Receivables',
                    value: receivablesVisible ? MaterialYardFormat.money(receivables ?? 0, currency: currency) : 'Restricted',
                    subtext: receivablesVisible ? 'Ledger outstanding' : 'Finance permission',
                  ),
                  _buildKpiCard(
                    icon: Icons.payments_outlined,
                    iconColor: const Color(0xFFDC2626),
                    label: 'Supplier Payables',
                    value: payablesVisible ? MaterialYardFormat.money(payables ?? 0, currency: currency) : 'Restricted',
                    subtext: payablesVisible ? 'Quarry outstanding' : 'Finance permission',
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Recent Yard Activity
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Yard Activity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => _tabController.animateTo(1),
                    child: const Text('View All', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),

              if (recentLoads.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('No loads recorded today yet.')),
                  ),
                )
              else
                ...recentLoads.take(6).map((item) {
                  final loadId = item['load_id']?.toString() ?? item['id']?.toString() ?? '';
                  final loadNum = item['load_number'] ?? 'LD-$loadId';
                  final truck = item['vehicle_registration'] ?? item['vehicle_registration_snapshot'] ?? 'No Reg';
                  final material = item['product_name'] ?? 'Aggregate';
                  final qty = item['quantity'] ?? 0;
                  final unit = item['unit_code'] ?? 'CFT';
                  final status = item['status']?.toString().toLowerCase() ?? 'draft';
                  final isIn = item['direction']?.toString().toLowerCase() == 'inbound';
                  final statusColor = MaterialYardFormat.statusColor(status);

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: ListTile(
                      onTap: () => _openLoadDetail(loadId),
                      leading: CircleAvatar(
                        backgroundColor: (isIn ? Colors.teal : Colors.indigo).withValues(alpha: 0.12),
                        child: Icon(
                          isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                          color: isIn ? Colors.teal : Colors.indigo,
                          size: 18,
                        ),
                      ),
                      title: Text('$truck • $material', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('$loadNum • ${MaterialYardFormat.quantity(qty, unit)}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          MaterialYardFormat.statusLabel(status),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  // ==========================================================================
  // TAB 2: INWARD REGISTER
  // ==========================================================================
  Widget _buildInwardTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: TextField(
            controller: _inwardSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Search truck, supplier, driver or material...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              _buildFilterChip('All', _inwardStatusFilter == 'all', () {
                setState(() {
                  _inwardStatusFilter = 'all';
                  _reloadAll();
                });
              }),
              const SizedBox(width: 6),
              _buildFilterChip('Draft', _inwardStatusFilter == 'draft', () {
                setState(() {
                  _inwardStatusFilter = 'draft';
                  _reloadAll();
                });
              }),
              const SizedBox(width: 6),
              _buildFilterChip('Confirmed', _inwardStatusFilter == 'confirmed', () {
                setState(() {
                  _inwardStatusFilter = 'confirmed';
                  _reloadAll();
                });
              }),
              const SizedBox(width: 6),
              _buildFilterChip('Invoiced', _inwardStatusFilter == 'invoiced', () {
                setState(() {
                  _inwardStatusFilter = 'invoiced';
                  _reloadAll();
                });
              }),
            ],
          ),
        ),
        Expanded(
          child: _buildLoadsList(
            future: _inwardLoadsFuture,
            searchQuery: _inwardSearchCtrl.text.trim().toLowerCase(),
            emptyLabel: 'No inward quarry loads found.',
            onNewLoad: () => _openNewLoad(direction: 'inbound'),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 3: OUTWARD REGISTER
  // ==========================================================================
  Widget _buildOutwardTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: TextField(
            controller: _outwardSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Search truck, customer, driver or material...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            children: [
              _buildFilterChip('All', _outwardStatusFilter == 'all', () {
                setState(() {
                  _outwardStatusFilter = 'all';
                  _reloadAll();
                });
              }),
              const SizedBox(width: 6),
              _buildFilterChip('Draft', _outwardStatusFilter == 'draft', () {
                setState(() {
                  _outwardStatusFilter = 'draft';
                  _reloadAll();
                });
              }),
              const SizedBox(width: 6),
              _buildFilterChip('Confirmed', _outwardStatusFilter == 'confirmed', () {
                setState(() {
                  _outwardStatusFilter = 'confirmed';
                  _reloadAll();
                });
              }),
              const SizedBox(width: 6),
              _buildFilterChip('Invoiced', _outwardStatusFilter == 'invoiced', () {
                setState(() {
                  _outwardStatusFilter = 'invoiced';
                  _reloadAll();
                });
              }),
            ],
          ),
        ),
        Expanded(
          child: _buildLoadsList(
            future: _outwardLoadsFuture,
            searchQuery: _outwardSearchCtrl.text.trim().toLowerCase(),
            emptyLabel: 'No outward sales loads found.',
            onNewLoad: () => _openNewLoad(direction: 'outbound'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadsList({
    required Future<List<Map<String, dynamic>>> future,
    required String searchQuery,
    required String emptyLabel,
    required VoidCallback onNewLoad,
  }) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, size: 40, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 10),
                  Text('Error loading loads: ${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        final all = snapshot.data ?? [];
        final filtered = all.where((row) {
          if (searchQuery.isEmpty) return true;
          final truck = (row['vehicle_registration'] ?? row['vehicle_registration_snapshot'] ?? '').toString().toLowerCase();
          final driver = (row['driver_name'] ?? row['driver_name_snapshot'] ?? '').toString().toLowerCase();
          final party = (row['customer_name'] ?? row['supplier_name'] ?? row['party_name'] ?? '').toString().toLowerCase();
          final mat = (row['product_name'] ?? row['variant_name'] ?? '').toString().toLowerCase();
          final loadNum = (row['load_number'] ?? '').toString().toLowerCase();
          return truck.contains(searchQuery) ||
              driver.contains(searchQuery) ||
              party.contains(searchQuery) ||
              mat.contains(searchQuery) ||
              loadNum.contains(searchQuery);
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_shipping_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 10),
                Text(emptyLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onNewLoad,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create New Load'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
            itemCount: filtered.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final item = filtered[i];
              final loadId = item['load_id']?.toString() ?? item['id']?.toString() ?? '';
              final loadNum = item['load_number'] ?? 'LD-$loadId';
              final truck = item['vehicle_registration'] ?? item['vehicle_registration_snapshot'] ?? 'No Truck Reg';
              final driver = item['driver_name'] ?? item['driver_name_snapshot'] ?? '';
              final material = item['product_name'] ?? item['variant_name'] ?? 'Aggregate';
              final qty = item['quantity'] ?? 0;
              final unit = item['unit_code'] ?? 'CFT';
              final party = item['customer_name'] ?? item['supplier_name'] ?? item['party_name'] ?? 'Direct Party';
              final status = (item['status'] ?? 'draft').toString().toLowerCase();
              final statusColor = MaterialYardFormat.statusColor(status);
              final invoiceNum = item['invoice_number'] ?? item['sale_number'] ?? item['purchase_number'];
              final date = item['load_date']?.toString().split('T').first ?? '';

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _openLoadDetail(loadId),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(truck, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                MaterialYardFormat.statusLabel(status),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('$material • ${MaterialYardFormat.quantity(qty, unit)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text('Party: $party${driver.isNotEmpty ? " • Driver: $driver" : ""}', style: Theme.of(context).textTheme.bodySmall),
                        const Divider(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(loadNum, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
                            if (invoiceNum != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                                child: Text('Inv #$invoiceNum', style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                              )
                            else if (date.isNotEmpty)
                              Text(date, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ==========================================================================
  // TAB 4: STOCK & BATCHES
  // ==========================================================================
  Widget _buildStockTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: TextField(
            controller: _stockSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Search stock material...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _stockFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error loading stock: ${snapshot.error}'));
              }

              final allStock = snapshot.data ?? [];
              final query = _stockSearchCtrl.text.trim().toLowerCase();
              final filtered = allStock.where((s) {
                if (query.isEmpty) return true;
                final name = (s['product_name'] ?? s['name'] ?? s['material_name'] ?? '').toString().toLowerCase();
                final variant = (s['variant_name'] ?? s['quality_grade'] ?? '').toString().toLowerCase();
                return name.contains(query) || variant.contains(query);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(child: Text('No bulk stock inventory records found.'));
              }

              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    final name = item['product_name'] ?? item['name'] ?? item['material_name'] ?? 'Material';
                    final variant = item['variant_name'] ?? item['quality_grade'] ?? '';
                    final avail = item['stock_available_cft'] ?? item['available_quantity'] ?? item['available_qty'] ?? 0;
                    final onHand = item['stock_on_hand_cft'] ?? item['on_hand_quantity'] ?? item['on_hand_qty'] ?? avail;
                    final unit = item['unit_code'] ?? 'CFT';

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue.withValues(alpha: 0.1),
                              child: const Icon(Icons.inventory_2_outlined, color: Colors.blue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$name${variant.toString().isNotEmpty ? " • $variant" : ""}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'On-hand: ${MaterialYardFormat.quantity(onHand, unit)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Available', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
                                Text(
                                  MaterialYardFormat.quantity(avail, unit),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0052CC)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 5: MORE SECTION
  // ==========================================================================
  Widget _buildMoreTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _buildMoreTile(
          icon: Icons.price_change_outlined,
          title: 'Daily Rate Board',
          subtitle: 'View and update per-material buy and sell rates',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MobileDailyRatesBoard(
                session: widget.session,
                service: widget.service,
                locationId: _currentLocationId,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildMoreTile(
          icon: Icons.fire_truck_outlined,
          title: 'Yard Trucks & Fleet Master',
          subtitle: 'Register vehicles, nominal capacity and body dimensions',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MobileTrucksFleetView(
                session: widget.session,
                service: widget.service,
                locationId: _currentLocationId,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildMoreTile(
          icon: Icons.badge_outlined,
          title: 'Yard Driver Master',
          subtitle: 'Register drivers, mobile numbers and licenses',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MobileDriverMasterView(
                session: widget.session,
                service: widget.service,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildMoreTile(
          icon: Icons.assignment_outlined,
          title: 'Customer Bulk Orders',
          subtitle: 'Track advance aggregate commitments and balances',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MobileCustomerOrdersView(
                session: widget.session,
                service: widget.service,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildMoreTile(
          icon: Icons.local_shipping_outlined,
          title: 'Freight & Logistics Settlement',
          subtitle: 'Review transporter freight allowances and settlements',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MobileFreightLogisticsView(
                session: widget.session,
                service: widget.service,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMoreTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected, VoidCallback onSelected) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String subtext,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtext,
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
