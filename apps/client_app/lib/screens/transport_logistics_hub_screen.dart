import 'package:flutter/material.dart';
import 'package:thq_logistics/thq_logistics.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/transport_trip_hub_service.dart';
import 'logistics_screen.dart';
import 'transport_service_screen.dart';

class TransportLogisticsHubScreen extends StatefulWidget {
  final ClientSession session;

  const TransportLogisticsHubScreen({super.key, required this.session});

  @override
  State<TransportLogisticsHubScreen> createState() =>
      _TransportLogisticsHubScreenState();
}

class _TransportLogisticsHubScreenState
    extends State<TransportLogisticsHubScreen> {
  final TransportTripHubService _tripHub = TransportTripHubService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  String _kind = 'all';
  List<Map<String, dynamic>> _rows = const [];

  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);

  bool get _hasOperations =>
      widget.session.hasModule('logistics_operations') ||
      widget.session.hasModule('vehicle_logistics');

  bool get _hasCustomerTransport =>
      widget.session.hasModule('transport_service');

  bool get _canCreate =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('logistics_operations.create') ||
      widget.session.hasPermission('logistics_operations.manage') ||
      widget.session.hasPermission('transport_service.create') ||
      widget.session.hasPermission('transport_service.manage') ||
      widget.session.hasPermission('inventory.transfer') ||
      widget.session.hasPermission('inventory.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _tripHub.list(
        tenantId: _tenantId,
        locationId: _locationId,
        kind: _kind == 'all' ? null : _kind,
        query: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _clean(Object error) => error
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  String _kindLabel(String kind) => switch (kind) {
    'operational' => 'Operational',
    'stock_transfer' => 'Stock Transfer',
    'customer_transport' => 'Customer Transport',
    _ => kind.replaceAll('_', ' '),
  };

  IconData _kindIcon(String kind) => switch (kind) {
    'operational' => Icons.route_outlined,
    'stock_transfer' => Icons.swap_horiz_rounded,
    'customer_transport' => Icons.receipt_long_outlined,
    _ => Icons.local_shipping_outlined,
  };

  Future<void> _newTrip() async {
    final mode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Trip'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.route_outlined)),
                title: const Text('Internal / Operational'),
                subtitle: const Text(
                  'Physical movement only. No inventory posting and no GST.',
                ),
                enabled: _hasOperations,
                onTap: !_hasOperations
                    ? null
                    : () => Navigator.pop(dialogContext, 'operational'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.swap_horiz_rounded),
                ),
                title: const Text('Stock Transfer'),
                subtitle: const Text(
                  'Inventory-authoritative stock movement. The trip itself '
                  'does not post GST.',
                ),
                onTap: () => Navigator.pop(dialogContext, 'stock_transfer'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.receipt_long_outlined),
                ),
                title: const Text('Customer Transport'),
                subtitle: const Text(
                  'Commercial transport job. Sale/GST/accounting happen only '
                  'when the job is billed.',
                ),
                enabled: _hasCustomerTransport,
                onTap: !_hasCustomerTransport
                    ? null
                    : () => Navigator.pop(dialogContext, 'customer_transport'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (!mounted || mode == null) return;

    if (mode == 'operational') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('New Operational Trip')),
            body: LogisticsOperationsWorkspace(
              tenantId: _tenantId,
              locationId: _locationId,
              startInCreate: true,
            ),
          ),
        ),
      );
    } else if (mode == 'stock_transfer') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LogisticsScreen(session: widget.session),
        ),
      );
    } else if (mode == 'customer_transport') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('New Customer Transport')),
            body: TransportServiceScreen(
              session: widget.session,
              startInCreate: true,
            ),
          ),
        ),
      );
    }

    if (mounted) await _load();
  }

  Future<void> _openStockTransferExecution() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LogisticsScreen(session: widget.session),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openControlCenter() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VehicleLogisticsReportWorkspace(
          tenantId: _tenantId,
          locationId: _locationId,
          legacyTransferBuilder: (_) =>
              LogisticsScreen(session: widget.session),
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openRow(Map<String, dynamic> row) async {
    final kind = row['trip_kind']?.toString() ?? '';

    if (kind == 'stock_transfer') {
      final tripId = row['stock_trip_id']?.toString();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              LogisticsScreen(session: widget.session, initialTripId: tripId),
        ),
      );
    } else if (kind == 'customer_transport') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Customer Transport')),
            body: TransportServiceScreen(session: widget.session),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Logistics Operations')),
            body: LogisticsOperationsWorkspace(
              tenantId: _tenantId,
              locationId: _locationId,
            ),
          ),
        ),
      );
    }

    if (mounted) await _load();
  }

  Widget _metric(String label, int value, IconData icon) {
    return Card(
      child: SizedBox(
        width: 150,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(label, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tripsTab() {
    final operational = _rows
        .where((row) => row['trip_kind'] == 'operational')
        .length;
    final stock = _rows
        .where((row) => row['trip_kind'] == 'stock_transfer')
        .length;
    final customer = _rows
        .where((row) => row['trip_kind'] == 'customer_transport')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric('Visible trips', _rows.length, Icons.route_outlined),
            _metric('Operational', operational, Icons.alt_route_outlined),
            _metric('Stock transfer', stock, Icons.swap_horiz_rounded),
            _metric('Customer', customer, Icons.receipt_long_outlined),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final search = TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search trip, source reference, vehicle or route',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                border: const OutlineInputBorder(),
              ),
            );

            final filters = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in const [
                  ('all', 'All'),
                  ('operational', 'Operational'),
                  ('stock_transfer', 'Stock Transfer'),
                  ('customer_transport', 'Customer'),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected: _kind == entry.$1,
                    onSelected: (_) {
                      setState(() => _kind = entry.$1);
                      _load();
                    },
                  ),
              ],
            );

            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [search, const SizedBox(height: 8), filters],
              );
            }

            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 10),
                filters,
              ],
            );
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_error!),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
              ? const Center(
                  child: Text('No transport or logistics trips found.'),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final kind =
                          row['trip_kind']?.toString() ?? 'operational';
                      final status =
                          row['source_status']?.toString() ?? 'planned';
                      final route =
                          [
                                row['from_label']?.toString(),
                                row['to_label']?.toString(),
                              ]
                              .where(
                                (value) => value != null && value.isNotEmpty,
                              )
                              .join(' -> ');
                      final source = row['source_reference']?.toString() ?? '-';
                      final vehicle = row['vehicle_registration']?.toString();

                      return Card(
                        child: ListTile(
                          onTap: () => _openRow(row),
                          leading: CircleAvatar(child: Icon(_kindIcon(kind))),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row['trip_number']?.toString() ?? source,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  status.replaceAll('_', ' ').toUpperCase(),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            [
                              _kindLabel(kind),
                              source,
                              if (route.isNotEmpty) route,
                              if (vehicle != null && vehicle.isNotEmpty)
                                vehicle,
                              if (row['sale_id'] != null) 'Billed',
                            ].join(' | '),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _operationsTab() {
    if (!_hasOperations) {
      return const Center(
        child: Text('Logistics Operations is not enabled for this business.'),
      );
    }

    return LogisticsOperationsWorkspace(
      tenantId: _tenantId,
      locationId: _locationId,
    );
  }

  Widget _customerJobsTab() {
    if (!_hasCustomerTransport) {
      return const Center(
        child: Text('Transport Service is not enabled for this business.'),
      );
    }

    return TransportServiceScreen(session: widget.session);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: DefaultTabController(
        length: 3,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Transport & Logistics',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'One control center for physical trips, Stock Transfer '
                        'movement and customer transport billing.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );

                  final actions = Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _openStockTransferExecution,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text('Transfer Execution'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openControlCenter,
                        icon: const Icon(
                          Icons.monitor_heart_outlined,
                          size: 18,
                        ),
                        label: const Text('Control Center'),
                      ),
                      IconButton(
                        tooltip: 'Refresh trips',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      if (_canCreate)
                        FilledButton.icon(
                          onPressed: _newTrip,
                          icon: const Icon(Icons.add_road, size: 18),
                          label: const Text('New Trip'),
                        ),
                    ],
                  );

                  if (constraints.maxWidth < 920) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 9), actions],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(icon: Icon(Icons.route_outlined), text: 'Trips'),
                  Tab(icon: Icon(Icons.alt_route_outlined), text: 'Operations'),
                  Tab(
                    icon: Icon(Icons.receipt_long_outlined),
                    text: 'Customer Jobs',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    Material(color: Colors.transparent, child: _tripsTab()),
                    Material(
                      color: Colors.transparent,
                      child: _operationsTab(),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: _customerJobsTab(),
                    ),
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
