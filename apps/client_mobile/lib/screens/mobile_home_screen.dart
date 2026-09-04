// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import '../models/mobile_session.dart';
import '../services/device_installation_service.dart';
import '../services/mobile_auth_service.dart';
import '../services/mobile_client_service.dart';
import 'mobile_entry_screen.dart';

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
  late Future<Map<String, dynamic>> _dashboard;
  @override
  void initState() {
    super.initState();
    _locationId = widget.session.canViewAllLocations
        ? null
        : widget.session.locationId;
    _dashboard = _service.dashboard(widget.session, locationId: _locationId);
  }

  void _refresh() {
    setState(
      () => _dashboard = _service.dashboard(
        widget.session,
        locationId: _locationId,
      ),
    );
  }

  String money(dynamic v) {
    final n = v is num
        ? v.toDouble()
        : double.tryParse(v?.toString() ?? '') ?? 0;
    return '${widget.session.currencyCode} ${n.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardTab(
        session: widget.session,
        future: _dashboard,
        money: money,
        onRefresh: _refresh,
        locationId: _locationId,
        onLocation: (v) {
          setState(() => _locationId = v);
          _refresh();
        },
        onOpen: _open,
      ),
      _BusinessTab(open: _open),
      _ApprovalsTab(session: widget.session, service: _service, money: money),
      _MoreTab(
        session: widget.session,
        service: _service,
        money: money,
        onOpen: _open,
        onLogout: _logout,
      ),
    ];

    final titles = ['Dashboard', 'Business', 'Approvals', 'More'];

    return Scaffold(
      appBar: _index == 0
          ? null
          : AppBar(
              toolbarHeight: 56,
              title: Text(titles[_index]),
              actions: [
                if (_index == 1)
                  IconButton(
                    tooltip: 'Refresh dashboard',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                const SizedBox(width: 4),
              ],
            ),
      body: _index == 0
          ? pages[_index]
          : SafeArea(top: false, child: pages[_index]),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE9E6F1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (v) => setState(() => _index = v),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_rounded),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Overview',
                ),
                NavigationDestination(
                  icon: Icon(Icons.business_center_outlined),
                  selectedIcon: Icon(Icons.business_center_rounded),
                  label: 'Business',
                ),
                NavigationDestination(
                  icon: Icon(Icons.approval_outlined),
                  selectedIcon: Icon(Icons.approval_rounded),
                  label: 'Approvals',
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
      ),
    );
  }

  Future<void> _logout() async {
    await MobileAuthService().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MobileEntryScreen()),
      (_) => false,
    );
  }

  void _open(String key) {
    switch (key) {
      case 'sales':
        _push(
          'Sales Status',
          () => _service.sales(widget.session, locationId: _locationId),
          [
            'sale_number',
            'customer_name',
            'status',
            'grand_total',
            'balance_due',
          ],
        );
        break;
      case 'purchases':
        _push(
          'Purchases',
          () => _service.purchases(widget.session, locationId: _locationId),
          [
            'document_type',
            'document_number',
            'supplier_name',
            'status',
            'grand_total',
            'balance_due',
          ],
        );
        break;
      case 'inventory':
        _push(
          'Inventory',
          () => _service.inventory(widget.session, locationId: _locationId),
          [
            'product_name',
            'sku',
            'location_name',
            'available',
            'status',
            'stock_value',
          ],
        );
        break;
      case 'customers':
        _push(
          'Customer Outstanding',
          () => _service.customerOutstanding(
            widget.session,
            locationId: _locationId,
          ),
          [
            'customer_name',
            'phone',
            'total_outstanding',
            'days_90_plus',
            'status',
          ],
        );
        break;
      case 'suppliers':
        _push(
          'Supplier Outstanding',
          () => _service.supplierOutstanding(
            widget.session,
            locationId: _locationId,
          ),
          [
            'supplier_name',
            'phone',
            'total_outstanding',
            'days_90_plus',
            'status',
          ],
        );
        break;
      case 'stores':
        _push(
          'Store Performance',
          () => _service.storePerformance(widget.session),
          [
            'location_name',
            'net_sales',
            'gross_profit',
            'invoice_count',
            'inventory_value',
            'receivables',
            'payables',
          ],
        );
        break;
    }
  }

  void _push(
    String title,
    Future<List<Map<String, dynamic>>> Function() loader,
    List<String> fields,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DataListPage(
          title: title,
          loader: loader,
          fields: fields,
          currency: widget.session.currencyCode,
        ),
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  final MobileSession session;
  final Future<Map<String, dynamic>> future;
  final String Function(dynamic) money;
  final VoidCallback onRefresh;
  final String? locationId;
  final ValueChanged<String?> onLocation;
  final ValueChanged<String> onOpen;

  const _DashboardTab({
    required this.session,
    required this.future,
    required this.money,
    required this.onRefresh,
    required this.locationId,
    required this.onLocation,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async => onRefresh(),
    child: FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 280),
              Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            ],
          );
        }

        if (s.hasError) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 120),
              ThqErrorState(
                title: 'Could not load dashboard',
                message: 'Pull down to retry.',
              ),
            ],
          );
        }

        final d = s.data ?? {};
        final a = d['attention'] is Map
            ? Map<String, dynamic>.from(d['attention'] as Map)
            : <String, dynamic>{};

        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _DashboardHero(
              businessName: session.businessName,
              netSales: money(d['net_sales']),
              grossProfit: money(d['gross_profit']),
              invoiceCount: '${d['invoice_count'] ?? 0}',
              approvals: '${d['pending_approvals'] ?? 0}',
              onRefresh: onRefresh,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (session.canViewAllLocations) ...[
                    DropdownButtonFormField<String?>(
                      initialValue: locationId,
                      decoration: const InputDecoration(
                        labelText: 'Store scope',
                        prefixIcon: Icon(Icons.store_mall_directory_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All accessible stores'),
                        ),
                        ...session.locations.map(
                          (l) => DropdownMenuItem<String?>(
                            value: l.id,
                            child: Text(l.name),
                          ),
                        ),
                      ],
                      onChanged: onLocation,
                    ),
                    const SizedBox(height: 16),
                  ],
                  const _MobileSectionTitle(
                    title: 'Quick actions',
                    subtitle: 'Open the areas you use most.',
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: 1.08,
                    children: [
                      _QuickActionTile(
                        label: 'Sales',
                        icon: Icons.point_of_sale_rounded,
                        onTap: () => onOpen('sales'),
                      ),
                      _QuickActionTile(
                        label: 'Purchases',
                        icon: Icons.shopping_bag_outlined,
                        onTap: () => onOpen('purchases'),
                      ),
                      _QuickActionTile(
                        label: 'Inventory',
                        icon: Icons.inventory_2_outlined,
                        onTap: () => onOpen('inventory'),
                      ),
                      _QuickActionTile(
                        label: 'Customers',
                        icon: Icons.people_alt_outlined,
                        onTap: () => onOpen('customers'),
                      ),
                      _QuickActionTile(
                        label: 'Suppliers',
                        icon: Icons.local_shipping_outlined,
                        onTap: () => onOpen('suppliers'),
                      ),
                      _QuickActionTile(
                        label: 'Stores',
                        icon: Icons.storefront_outlined,
                        onTap: () => onOpen('stores'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _MobileSectionTitle(
                    title: 'Outstanding',
                    subtitle: 'Current receivable and payable position.',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DueCard(
                          label: 'Customer due',
                          value: money(d['customer_outstanding']),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _DueCard(
                          label: 'Supplier due',
                          value: money(d['supplier_outstanding']),
                          icon: Icons.payments_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _MobileSectionTitle(
                    title: 'Attention',
                    subtitle: 'Items that may need action.',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE9E6F1)),
                    ),
                    child: Column(
                      children: [
                        _AttentionRow(
                          icon: Icons.warning_amber_rounded,
                          label: 'Low stock',
                          value: '${a['low_stock'] ?? 0}',
                        ),
                        const Divider(height: 1, indent: 52, endIndent: 14),
                        _AttentionRow(
                          icon: Icons.remove_shopping_cart_outlined,
                          label: 'Out of stock',
                          value: '${a['out_of_stock'] ?? 0}',
                        ),
                        const Divider(height: 1, indent: 52, endIndent: 14),
                        _AttentionRow(
                          icon: Icons.schedule_rounded,
                          label: 'Overdue receivables',
                          value: money(a['overdue_receivables']),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _DashboardHero extends StatelessWidget {
  final String businessName;
  final String netSales;
  final String grossProfit;
  final String invoiceCount;
  final String approvals;
  final VoidCallback onRefresh;

  const _DashboardHero({
    required this.businessName,
    required this.netSales,
    required this.grossProfit,
    required this.invoiceCount,
    required this.approvals,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: 266 + topInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 216 + topInset,
            padding: EdgeInsets.fromLTRB(18, topInset + 14, 14, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5E50D8), Color(0xFF8D7CF6)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ThqMobileMark(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'THQ BUSINESS',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        businessName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.35,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: onRefresh,
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.13),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE8E4F3)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4E3DA8).withValues(alpha: 0.11),
                    blurRadius: 24,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        'TODAY',
                        style: TextStyle(
                          color: Color(0xFF77717F),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                        ),
                      ),
                      Spacer(),
                      Icon(
                        Icons.auto_graph_rounded,
                        size: 17,
                        color: Color(0xFF6C5CE7),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroMetric(label: 'Net sales', value: netSales),
                      ),
                      const _MetricDivider(),
                      Expanded(
                        child: _HeroMetric(
                          label: 'Gross profit',
                          value: grossProfit,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroMetric(
                          label: 'Invoices',
                          value: invoiceCount,
                        ),
                      ),
                      const _MetricDivider(),
                      Expanded(
                        child: _HeroMetric(
                          label: 'Approvals',
                          value: approvals,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThqMobileMark extends StatelessWidget {
  const _ThqMobileMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    ),
    child: const Text(
      'T',
      style: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF211F27),
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF77717F),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: const Color(0xFFEDEAF4));
}

class _MobileSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _MobileSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF77717F)),
            ),
          ],
        ),
      ),
    ],
  );
}

