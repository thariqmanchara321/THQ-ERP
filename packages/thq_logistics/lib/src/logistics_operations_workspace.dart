import 'package:flutter/material.dart';

import 'logistics_api.dart';

class LogisticsOperationsWorkspace extends StatefulWidget {
  final String tenantId;
  final String? locationId;
  final bool startInCreate;

  const LogisticsOperationsWorkspace({
    super.key,
    required this.tenantId,
    this.locationId,
    this.startInCreate = false,
  });

  @override
  State<LogisticsOperationsWorkspace> createState() =>
      _LogisticsOperationsWorkspaceState();
}

class _LogisticsOperationsWorkspaceState
    extends State<LogisticsOperationsWorkspace> {
  final api = ThqLogisticsApi();
  final search = TextEditingController();
  bool loading = true;
  String? error;
  String status = 'all';
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> dashboard = {};

  @override
  void initState() {
    super.initState();
    bootstrap();
  }

  Future<void> bootstrap() async {
    await load();
    if (!mounted || !widget.startInCreate || error != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) newOperation();
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  String clean(Object value) => value
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final now = DateTime.now();
      final result = await Future.wait([
        api.operations(
          tenantId: widget.tenantId,
          locationId: widget.locationId,
          status: status == 'all' ? null : status,
          query: search.text.trim().isEmpty ? null : search.text.trim(),
        ),
        api.dashboard(tenantId: widget.tenantId, from: now, to: now),
      ]);
      if (!mounted) return;
      setState(() {
        rows = result[0] as List<Map<String, dynamic>>;
        dashboard = result[1] as Map<String, dynamic>;
      });
    } catch (e) {
      if (mounted) setState(() => error = clean(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> newOperation() async {
    final title = TextEditingController();
    final coordinator = TextEditingController();
    final primary = TextEditingController(text: 'kg');
    final secondary = TextEditingController();
    final notes = TextEditingController();
    var purpose = 'delivery';
    var day = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Logistics Operation'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: day,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (picked != null) setLocal(() => day = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Operation date',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(shortDate(day)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: purpose,
                    decoration: const InputDecoration(
                      labelText: 'Purpose',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'delivery',
                        child: Text('Delivery'),
                      ),
                      DropdownMenuItem(
                        value: 'collection',
                        child: Text('Collection'),
                      ),
                      DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                      DropdownMenuItem(
                        value: 'transfer',
                        child: Text('Stock transfer'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) =>
                        setLocal(() => purpose = value ?? 'delivery'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Title / reference',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: primary,
                          decoration: const InputDecoration(
                            labelText: 'Primary unit *',
                            hintText: 'kg',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: secondary,
                          decoration: const InputDecoration(
                            labelText: 'Secondary unit (optional)',
                            hintText: 'birds / boxes / units',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: coordinator,
                    decoration: const InputDecoration(
                      labelText: 'Coordinator',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (primary.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && mounted) {
      try {
        final result = await api.saveOperation(
          tenantId: widget.tenantId,
          operationDate: day,
          baseLocationId: widget.locationId,
          title: title.text.trim(),
          purpose: purpose,
          primaryUnit: primary.text.trim(),
          secondaryUnit: nullIfEmpty(secondary.text),
          coordinator: coordinator.text.trim(),
          notes: notes.text.trim(),
        );
        await load();
        if (!mounted) return;
        final id = result['id']?.toString();
        if (id != null && id.isNotEmpty) await openOperation(id);
      } catch (e) {
        message(clean(e));
      }
    }

    for (final c in [title, coordinator, primary, secondary, notes]) {
      c.dispose();
    }
  }

  Future<void> openOperation(String id) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LogisticsOperationDialog(
        api: api,
        tenantId: widget.tenantId,
        locationId: widget.locationId,
        operationId: id,
        readOnly: false,
      ),
    );
    if (mounted) await load();
  }

  Future<void> openMasters() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LogisticsMastersPage(
          api: api,
          tenantId: widget.tenantId,
          locationId: widget.locationId,
        ),
      ),
    );
    if (mounted) await load();
  }

  Widget metric(String label, dynamic value, IconData icon) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 7),
            Text(
              '${value ?? 0}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );

  Widget operationCard(Map<String, dynamic> row) {
    final unit = row['primary_unit']?.toString() ?? 'kg';
    return Card(
      child: ListTile(
        onTap: () => openOperation(row['id'].toString()),
        leading: const CircleAvatar(child: Icon(Icons.route_outlined)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                row['operation_number']?.toString() ?? '-',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            statusChip(row['status']?.toString() ?? 'planned'),
          ],
        ),
        subtitle: Text(
          '${row['purpose'] ?? '-'} | ${row['run_count'] ?? 0} run(s) | ${row['stop_count'] ?? 0} stop(s)\n'
          'Pickup ${qty(row['pickup_primary_qty'])} $unit | '
          'Delivery ${qty(row['delivery_primary_qty'])} $unit | '
          'Return ${qty(row['returned_primary_qty'])} $unit | '
          'Variance ${qty(row['variance_primary_qty'])} $unit',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Logistics Operations',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Execute multi-vehicle, multi-run pickup and delivery operations with live load reconciliation.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: openMasters,
                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: const Text('Fleet & Masters'),
                  ),
                  OutlinedButton.icon(
                    onPressed: load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                  FilledButton.icon(
                    onPressed: newOperation,
                    icon: const Icon(Icons.add_road, size: 18),
                    label: const Text('New Operation'),
                  ),
                ],
              );
              if (constraints.maxWidth < 850) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 10), actions],
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
          if (error != null) ...[
            const SizedBox(height: 10),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              metric(
                'Active operations',
                dashboard['operations_active'],
                Icons.route_outlined,
              ),
              metric(
                'Trucks on road',
                dashboard['runs_on_road'],
                Icons.local_shipping_outlined,
              ),
              metric(
                'Pickup today',
                qty(dashboard['pickup_primary_qty']),
                Icons.call_received_outlined,
              ),
              metric(
                'Delivered today',
                qty(dashboard['delivery_primary_qty']),
                Icons.call_made_outlined,
              ),
              metric(
                'Variance',
                qty(dashboard['variance_primary_qty']),
                Icons.warning_amber_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final searchBox = TextField(
                controller: search,
                onSubmitted: (_) => load(),
                decoration: InputDecoration(
                  hintText: 'Search operation, truck, driver or reference',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: load,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              );
              final statusFilter = DropdownButtonFormField<String>(
                initialValue: status,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'planned', child: Text('Planned')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Text('Completed'),
                  ),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  DropdownMenuItem(
                    value: 'cancelled',
                    child: Text('Cancelled'),
                  ),
                ],
                onChanged: (value) {
                  setState(() => status = value ?? 'all');
                  load();
                },
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  children: [
                    searchBox,
                    const SizedBox(height: 8),
                    statusFilter,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: searchBox),
                  const SizedBox(width: 8),
                  SizedBox(width: 170, child: statusFilter),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.route_outlined, size: 34, color: scheme.primary),
                    const SizedBox(height: 8),
                    const Text(
                      'No logistics operations found.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create an operation, then add one or more vehicle runs and ordered pickup/delivery stops.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...rows.map(operationCard),
        ],
      ),
    );
  }
}

class LogisticsOperationDialog extends StatefulWidget {
  final ThqLogisticsApi api;
  final String tenantId;
  final String? locationId;
  final String operationId;
  final bool readOnly;

  const LogisticsOperationDialog({
    super.key,
    required this.api,
    required this.tenantId,
    required this.locationId,
    required this.operationId,
    required this.readOnly,
  });

  @override
  State<LogisticsOperationDialog> createState() =>
      _LogisticsOperationDialogState();
}

class _LogisticsOperationDialogState extends State<LogisticsOperationDialog> {
  bool loading = true;
  bool working = false;
  String? error;
  Map<String, dynamic> detail = {};
  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> drivers = [];
  List<Map<String, dynamic>> destinations = [];

  Map<String, dynamic> get operation =>
      Map<String, dynamic>.from((detail['operation'] as Map?) ?? const {});
  List<Map<String, dynamic>> get runs => ((detail['runs'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  List<Map<String, dynamic>> get events =>
      ((detail['events'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  @override
  void initState() {
    super.initState();
    load();
  }

  String clean(Object value) => value
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait([
        widget.api.detail(
          tenantId: widget.tenantId,
          operationId: widget.operationId,
        ),
        widget.api.vehicles(
          tenantId: widget.tenantId,
          locationId: widget.locationId,
        ),
        widget.api.drivers(widget.tenantId),
        widget.api.destinations(widget.tenantId),
      ]);
      if (!mounted) return;
      setState(() {
        detail = result[0] as Map<String, dynamic>;
        vehicles = result[1] as List<Map<String, dynamic>>;
        drivers = result[2] as List<Map<String, dynamic>>;
        destinations = result[3] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) setState(() => error = clean(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> runAction(Future<void> Function() action) async {
    if (working) return;
    setState(() => working = true);
    try {
      await action();
      await load();
    } catch (e) {
      message(clean(e));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> addRun() async {
    String? vehicleId = vehicles.where((v) => v['active'] != false).isEmpty
        ? null
        : vehicles.firstWhere((v) => v['active'] != false)['id']?.toString();
    String? driverId = drivers.where((d) => d['active'] != false).isEmpty
        ? null
        : drivers.firstWhere((d) => d['active'] != false)['id']?.toString();
    final manualDriver = TextEditingController();
    final phone = TextEditingController();
    final primary = TextEditingController(text: '0');
    final secondary = TextEditingController();
    final notes = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add Vehicle Run'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: vehicleId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Unassigned vehicle'),
                      ),
                      ...vehicles
                          .where((v) => v['active'] != false)
                          .map(
                            (v) => DropdownMenuItem<String?>(
                              value: v['id']?.toString(),
                              child: Text(
                                '${v['registration_number'] ?? '-'} | ${v['make_model'] ?? v['vehicle_type'] ?? ''}',
                              ),
                            ),
                          ),
                    ],
                    onChanged: (value) => setLocal(() => vehicleId = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: driverId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Driver',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Manual / no saved driver'),
                      ),
                      ...drivers
                          .where((d) => d['active'] != false)
                          .map(
                            (d) => DropdownMenuItem<String?>(
                              value: d['id']?.toString(),
                              child: Text(
                                '${d['name'] ?? '-'} | ${d['phone'] ?? ''}',
                              ),
                            ),
                          ),
                    ],
                    onChanged: (value) => setLocal(() => driverId = value),
                  ),
                  if (driverId == null) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: manualDriver,
                      decoration: const InputDecoration(
                        labelText: 'Driver name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phone,
                      decoration: const InputDecoration(
                        labelText: 'Driver phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: primary,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                'Starting ${operation['primary_unit'] ?? 'kg'}',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      if (operation['secondary_unit'] != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: secondary,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Starting ${operation['secondary_unit']}',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Run notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add Run'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await runAction(() async {
        await widget.api.saveRun(
          tenantId: widget.tenantId,
          operationId: widget.operationId,
          vehicleId: vehicleId,
          driverId: driverId,
          driverName: manualDriver.text.trim(),
          driverPhone: phone.text.trim(),
          startingPrimary: number(primary.text),
          startingSecondary: optionalNumber(secondary.text),
          notes: notes.text.trim(),
        );
      });
    }
    for (final c in [manualDriver, phone, primary, secondary, notes])
      c.dispose();
  }

  Future<void> addStop(Map<String, dynamic> run) async {
    var action = 'delivery';
    String? destinationId =
        destinations.where((d) => d['active'] != false).isEmpty
        ? null
        : destinations
              .firstWhere((d) => d['active'] != false)['id']
              ?.toString();
    final manualDestination = TextEditingController();
    final pickup = TextEditingController(text: '0');
    final delivery = TextEditingController(text: '0');
    final pickup2 = TextEditingController();
    final delivery2 = TextEditingController();
    final docType = TextEditingController();
    final docRef = TextEditingController();
    final note = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Add Stop - Run ${run['run_no'] ?? ''}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: action,
                    decoration: const InputDecoration(
                      labelText: 'Action',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
                      DropdownMenuItem(
                        value: 'delivery',
                        child: Text('Delivery'),
                      ),
                      DropdownMenuItem(
                        value: 'pickup_delivery',
                        child: Text('Pickup + Delivery'),
                      ),
                      DropdownMenuItem(value: 'return', child: Text('Return')),
                      DropdownMenuItem(
                        value: 'waypoint',
                        child: Text('Waypoint'),
                      ),
                    ],
                    onChanged: (value) =>
                        setLocal(() => action = value ?? 'delivery'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: destinationId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Destination',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Manual destination'),
                      ),
                      ...destinations
                          .where((d) => d['active'] != false)
                          .map(
                            (d) => DropdownMenuItem<String?>(
                              value: d['id']?.toString(),
                              child: Text(
                                '${d['name'] ?? '-'} | ${d['destination_type'] ?? ''}',
                              ),
                            ),
                          ),
                    ],
                    onChanged: (value) => setLocal(() => destinationId = value),
                  ),
                  if (destinationId == null) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: manualDestination,
                      decoration: const InputDecoration(
                        labelText: 'Destination name *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pickup,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                'Planned pickup (${operation['primary_unit'] ?? 'kg'})',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: delivery,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                'Planned delivery (${operation['primary_unit'] ?? 'kg'})',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (operation['secondary_unit'] != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pickup2,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Pickup (${operation['secondary_unit']})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: delivery2,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Delivery (${operation['secondary_unit']})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: docType,
                          decoration: const InputDecoration(
                            labelText: 'Linked document type (optional)',
                            hintText: 'sale / purchase / stock_transfer',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: docRef,
                          decoration: const InputDecoration(
                            labelText: 'Document reference',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Stop notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (destinationId != null ||
                    manualDestination.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Add Stop'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await runAction(() async {
        await widget.api.saveStop(
          tenantId: widget.tenantId,
          runId: run['id'].toString(),
          actionType: action,
          destinationId: destinationId,
          destinationName: manualDestination.text.trim(),
          linkedDocumentType: nullIfEmpty(docType.text),
          linkedDocumentReference: nullIfEmpty(docRef.text),
          plannedPickupPrimary: number(pickup.text),
          plannedDeliveryPrimary: number(delivery.text),
          plannedPickupSecondary: optionalNumber(pickup2.text),
          plannedDeliverySecondary: optionalNumber(delivery2.text),
          note: note.text.trim(),
        );
      });
    }
    for (final c in [
      manualDestination,
      pickup,
      delivery,
      pickup2,
      delivery2,
      docType,
      docRef,
      note,
    ])
      c.dispose();
  }

  Future<void> completeStop(Map<String, dynamic> stop) async {
    final pickup = TextEditingController(
      text: '${stop['planned_pickup_primary_qty'] ?? 0}',
    );
    final delivery = TextEditingController(
      text: '${stop['planned_delivery_primary_qty'] ?? 0}',
    );
    final pickup2 = TextEditingController(
      text: stop['planned_pickup_secondary_qty']?.toString() ?? '',
    );
    final delivery2 = TextEditingController(
      text: stop['planned_delivery_secondary_qty']?.toString() ?? '',
    );
    final variance = TextEditingController(text: '0');
    final variance2 = TextEditingController();
    final receiver = TextEditingController();
    final note = TextEditingController();
    String? varianceReason;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(
            'Complete - ${stop['destination_name_snapshot'] ?? 'Stop'}',
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pickup,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                'Actual pickup (${operation['primary_unit'] ?? 'kg'})',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: delivery,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText:
                                'Actual delivery (${operation['primary_unit'] ?? 'kg'})',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (operation['secondary_unit'] != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pickup2,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Pickup (${operation['secondary_unit']})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: delivery2,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Delivery (${operation['secondary_unit']})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: variance,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          'Variance / loss (${operation['primary_unit'] ?? 'kg'})',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: varianceReason,
                    decoration: const InputDecoration(
                      labelText: 'Variance reason',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No variance'),
                      ),
                      DropdownMenuItem(
                        value: 'mortality',
                        child: Text('Mortality'),
                      ),
                      DropdownMenuItem(
                        value: 'shortage',
                        child: Text('Shortage'),
                      ),
                      DropdownMenuItem(value: 'damage', child: Text('Damage')),
                      DropdownMenuItem(
                        value: 'weight_variance',
                        child: Text('Weight variance'),
                      ),
                      DropdownMenuItem(
                        value: 'rejected',
                        child: Text('Rejected'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) =>
                        setLocal(() => varianceReason = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: receiver,
                    decoration: const InputDecoration(
                      labelText: 'Receiver / contact',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Completion note',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (number(variance.text) == 0 || varianceReason != null) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Complete Stop'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await runAction(() async {
        await widget.api.completeStop(
          tenantId: widget.tenantId,
          stopId: stop['id'].toString(),
          pickupPrimary: number(pickup.text),
          deliveryPrimary: number(delivery.text),
          pickupSecondary: optionalNumber(pickup2.text),
          deliverySecondary: optionalNumber(delivery2.text),
          variancePrimary: number(variance.text),
          varianceSecondary: optionalNumber(variance2.text),
          varianceReason: number(variance.text) > 0 ? varianceReason : null,
          receiver: receiver.text.trim(),
          note: note.text.trim(),
        );
      });
    }
    for (final c in [
      pickup,
      delivery,
      pickup2,
      delivery2,
      variance,
      variance2,
      receiver,
      note,
    ])
      c.dispose();
  }

  Future<void> setRunStatus(Map<String, dynamic> run, String status) =>
      runAction(() async {
        await widget.api.runStatus(
          tenantId: widget.tenantId,
          runId: run['id'].toString(),
          status: status,
        );
      });

  Future<void> setOperationStatus(String status) async {
    String? reason;
    if (status == 'cancelled') {
      final c = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancel Operation'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Cancellation reason *',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () {
                if (c.text.trim().isNotEmpty)
                  Navigator.pop(dialogContext, c.text.trim());
              },
              child: const Text('Cancel Operation'),
            ),
          ],
        ),
      );
      c.dispose();
      if (reason == null || reason.isEmpty) return;
    }
    await runAction(() async {
      await widget.api.operationStatus(
        tenantId: widget.tenantId,
        operationId: widget.operationId,
        status: status,
        reason: reason,
      );
    });
  }

  Widget runCard(Map<String, dynamic> run) {
    final stops = ((run['stops'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final status = run['status']?.toString() ?? 'planned';
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Run ${run['run_no'] ?? '-'} | ${run['vehicle_registration'] ?? 'Unassigned vehicle'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            statusChip(status),
          ],
        ),
        subtitle: Text(
          '${run['driver_name'] ?? 'No driver'} | Current load ${qty(run['current_primary_qty'])} ${operation['primary_unit'] ?? 'kg'}',
        ),
        children: [
          if (!widget.readOnly &&
              status != 'completed' &&
              status != 'cancelled')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'planned')
                    OutlinedButton.icon(
                      onPressed: working
                          ? null
                          : () => setRunStatus(run, 'loading'),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Start Loading'),
                    ),
                  if (status == 'loading')
                    FilledButton.icon(
                      onPressed: working
                          ? null
                          : () => setRunStatus(run, 'in_transit'),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text('Dispatch'),
                    ),
                  if (status == 'loading' || status == 'in_transit')
                    OutlinedButton.icon(
                      onPressed: working
                          ? null
                          : () => setRunStatus(run, 'completed'),
                      icon: const Icon(Icons.task_alt),
                      label: const Text('Complete Run'),
                    ),
                  OutlinedButton(
                    onPressed: working
                        ? null
                        : () => setRunStatus(run, 'cancelled'),
                    child: const Text('Cancel Run'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: working ? null : () => addStop(run),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Add Stop'),
                  ),
                ],
              ),
            ),
          if (stops.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No stops added yet.'),
            )
          else
            ...stops.map(
              (stop) => ListTile(
                leading: CircleAvatar(
                  child: Text('${stop['sequence_no'] ?? '-'}'),
                ),
                title: Text(
                  '${stop['destination_name_snapshot'] ?? '-'} | ${(stop['action_type'] ?? '').toString().replaceAll('_', ' ')}',
                ),
                subtitle: Text(
                  'Planned pickup ${qty(stop['planned_pickup_primary_qty'])}, delivery ${qty(stop['planned_delivery_primary_qty'])} ${operation['primary_unit'] ?? 'kg'}'
                  '${stop['linked_document_reference'] == null ? '' : '\nDocument: ${stop['linked_document_reference']}'}'
                  '${stop['status'] == 'completed' ? '\nActual pickup ${qty(stop['actual_pickup_primary_qty'])}, delivery ${qty(stop['actual_delivery_primary_qty'])}, variance ${qty(stop['variance_primary_qty'])}' : ''}',
                ),
                isThreeLine: true,
                trailing: widget.readOnly || stop['status'] == 'completed'
                    ? statusChip(stop['status']?.toString() ?? 'planned')
                    : FilledButton.tonal(
                        onPressed: working ? null : () => completeStop(stop),
                        child: const Text('Complete'),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const AlertDialog(
        content: SizedBox(
          width: 720,
          height: 300,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final status = operation['status']?.toString() ?? 'planned';
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              operation['operation_number']?.toString() ??
                  'Logistics Operation',
            ),
          ),
          statusChip(status),
        ],
      ),
      content: SizedBox(
        width: 920,
        height: 670,
        child: error != null
            ? Center(child: Text(error!))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      Text('Date: ${operation['operation_date'] ?? '-'}'),
                      Text('Purpose: ${operation['purpose'] ?? '-'}'),
                      Text(
                        'Units: ${operation['primary_unit'] ?? 'kg'}${operation['secondary_unit'] == null ? '' : ' / ${operation['secondary_unit']}'}',
                      ),
                      if (operation['title'] != null)
                        Text('Reference: ${operation['title']}'),
                    ],
                  ),
                  if (!widget.readOnly) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: working ? null : addRun,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Vehicle Run'),
                        ),
                        if (status == 'planned')
                          OutlinedButton(
                            onPressed: working
                                ? null
                                : () => setOperationStatus('active'),
                            child: const Text('Start Operation'),
                          ),
                        if (status == 'active')
                          OutlinedButton(
                            onPressed: working
                                ? null
                                : () => setOperationStatus('completed'),
                            child: const Text('Complete Operation'),
                          ),
                        if (status == 'completed')
                          FilledButton(
                            onPressed: working
                                ? null
                                : () => setOperationStatus('closed'),
                            child: const Text('Close Operation'),
                          ),
                        if (status != 'closed' && status != 'cancelled')
                          TextButton(
                            onPressed: working
                                ? null
                                : () => setOperationStatus('cancelled'),
                            child: const Text('Cancel'),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Expanded(
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(
                            tabs: [
                              Tab(text: 'Vehicle Runs'),
                              Tab(text: 'Timeline'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                ListView(
                                  padding: const EdgeInsets.only(top: 8),
                                  children: runs.isEmpty
                                      ? const [
                                          Card(
                                            child: Padding(
                                              padding: EdgeInsets.all(24),
                                              child: Center(
                                                child: Text(
                                                  'No vehicle runs yet.',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ]
                                      : runs.map(runCard).toList(),
                                ),
                                ListView(
                                  padding: const EdgeInsets.only(top: 8),
                                  children: events.isEmpty
                                      ? const [
                                          Center(child: Text('No events yet.')),
                                        ]
                                      : events
                                            .map(
                                              (e) => ListTile(
                                                leading: const Icon(
                                                  Icons.history,
                                                ),
                                                title: Text(
                                                  e['message']?.toString() ??
                                                      e['event_type']
                                                          ?.toString() ??
                                                      'Event',
                                                ),
                                                subtitle: Text(
                                                  '${e['created_at'] ?? ''}',
                                                ),
                                              ),
                                            )
                                            .toList(),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class LogisticsMastersPage extends StatefulWidget {
  final ThqLogisticsApi api;
  final String tenantId;
  final String? locationId;

  const LogisticsMastersPage({
    super.key,
    required this.api,
    required this.tenantId,
    required this.locationId,
  });

  @override
  State<LogisticsMastersPage> createState() => _LogisticsMastersPageState();
}

class _LogisticsMastersPageState extends State<LogisticsMastersPage> {
  bool loading = true;
  List<Map<String, dynamic>> vehicles = [];
  List<Map<String, dynamic>> drivers = [];
  List<Map<String, dynamic>> destinations = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  String clean(Object value) => value
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');
  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await Future.wait([
        widget.api.vehicles(
          tenantId: widget.tenantId,
          locationId: widget.locationId,
        ),
        widget.api.drivers(widget.tenantId),
        widget.api.destinations(widget.tenantId),
      ]);
      if (!mounted) return;
      setState(() {
        vehicles = result[0];
        drivers = result[1];
        destinations = result[2];
      });
    } catch (e) {
      message(clean(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addVehicle() async {
    final locationId = widget.locationId;
    if (locationId == null || locationId.isEmpty) {
      message('Select a specific store/location before adding a vehicle.');
      return;
    }
    final reg = TextEditingController();
    final type = TextEditingController(text: 'Truck');
    final model = TextEditingController();
    final capacity = TextEditingController();
    final unit = TextEditingController(text: 'kg');
    final driver = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add Vehicle'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: reg,
                  decoration: const InputDecoration(
                    labelText: 'Registration number *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: type,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle type',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: model,
                        decoration: const InputDecoration(
                          labelText: 'Make / model',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: capacity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Capacity',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unit,
                        decoration: const InputDecoration(
                          labelText: 'Capacity unit',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: driver,
                  decoration: const InputDecoration(
                    labelText: 'Default driver',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(
                    labelText: 'Driver phone',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reg.text.trim().isNotEmpty) Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.api.saveVehicle(
          tenantId: widget.tenantId,
          locationId: locationId,
          registration: reg.text.trim(),
          vehicleType: type.text.trim(),
          makeModel: model.text.trim(),
          capacity: number(capacity.text),
          capacityUnit: unit.text.trim(),
          driverName: driver.text.trim(),
          driverPhone: phone.text.trim(),
        );
        await load();
      } catch (e) {
        message(clean(e));
      }
    }
    for (final x in [reg, type, model, capacity, unit, driver, phone])
      x.dispose();
  }

  Future<void> addDriver() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final license = TextEditingController();
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add Driver'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Driver name *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: license,
                decoration: const InputDecoration(
                  labelText: 'License number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) Navigator.pop(c, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.api.saveDriver(
          tenantId: widget.tenantId,
          name: name.text.trim(),
          phone: phone.text.trim(),
          license: license.text.trim(),
          notes: notes.text.trim(),
        );
        await load();
      } catch (e) {
        message(clean(e));
      }
    }
    for (final x in [name, phone, license, notes]) x.dispose();
  }

  Future<void> addDestination() async {
    var type = 'farm';
    final name = TextEditingController();
    final code = TextEditingController();
    final address = TextEditingController();
    final contact = TextEditingController();
    final phone = TextEditingController();
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add Destination'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'farm', child: Text('Farm')),
                      DropdownMenuItem(value: 'shop', child: Text('Shop')),
                      DropdownMenuItem(
                        value: 'customer',
                        child: Text('Customer'),
                      ),
                      DropdownMenuItem(
                        value: 'supplier',
                        child: Text('Supplier'),
                      ),
                      DropdownMenuItem(value: 'store', child: Text('Store')),
                      DropdownMenuItem(
                        value: 'warehouse',
                        child: Text('Warehouse'),
                      ),
                      DropdownMenuItem(
                        value: 'processing',
                        child: Text('Processing unit'),
                      ),
                      DropdownMenuItem(value: 'market', child: Text('Market')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setLocal(() => type = v ?? 'farm'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: code,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: address,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: contact,
                    decoration: const InputDecoration(
                      labelText: 'Contact person',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isNotEmpty) Navigator.pop(c, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await widget.api.saveDestination(
          tenantId: widget.tenantId,
          type: type,
          name: name.text.trim(),
          code: code.text.trim(),
          address: address.text.trim(),
          contact: contact.text.trim(),
          phone: phone.text.trim(),
          notes: notes.text.trim(),
        );
        await load();
      } catch (e) {
        message(clean(e));
      }
    }
    for (final x in [name, code, address, contact, phone, notes]) x.dispose();
  }

  Widget section(
    String title,
    IconData icon,
    List<Map<String, dynamic>> rows,
    VoidCallback add,
    Widget Function(Map<String, dynamic>) tile,
  ) => Card(
    child: ExpansionTile(
      initiallyExpanded: true,
      leading: Icon(icon),
      title: Text(title),
      trailing: IconButton(
        tooltip: 'Add $title',
        onPressed: add,
        icon: const Icon(Icons.add),
      ),
      children: rows.isEmpty
          ? const [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text('No records found.'),
              ),
            ]
          : rows.map(tile).toList(),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Fleet / Drivers / Destinations'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              section(
                'Vehicles',
                Icons.local_shipping_outlined,
                vehicles,
                addVehicle,
                (r) => ListTile(
                  title: Text(r['registration_number']?.toString() ?? '-'),
                  subtitle: Text(
                    '${r['vehicle_type'] ?? ''} | ${r['make_model'] ?? ''} | ${r['capacity'] ?? 0} ${r['capacity_unit'] ?? ''}',
                  ),
                  trailing: statusChip(
                    r['active'] == false ? 'inactive' : 'active',
                  ),
                ),
              ),
              section(
                'Drivers',
                Icons.badge_outlined,
                drivers,
                addDriver,
                (r) => ListTile(
                  title: Text(r['name']?.toString() ?? '-'),
                  subtitle: Text(
                    '${r['phone'] ?? ''} | ${r['license_number'] ?? ''}',
                  ),
                  trailing: statusChip(
                    r['active'] == false ? 'inactive' : 'active',
                  ),
                ),
              ),
              section(
                'Destinations',
                Icons.location_on_outlined,
                destinations,
                addDestination,
                (r) => ListTile(
                  title: Text(r['name']?.toString() ?? '-'),
                  subtitle: Text(
                    '${r['destination_type'] ?? ''} | ${r['address'] ?? ''}',
                  ),
                  trailing: statusChip(
                    r['active'] == false ? 'inactive' : 'active',
                  ),
                ),
              ),
            ],
          ),
  );
}

Widget statusChip(String status) => Chip(
  visualDensity: VisualDensity.compact,
  label: Text(
    status.replaceAll('_', ' ').toUpperCase(),
    style: const TextStyle(fontSize: 10),
  ),
);

String shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
double number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
double? optionalNumber(String value) =>
    value.trim().isEmpty ? null : double.tryParse(value.trim());
String qty(dynamic value) {
  final n = number(value);
  return (n - n.roundToDouble()).abs() < 0.000001
      ? n.toInt().toString()
      : n.toStringAsFixed(2);
}

String? nullIfEmpty(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}
