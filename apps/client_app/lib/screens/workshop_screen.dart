import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/workshop_service.dart';

class WorkshopScreen extends StatefulWidget {
  final ClientSession session;
  const WorkshopScreen({super.key, required this.session});

  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<WorkshopScreen>
    with SingleTickerProviderStateMixin {
  final _service = WorkshopService();
  final _search = TextEditingController();
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _jobs = [];
  String _status = '';

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('workshop.manage');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_tabs.index == 0) {
        _jobs = await _service.jobs(
          tenantId: widget.session.business.id,
          status: _status,
          query: _search.text,
        );
      } else {
        _vehicles = await _service.vehicles(
          tenantId: widget.session.business.id,
          query: _search.text,
        );
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _writeLocationId {
    final selected = LocationScopeService.selectedLocationId.value;
    if (selected != null && selected.isNotEmpty) return selected;
    if (widget.session.device?.locationId.isNotEmpty == true) {
      return widget.session.device!.locationId;
    }
    if (widget.session.locations.length == 1) {
      return widget.session.locations.first.id;
    }
    return null;
  }

  Future<void> _vehicleDialog([Map<String, dynamic>? row]) async {
    final locationId = _writeLocationId;
    if (locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a store before creating a vehicle.'),
        ),
      );
      return;
    }
    final number = TextEditingController(
      text: row?['vehicle_number']?.toString() ?? '',
    );
    final make = TextEditingController(text: row?['make']?.toString() ?? '');
    final model = TextEditingController(text: row?['model']?.toString() ?? '');
    final year = TextEditingController(text: row?['year']?.toString() ?? '');
    final odo = TextEditingController(text: row?['odometer']?.toString() ?? '');
    final vin = TextEditingController(text: row?['vin']?.toString() ?? '');
    final chassis = TextEditingController(
      text: row?['chassis_number']?.toString() ?? '',
    );
    final notes = TextEditingController(text: row?['notes']?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(row == null ? 'Add Vehicle' : 'Edit Vehicle'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: number,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Number *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: make,
                        decoration: const InputDecoration(
                          labelText: 'Make',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: model,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: year,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Year',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: odo,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Odometer',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vin,
                  decoration: const InputDecoration(
                    labelText: 'VIN',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: chassis,
                  decoration: const InputDecoration(
                    labelText: 'Chassis Number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (number.text.trim().isEmpty) return;
              await _service.saveVehicle(
                tenantId: widget.session.business.id,
                id: row?['id']?.toString(),
                locationId: locationId,
                customerId: row?['customer_id']?.toString(),
                vehicleNumber: number.text,
                make: make.text,
                model: model.text,
                year: int.tryParse(year.text),
                vin: vin.text,
                chassis: chassis.text,
                odometer: double.tryParse(odo.text),
                notes: notes.text,
              );
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    for (final c in [number, make, model, year, odo, vin, chassis, notes]) {
      c.dispose();
    }
    if (saved == true) await _load();
  }

  Future<void> _newJob() async {
    final locationId = _writeLocationId;
    if (locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a store before creating a job card.'),
        ),
      );
      return;
    }
    final vehicles = await _service.vehicles(
      tenantId: widget.session.business.id,
    );
    if (!mounted) return;
    if (vehicles.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add a vehicle first.')));
      return;
    }
    var vehicleId = vehicles.first['id'].toString();
    final complaint = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New Job Card'),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: vehicleId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle',
                    border: OutlineInputBorder(),
                  ),
                  items: vehicles
                      .map(
                        (v) => DropdownMenuItem(
                          value: v['id'].toString(),
                          child: Text(
                            '${v['vehicle_number']} • ${v['make'] ?? ''} ${v['model'] ?? ''}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => vehicleId = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: complaint,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Complaint / Work Required *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (complaint.text.trim().isEmpty) return;
                final vehicle = vehicles.firstWhere(
                  (v) => v['id'].toString() == vehicleId,
                );
                await _service.createJob(
                  tenantId: widget.session.business.id,
                  locationId: locationId,
                  vehicleId: vehicleId,
                  customerId: vehicle['customer_id']?.toString(),
                  complaint: complaint.text,
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Create Job'),
            ),
          ],
        ),
      ),
    );
    complaint.dispose();
    if (saved == true) await _load();
  }