class _QuickActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9E6F1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 37,
              height: 37,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EDFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFF6C5CE7)),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DueCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DueCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFE9E6F1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: const Color(0xFF6C5CE7)),
        const SizedBox(height: 10),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF77717F),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _AttentionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AttentionRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    child: Row(
      children: [
        Container(
          width: 31,
          height: 31,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4DA),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: const Color(0xFFC88900)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _BusinessTab extends StatelessWidget {
  final ValueChanged<String> open;
  const _BusinessTab({required this.open});
  @override
  Widget build(BuildContext context) {
    final rows = [
      ('sales', 'Sales Status', Icons.point_of_sale),
      ('purchases', 'Purchases', Icons.shopping_cart_outlined),
      ('inventory', 'Inventory', Icons.inventory_2_outlined),
      ('customers', 'Customer Outstanding', Icons.people_outline),
      ('suppliers', 'Supplier Outstanding', Icons.local_shipping_outlined),
    ];
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text('Business', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        ...rows.map(
          (r) => Card(
            child: ListTile(
              leading: Icon(r.$3),
              title: Text(r.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(r.$1),
            ),
          ),
        ),
      ],
    );
  }
}

class _ApprovalsTab extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String Function(dynamic) money;
  const _ApprovalsTab({
    required this.session,
    required this.service,
    required this.money,
  });
  @override
  State<_ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends State<_ApprovalsTab> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.service.approvals(widget.session);
  }

  void _reload() =>
      setState(() => _future = widget.service.approvals(widget.session));
  Future<void> _decide(Map<String, dynamic> row, bool approve) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(
        title: approve ? 'Approve' : 'Reject',
        required: !approve,
      ),
    );
    if (note == null) return;
    await widget.service.decide(
      widget.session,
      type: row['approval_type']?.toString() ?? '',
      id: row['id']?.toString() ?? '',
      approve: approve,
      note: note,
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done)
            return const Center(child: CircularProgressIndicator());
          if (s.hasError)
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(s.error.toString()),
              ),
            );
          final rows = s.data ?? [];
          if (rows.isEmpty)
            return const Center(child: Text('No pending approvals'));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['reference']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(r['summary']?.toString() ?? ''),
                        if (r['location_name'] != null)
                          Text(r['location_name'].toString()),
                        if (r['amount'] != null)
                          Text(widget.money(r['amount'])),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _decide(r, false),
                                child: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _decide(r, true),
                                child: const Text('Approve'),
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
          );
        },
      );
}

