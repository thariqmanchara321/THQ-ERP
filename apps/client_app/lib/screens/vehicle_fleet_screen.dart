import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../services/location_scope_service.dart';
import '../services/transport_service.dart';

class VehicleFleetScreen extends StatefulWidget {
  final ClientSession session;

  const VehicleFleetScreen({super.key, required this.session});

  @override
  State<VehicleFleetScreen> createState() => _VehicleFleetScreenState();
}

class _VehicleFleetScreenState extends State<VehicleFleetScreen> {
  final TransportService _transport = TransportService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vehicles = [];

  String get _tenantId => widget.session.business.id;
  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('transport_service.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object error) => error
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  void _message(String message) {
    if (!mounted) {
      return;
    }
    ThqNotify.showSnackBar(context, SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _transport.vehicles(
        _tenantId,
        locationId: _locationId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _vehicles = rows);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _clean(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editVehicle([Map<String, dynamic>? vehicle]) async {
    if (!_canManage) {
      _message('Transport service manage permission required.');
      return;
    }

    final registration = TextEditingController(
      text: vehicle?['registration_number']?.toString() ?? '',
    );
    final type = TextEditingController(
      text: vehicle?['vehicle_type']?.toString() ?? 'Truck',
    );
    final model = TextEditingController(
      text: vehicle?['make_model']?.toString() ?? '',
    );
    final capacity = TextEditingController(
      text: vehicle == null ? '' : '${vehicle['capacity'] ?? ''}',
    );
    final unit = TextEditingController(
      text: vehicle?['capacity_unit']?.toString() ?? 'kg',
    );
    final driver = TextEditingController(
      text: vehicle?['driver_name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: vehicle?['driver_phone']?.toString() ?? '',
    );

    bool active = vehicle?['active'] != false;
    String? validationError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(vehicle == null ? 'Add Vehicle' : 'Edit Vehicle'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (validationError != null) ...[
                    Text(
                      validationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: registration,
                    autofocus: vehicle == null,
                    onChanged: (_) {
                      if (validationError != null) {
                        setLocalState(() => validationError = null);
                      }
                    },
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: driver,
                          decoration: const InputDecoration(
                            labelText: 'Driver name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: phone,
                          decoration: const InputDecoration(
                            labelText: 'Driver phone',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (vehicle != null) ...[
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active vehicle'),
                      subtitle: Text(
                        '${vehicle['open_jobs'] ?? 0} open service job(s)',
                      ),
                      value: active,
                      onChanged: (value) => setLocalState(() => active = value),
                    ),
                  ],
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
                final registrationValue = registration.text.trim();
                final capacityText = capacity.text.trim();
                final capacityValue = capacityText.isEmpty
                    ? 0.0
                    : double.tryParse(capacityText);

                if (registrationValue.isEmpty) {
                  setLocalState(
                    () => validationError = 'Registration number is required.',
                  );
                  return;
                }
                if (capacityValue == null || capacityValue < 0) {
                  setLocalState(
                    () => validationError =
                        'Capacity must be a valid non-negative number.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      try {
        final existingLocationId = vehicle?['location_id']?.toString();
        final locationId =
            existingLocationId != null && existingLocationId.isNotEmpty
            ? existingLocationId
            : LocationScopeService.currentForCreate(widget.session);

        await _transport.saveVehicle(
          tenantId: _tenantId,
          vehicleId: vehicle?['id']?.toString(),
          locationId: locationId,
          registration: registration.text,
          vehicleType: type.text,
          makeModel: model.text,
          capacity: double.tryParse(capacity.text.trim()) ?? 0,
          capacityUnit: unit.text,
          driverName: driver.text,
          driverPhone: phone.text,
          active: active,
        );

        _message(vehicle == null ? 'Vehicle created.' : 'Vehicle updated.');
        await _load();
      } catch (error) {
        _message(_clean(error));
      }
    }

    for (final controller in [
      registration,
      type,
      model,
      capacity,
      unit,
      driver,
      phone,
    ]) {
      controller.dispose();
    }
  }

  Widget _vehicleCard(Map<String, dynamic> vehicle) {
    final active = vehicle['active'] != false;
    final registration =
        vehicle['registration_number']?.toString().trim() ?? '';
    final makeModel = vehicle['make_model']?.toString().trim() ?? '';
    final vehicleType = vehicle['vehicle_type']?.toString().trim() ?? '';
    final driver = vehicle['driver_name']?.toString().trim() ?? '';
    final phone = vehicle['driver_phone']?.toString().trim() ?? '';
    final location = vehicle['location_name']?.toString().trim() ?? '';
    final capacity = vehicle['capacity'];
    final unit = vehicle['capacity_unit']?.toString().trim() ?? '';

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            active
                ? Icons.local_shipping_outlined
                : Icons.local_shipping_rounded,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                registration.isEmpty ? 'Vehicle' : registration,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(active ? 'ACTIVE' : 'INACTIVE'),
            ),
          ],
        ),
        subtitle: Text(
          [
            [vehicleType, makeModel].where((v) => v.isNotEmpty).join(' - '),
            if (capacity != null)
              'Capacity $capacity${unit.isEmpty ? '' : ' $unit'}',
            if (driver.isNotEmpty)
              'Driver $driver${phone.isEmpty ? '' : ' | $phone'}',
            if (location.isNotEmpty) location,
          ].where((v) => v.isNotEmpty).join('\n'),
        ),
        isThreeLine: true,
        trailing: _canManage
            ? IconButton(
                tooltip: 'Edit vehicle',
                onPressed: () => _editVehicle(vehicle),
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Fleet'),
        actions: [
          if (_canManage)
            FilledButton.tonalIcon(
              onPressed: () => _editVehicle(),
              icon: const Icon(Icons.add),
              label: const Text('Add Vehicle'),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Text(
                    'Fleet master',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Vehicles here are shared by Vehicle Logistics and Transport / Service.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_vehicles.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Center(
                          child: Text(
                            _canManage
                                ? 'No vehicles found. Use Add Vehicle to create the first fleet vehicle.'
                                : 'No vehicles found for this location.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._vehicles.map(_vehicleCard),
                ],
              ),
            ),
    );
  }
}
