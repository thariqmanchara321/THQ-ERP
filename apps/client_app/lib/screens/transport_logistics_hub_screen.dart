import 'package:thq_ui/thq_ui.dart';
import 'package:flutter/material.dart';
import 'package:thq_logistics/thq_logistics.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/transport_trip_hub_service.dart';
import 'logistics_screen.dart';
import 'transport_service_screen.dart';
import 'aggregate_loads_screen.dart';
import 'vehicle_fleet_screen.dart';
import 'material_load_reports_screen.dart';

class TransportLogisticsHubScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final ClientSession session;
  final String? initialVehicleId;
  final String? initialMaterialLoadId;

  const TransportLogisticsHubScreen({
    super.key,
    this.onBack,
    required this.session,
    this.initialVehicleId,
    this.initialMaterialLoadId,
  });

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
  String? _vehicleId;
  String? _materialLoadId;

  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);

  bool get _hasOperations =>
      widget.session.hasModule('logistics_operations') ||
      widget.session.hasModule('vehicle_logistics');

  bool get _hasCustomerTransport =>
      widget.session.hasModule('transport_service');
  bool get _hasMaterialYard =>
      widget.session.hasModule('aggregate_yard') &&
      (widget.session.hasRole('owner') ||
          widget.session.hasPermission('aggregate_yard.view') ||
          widget.session.hasPermission('aggregate_yard.manage'));

  bool get _canCreate =>
      widget.session.hasRole('owner') ||
      (_hasMaterialYard &&
          widget.session.hasPermission('aggregate_yard.manage')) ||
      widget.session.hasPermission('logistics_operations.create') ||
      widget.session.hasPermission('logistics_operations.manage') ||
      widget.session.hasPermission('transport_service.create') ||
      widget.session.hasPermission('transport_service.manage') ||
      widget.session.hasPermission('inventory.transfer') ||
      widget.session.hasPermission('inventory.manage');

  @override
  void initState() {
    super.initState();
    _vehicleId = widget.initialVehicleId;
    _materialLoadId = widget.initialMaterialLoadId;
    LocationScopeService.selectedLocationId.addListener(_locationChanged);
    _load();
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_locationChanged);
    _search.dispose();
    super.dispose();
  }

  void _locationChanged() => _load();

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
        vehicleId: _vehicleId,
        materialLoadId: _materialLoadId,
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
    'material_load' => 'Material Load',
    _ => kind.replaceAll('_', ' '),
  };

  IconData _kindIcon(String kind) => switch (kind) {
    'operational' => Icons.route_outlined,
    'stock_transfer' => Icons.swap_horiz_rounded,
    'customer_transport' => Icons.receipt_long_outlined,
    'material_load' => Icons.local_shipping_outlined,
    _ => Icons.local_shipping_outlined,
  };

  Future<void> _newTrip() async {
    final mode = await showThqDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Trip'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasMaterialYard &&
                  (widget.session.hasRole('owner') ||
                      widget.session.hasPermission(
                        'aggregate_yard.manage',
                      ))) ...[
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.local_shipping_outlined),
                  ),
                  title: const Text('Material Load'),
                  subtitle: const Text(
                    'Receive or dispatch material through the Load Register.',
                  ),
                  onTap: () => Navigator.pop(dialogContext, 'material_load'),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.route_outlined)),
                title: const Text('Quick Operational Trip'),
                subtitle: const Text(
                  'Track a vehicle movement without extra accounting steps.',
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

    if (mode == 'material_load') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AggregateLoadsScreen(
            session: widget.session,
            initialCreateDirection: 'outbound',
          ),
        ),
      );
    } else if (mode == 'operational') {
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

  Future<void> _openFullWorkflow(Map<String, dynamic> row) async {
    final kind = row['trip_kind']?.toString() ?? '';

    if (kind == 'material_load') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AggregateLoadsScreen(
            session: widget.session,
            initialLoadId: row['material_load_id']?.toString(),
          ),
        ),
      );
    } else if (kind == 'stock_transfer') {
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
            body: TransportServiceScreen(
              session: widget.session,
              initialJobId: row['service_job_id']?.toString(),
            ),
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
              initialOperationId: row['logistics_operation_id']?.toString(),
            ),
          ),
        ),
      );
    }

    if (mounted) await _load();
  }

  Future<void> _openRow(Map<String, dynamic> row) async {
    final kind = row['trip_kind']?.toString() ?? 'operational';
    final status = row['source_status']?.toString() ?? 'planned';
    final source = row['source_reference']?.toString() ?? '-';
    final vehicle = row['vehicle_registration']?.toString();
    final route = [
      row['from_label']?.toString(),
      row['to_label']?.toString(),
    ].where((value) => value != null && value.isNotEmpty).join(' -> ');
    final date = row['source_date']?.toString() ?? '-';
    final billed = row['sale_id'] != null;

    final openFull = await showThqDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(row['trip_number']?.toString() ?? source),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: Icon(_kindIcon(kind)),
                title: const Text('Type'),
                trailing: Text(_kindLabel(kind)),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Status'),
                trailing: Text(status.replaceAll('_', ' ').toUpperCase()),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.tag_outlined),
                title: const Text('Reference'),
                trailing: Text(source),
              ),
              if (vehicle != null && vehicle.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: const Text('Vehicle'),
                  trailing: Text(vehicle),
                ),
              if (route.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.alt_route_outlined),
                  title: const Text('Route'),
                  subtitle: Text(route),
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Date'),
                trailing: Text(date),
              ),
              if (kind == 'material_load')
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(
                    '${row['product_name'] ?? 'Material'} • ${row['quantity']} ${row['unit_code']}',
                  ),
                  subtitle: Text(
                    '${row['direction'] == 'outbound' ? 'Dispatch' : 'Inward'} • ${billed || row['purchase_id'] != null ? 'Invoice linked' : 'Invoice pending'}',
                  ),
                ),
              if (kind == 'customer_transport')
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Billing'),
                  trailing: Text(billed ? 'Billed' : 'Not billed'),
                ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'This summary is the normal view. Open the full workflow '
                  'only for execution, evidence or advanced controls.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Open Full Workflow'),
          ),
        ],
      ),
    );

    if (openFull == true && mounted) {
      await _openFullWorkflow(row);
    }
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
                        fontWeight: FontWeight.w600,
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
                for (final entry in [
                  ('all', 'All'),
                  ('operational', 'Operational'),
                  ('stock_transfer', 'Stock Transfer'),
                  ('customer_transport', 'Customer'),
                  if (_hasMaterialYard) ('material_load', 'Material Loads'),
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
        if (_vehicleId != null || _materialLoadId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _vehicleId = null;
                  _materialLoadId = null;
                  _kind = 'all';
                  _search.clear();
                });
                _load();
              },
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: Text(
                _vehicleId != null
                    ? 'Vehicle trips • Show all trips'
                    : 'Linked material load • Show all trips',
              ),
            ),
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
                                  style: const TextStyle(fontSize: 11),
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
      color: scheme.surface,
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
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Simple trip list first. Open advanced execution only when '
                        'you actually need it.',
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
                      if (widget.onBack != null ||
                          Navigator.of(context).canPop())
                        OutlinedButton.icon(
                          onPressed:
                              widget.onBack ??
                              () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => VehicleFleetScreen(
                                session: widget.session,
                                initialVehicleId: _vehicleId,
                              ),
                            ),
                          );
                          if (mounted) await _load();
                        },
                        icon: const Icon(
                          Icons.local_shipping_outlined,
                          size: 18,
                        ),
                        label: const Text('Vehicles'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openStockTransferExecution,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text('Stock Transfer'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openControlCenter,
                        icon: const Icon(
                          Icons.monitor_heart_outlined,
                          size: 18,
                        ),
                        label: const Text('Reports'),
                      ),
                      if (widget.session.hasModule('aggregate_yard'))
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MaterialLoadReportsScreen(
                                session: widget.session,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.assessment_outlined),
                          label: const Text('Load costs & deliveries'),
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
                    Material(color: scheme.surface, child: _tripsTab()),
                    Material(color: scheme.surface, child: _operationsTab()),
                    Material(color: scheme.surface, child: _customerJobsTab()),
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