class _NoteDialog extends StatefulWidget {
  final String title;
  final bool required;
  const _NoteDialog({required this.title, required this.required});
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final c = TextEditingController();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: c,
      maxLines: 3,
      decoration: InputDecoration(
        labelText: widget.required ? 'Reason required' : 'Note',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          (!widget.required || c.text.trim().isNotEmpty) ? c.text.trim() : null,
        ),
        child: Text(widget.title),
      ),
    ],
  );
}

class _MoreTab extends StatelessWidget {
  final MobileSession session;
  final MobileClientService service;
  final String Function(dynamic) money;
  final ValueChanged<String> onOpen;
  final Future<void> Function() onLogout;
  const _MoreTab({
    required this.session,
    required this.service,
    required this.money,
    required this.onOpen,
    required this.onLogout,
  });
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(10),
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.storefront),
          title: const Text('Store Performance'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpen('stores'),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.analytics_outlined),
          title: const Text('Reports'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _ReportsPage(
                session: session,
                service: service,
                money: money,
              ),
            ),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: const Text('Customer Payment'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _CustomerPaymentPage(
                session: session,
                service: service,
                money: money,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.phone_android),
          title: Text(session.deviceName),
          subtitle: Text('${session.deviceCode} • ${session.locationName}'),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => onLogout(),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Deactivate this phone'),
          onTap: () async {
            await MobileAuthService().signOut();
            await DeviceInstallationService().clearActivation();
            if (context.mounted)
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MobileEntryScreen()),
                (_) => false,
              );
          },
        ),
      ),
    ],
  );
}

