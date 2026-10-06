import 'package:thq_ui/thq_ui.dart';
import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import 'transport_logistics_hub_screen.dart';

class AggregateVehiclesScreen extends StatefulWidget {
  final ClientSession session;

  const AggregateVehiclesScreen({super.key, required this.session});

  @override
  State<AggregateVehiclesScreen> createState() =>
      _AggregateVehiclesScreenState();
}

class _AggregateVehiclesScreenState extends State<AggregateVehiclesScreen> {
  final AggregateYardService _service = AggregateYardService();

  List<Map<String, dynamic>> _vehicles = const [];
  List<Map<String, dynamic>> _locations = const [];
  bool _loading = true;
  String? _error;
  bool get _hasTransport =>
      widget.session.hasModule('vehicle_logistics') ||
      widget.session.hasModule('logistics_operations') ||
      widget.session.hasModule('transport_service');

  bool get _canManageTrucks =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('aggregate_yard.manage') ||
      widget.session.hasPermission('logistics_operations.manage') ||
      widget.session.hasPermission('transport_service.manage');

  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_locationChanged);
    _reload();
  }

  void _locationChanged() => _reload();

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_locationChanged);
    super.dispose();
  }

  double? _double(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final context = await _service.context(
        tenantId: widget.session.business.id,
      );
      _vehicles = (context['vehicles'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((row) {
            final locationId = LocationScopeService.currentForRead(
              widget.session,
            );
            return locationId == null ||
                row['location_id'] == null ||
                row['location_id'] == locationId;
          })
          .toList();
      _locations = (context['locations'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _text(dynamic value) => value?.toString() ?? '';

  Future<void> _addTruck() async {
    if (!_canManageTrucks) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Truck manage permission is required.')),
      );
      return;
    }

    if (_locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create an active store/location first.')),
      );
      return;
    }

    final registration = TextEditingController();
    final makeModel = TextEditingController();
    final driverName = TextEditingController();
    final driverPhone = TextEditingController();
    final capacity = TextEditingController();

    String vehicleType = 'Truck';
    String? locationId = LocationScopeService.selectedLocationId.value;
    if (locationId == null ||
        !_locations.any(
          (row) => row['location_id']?.toString() == locationId,
        )) {
      locationId = _locations.first['location_id']?.toString();
    }

    try {
      final saved = await showThqDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: const Text('Add Truck'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: registration,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Registration number *',
                        hintText: 'KL 11 AB 1234',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: vehicleType,
                            decoration: const InputDecoration(
                              labelText: 'Type',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Truck',
                                child: Text('Truck'),
                              ),
                              DropdownMenuItem(
                                value: 'Tipper',
                                child: Text('Tipper'),
                              ),
                              DropdownMenuItem(
                                value: 'Trailer',
                                child: Text('Trailer'),
                              ),
                              DropdownMenuItem(
                                value: 'Other',
                                child: Text('Other'),
                              ),
                            ],
                            onChanged: (value) => setLocalState(
                              () => vehicleType = value ?? 'Truck',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: capacity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Capacity CFT',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: locationId,
                      decoration: const InputDecoration(
                        labelText: 'Yard / store',
                        border: OutlineInputBorder(),
                      ),
                      items: _locations
                          .map(
                            (row) => DropdownMenuItem<String>(
                              value: row['location_id']?.toString(),
                              child: Text(
                                '${row['code'] ?? ''} - ${row['name'] ?? ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setLocalState(() => locationId = value),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: makeModel,
                      decoration: const InputDecoration(
                        labelText: 'Make / model (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: driverName,
                            decoration: const InputDecoration(
                              labelText: 'Driver (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: driverPhone,
                            decoration: const InputDecoration(
                              labelText: 'Driver phone',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Registration is the only required truck detail. '
                        'Ownership, dimensions and freight can be configured later.',
                        style: TextStyle(fontSize: 11),
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
              FilledButton.icon(
                onPressed: () async {
                  if (registration.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter the registration number.'),
                      ),
                    );
                    return;
                  }
                  if (locationId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Select a yard/store.')),
                    );
                    return;
                  }

                  try {
                    await _service.createVehicle(
                      tenantId: widget.session.business.id,
                      locationId: locationId!,
                      registrationNumber: registration.text,
                      vehicleType: vehicleType,
                      makeModel: makeModel.text,
                      driverName: driverName.text,
                      driverPhone: driverPhone.text,
                      capacityCft: _double(capacity.text),
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Truck'),
              ),
            ],
          ),
        ),
      );

      if (saved == true) {
        await _reload();
      }
    } finally {
      registration.dispose();
      makeModel.dispose();
      driverName.dispose();
      driverPhone.dispose();
      capacity.dispose();
    }
  }

  Future<void> _editDriver(Map<String, dynamic> vehicle) async {
    final name = TextEditingController(text: _text(vehicle['driver_name']));
    final phone = TextEditingController(text: _text(vehicle['driver_phone']));
    bool saving = false;
    String? error;
    try {
      final saved = await showThqDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('Driver — ${vehicle['registration_number']}'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Driver name'),
                  ),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Driver phone',
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await _service.saveVehicleDriver(
                            tenantId: widget.session.business.id,
                            vehicleId: vehicle['vehicle_id'].toString(),
                            driverName: name.text,
                            driverPhone: phone.text,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            update(() {
                              saving = false;
                              error = e.toString();
                            });
                          }
                        }
                      },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (saved == true && mounted) {
        await _reload();
      }
    } finally {
      name.dispose();
      phone.dispose();
    }
  }

  Future<void> _edit(Map<String, dynamic> vehicle) async {
    String ownership = _text(vehicle['ownership_type']).isEmpty
        ? 'hired'
        : _text(vehicle['ownership_type']);

    final ownerName = TextEditingController(text: _text(vehicle['owner_name']));
    final ownerPhone = TextEditingController(
      text: _text(vehicle['owner_phone']),
    );
    final length = TextEditingController(
      text: _text(vehicle['body_length_ft']),
    );
    final width = TextEditingController(text: _text(vehicle['body_width_ft']));
    final height = TextEditingController(
      text: _text(vehicle['body_height_ft']),
    );
    final capacity = TextEditingController(
      text: _text(vehicle['nominal_capacity_cft']),
    );
    final tare = TextEditingController(text: _text(vehicle['tare_weight_kg']));
    final payload = TextEditingController(
      text: _text(vehicle['max_payload_kg']),
    );
    final freight = TextEditingController(
      text: _text(vehicle['default_freight']).isEmpty
          ? '0'
          : _text(vehicle['default_freight']),
    );

    try {
      final saved = await showThqDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            final calculated =
                (_double(length.text) ?? 0) *
                (_double(width.text) ?? 0) *
                (_double(height.text) ?? 0);

            return AlertDialog(
              title: Text('Truck ${vehicle['registration_number'] ?? ''}'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: ownership,
                        decoration: const InputDecoration(
                          labelText: 'Ownership',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'owned',
                            child: Text('Own vehicle'),
                          ),
                          DropdownMenuItem(
                            value: 'hired',
                            child: Text('Hired vehicle'),
                          ),
                          DropdownMenuItem(
                            value: 'supplier',
                            child: Text('Supplier vehicle'),
                          ),
                          DropdownMenuItem(
                            value: 'customer',
                            child: Text('Customer vehicle'),
                          ),
                        ],
                        onChanged: (value) =>
                            setLocalState(() => ownership = value ?? 'hired'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ownerName,
                              decoration: const InputDecoration(
                                labelText: 'Owner / Transporter',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: ownerPhone,
                              decoration: const InputDecoration(
                                labelText: 'Owner phone',
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
                              controller: length,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Body length ft',
                              ),
                              onChanged: (_) => setLocalState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: width,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Body width ft',
                              ),
                              onChanged: (_) => setLocalState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: height,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Body height ft',
                              ),
                              onChanged: (_) => setLocalState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          calculated > 0
                              ? 'Calculated body capacity: ${calculated.toStringAsFixed(3)} CFT'
                              : 'Enter dimensions to calculate CFT capacity.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: capacity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Nominal capacity CFT',
                          helperText:
                              'Leave blank to use Length × Width × Height.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: tare,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Tare kg',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: payload,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Max payload kg',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: freight,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Default freight',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await _service.saveVehicleProfile(
                        tenantId: widget.session.business.id,
                        vehicleId: vehicle['vehicle_id'].toString(),
                        ownershipType: ownership,
                        ownerName: ownerName.text,
                        ownerPhone: ownerPhone.text,
                        bodyLengthFt: _double(length.text),
                        bodyWidthFt: _double(width.text),
                        bodyHeightFt: _double(height.text),
                        nominalCapacityCft: _double(capacity.text),
                        tareWeightKg: _double(tare.text),
                        maxPayloadKg: _double(payload.text),
                        defaultFreight: _double(freight.text) ?? 0,
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
      );

      if (saved == true) await _reload();
    } finally {
      ownerName.dispose();
      ownerPhone.dispose();
      length.dispose();
      width.dispose();
      height.dispose();
      capacity.dispose();
      tare.dispose();
      payload.dispose();
      freight.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Truck Setup'),
      actions: [
        if (_canManageTrucks)
          FilledButton.icon(
            onPressed: _loading ? null : _addTruck,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Truck'),
          ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _vehicles.isEmpty
        ? const Center(
            child: Text(
              'No trucks yet.\nUse Add Truck above to create the first one.',
              textAlign: TextAlign.center,
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _vehicles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final row = _vehicles[index];
              final capacity = row['nominal_capacity_cft'];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.local_shipping_outlined),
                  ),
                  title: Text(
                    '${row['registration_number'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${row['vehicle_type'] ?? 'Truck'}'
                    '  |  ${row['ownership_type'] ?? 'hired'}'
                    '${capacity == null ? '' : '  |  $capacity CFT'}'
                    '\n${row['driver_name'] ?? ''}'
                    '${row['owner_name'] == null ? '' : '  |  ${row['owner_name']}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _canManageTrucks || _hasTransport
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_hasTransport)
                              IconButton(
                                tooltip: 'View vehicle trips',
                                onPressed: () async {
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TransportLogisticsHubScreen(
                                            session: widget.session,
                                            initialVehicleId: row['vehicle_id']
                                                ?.toString(),
                                          ),
                                    ),
                                  );
                                  if (mounted) await _reload();
                                },
                                icon: const Icon(Icons.route_outlined),
                              ),
                            if (_canManageTrucks)
                              IconButton(
                                tooltip: 'Driver name / phone',
                                onPressed: () => _editDriver(row),
                                icon: const Icon(Icons.person_outline),
                              ),
                            if (_canManageTrucks)
                              IconButton(
                                tooltip: 'Configure',
                                onPressed: () => _edit(row),
                                icon: const Icon(Icons.tune_outlined),
                              ),
                          ],
                        )
                      : null,
                ),
              );
            },
          ),
  );
}