  Future<void> _changeStatus(Map<String, dynamic> job, String status) async {
    await _service.updateStatus(
      tenantId: widget.session.business.id,
      jobId: job['id'].toString(),
      status: status,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SizedBox(
                width: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workshop',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Vehicles, job cards, technicians and service progress',
                    ),
                  ],
                ),
              ),
              if (_canManage && _tabs.index == 0)
                FilledButton.icon(
                  onPressed: _newJob,
                  icon: const Icon(Icons.add),
                  label: const Text('New Job Card'),
                ),
              if (_canManage && _tabs.index == 1)
                FilledButton.icon(
                  onPressed: () => _vehicleDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Vehicle'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Job Cards'),
              Tab(text: 'Vehicles'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: _tabs.index == 0
                        ? 'Search job, vehicle, customer or complaint'
                        : 'Search vehicle, make, model or customer',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              if (_tabs.index == 0) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All')),
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(
                        value: 'in_progress',
                        child: Text('In Progress'),
                      ),
                      DropdownMenuItem(
                        value: 'waiting_parts',
                        child: Text('Waiting Parts'),
                      ),
                      DropdownMenuItem(value: 'ready', child: Text('Ready')),
                      DropdownMenuItem(
                        value: 'delivered',
                        child: Text('Delivered'),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _status = v ?? '');
                      _load();
                    },
                  ),
                ),
              ],
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 14),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tabs.index == 0
                ? _jobsView()
                : _vehiclesView(),
          ),
        ],
      ),
    );
  }

  Widget _jobsView() {
    if (_jobs.isEmpty) {
      return const Center(child: Text('No workshop job cards found.'));
    }
    return ListView.separated(
      itemCount: _jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final job = _jobs[index];
        final status = job['status']?.toString() ?? 'open';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(child: const Icon(Icons.build_outlined)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${job['job_number']} • ${job['vehicle_number']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        job['customer_name']?.toString().isNotEmpty == true
                            ? job['customer_name'].toString()
                            : 'No customer linked',
                      ),
                      if (job['complaint']?.toString().isNotEmpty == true)
                        Text(
                          job['complaint'].toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Chip(label: Text(status.replaceAll('_', ' ').toUpperCase())),
                if (_canManage) ...[
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'Update Status',
                    onSelected: (v) => _changeStatus(job, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'inspection',
                        child: Text('Inspection'),
                      ),
                      PopupMenuItem(value: 'approved', child: Text('Approved')),
                      PopupMenuItem(
                        value: 'in_progress',
                        child: Text('In Progress'),
                      ),
                      PopupMenuItem(
                        value: 'waiting_parts',
                        child: Text('Waiting Parts'),
                      ),
                      PopupMenuItem(value: 'ready', child: Text('Ready')),
                      PopupMenuItem(
                        value: 'delivered',
                        child: Text('Delivered'),
                      ),
                      PopupMenuItem(
                        value: 'cancelled',
                        child: Text('Cancelled'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _vehiclesView() {
    if (_vehicles.isEmpty) {
      return const Center(child: Text('No vehicles found.'));
    }
    return GridView.extent(
      maxCrossAxisExtent: 390,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.3,
      children: _vehicles
          .map(
            (v) => Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _canManage ? () => _vehicleDialog(v) : null,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car_outlined, size: 34),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v['vehicle_number']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${v['make'] ?? ''} ${v['model'] ?? ''}'.trim(),
                            ),
                            if (v['customer_name']?.toString().isNotEmpty ==
                                true)
                              Text(
                                v['customer_name'].toString(),
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