class _DataListPage extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function() loader;
  final List<String> fields;
  final String currency;

  const _DataListPage({
    required this.title,
    required this.loader,
    required this.fields,
    required this.currency,
  });

  @override
  State<_DataListPage> createState() => _DataListPageState();
}

class _DataListPageState extends State<_DataListPage> {
  late Future<List<Map<String, dynamic>>> future;

  @override
  void initState() {
    super.initState();
    future = widget.loader();
  }

  String label(String key) => key
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }

          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: () async {
              final next = widget.loader();
              setState(() => future = next);
              await next;
            },
            child: rows.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 200),
                      Center(child: Text('No data')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: widget.fields
                                .where((key) => row[key] != null)
                                .map(
                                  (key) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            label(key),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            row[key].toString(),
                                            style: TextStyle(
                                              fontWeight:
                                                  key.contains('name') ||
                                                      key.contains('number')
                                                  ? FontWeight.w600
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _ReportsPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String Function(dynamic) money;
  const _ReportsPage({
    required this.session,
    required this.service,
    required this.money,
  });
  @override
  State<_ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<_ReportsPage> {
  late DateTime from;
  late Future<Map<String, dynamic>> f;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    from = DateTime(now.year, now.month, 1);
    f = widget.service.report(widget.session, from: from, to: now);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reports')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text(s.error.toString()));
        final d = s.data ?? {};
        return ListView(
          padding: const EdgeInsets.all(10),
          children: [
            Text(
              'Month to date',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            ...d.entries.map(
              (e) => Card(
                child: ListTile(
                  title: Text(e.key.replaceAll('_', ' ')),
                  trailing: Text(e.value.toString()),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _CustomerPaymentPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String Function(dynamic) money;
  const _CustomerPaymentPage({
    required this.session,
    required this.service,
    required this.money,
  });
  @override
  State<_CustomerPaymentPage> createState() => _CustomerPaymentPageState();
}

class _CustomerPaymentPageState extends State<_CustomerPaymentPage> {
  late Future<List<Map<String, dynamic>>> f;
  String? customerId;
  final amount = TextEditingController();
  final reference = TextEditingController();
  String method = 'cash';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    f = widget.service.customerOutstanding(widget.session);
  }

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final v = double.tryParse(amount.text.trim()) ?? 0;
    if (customerId == null || v <= 0) return;
    setState(() => busy = true);
    try {
      await widget.service.receiveCustomerPayment(
        widget.session,
        customerId: customerId!,
        amount: v,
        method: method,
        reference: reference.text,
      );
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('Customer payment recorded.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ThqNotify.showSnackBar(context, SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customer Payment')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: f,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        final rows = s.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(10),
          children: [
            DropdownButtonFormField<String>(
              initialValue: customerId,
              decoration: const InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(),
              ),
              items: rows
                  .map(
                    (r) => DropdownMenuItem(
                      value: r['customer_id']?.toString() ?? '',
                      child: Text(
                        '${r['customer_name']} • ${widget.money(r['total_outstanding'])}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => customerId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(
                labelText: 'Method',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => method = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Reference',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Saving...' : 'Receive Payment'),
            ),
          ],
        );
      },
    ),
  );
}
