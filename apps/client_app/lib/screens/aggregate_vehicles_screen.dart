import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';

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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
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
          .toList();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _text(dynamic value) => value?.toString() ?? '';

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
      final saved = await showDialog<bool>(
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
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _vehicles.isEmpty
        ? const Center(
            child: Text(
              'No vehicles are available.\nAdd vehicles from Transport & Logistics first.',
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
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
                  trailing: IconButton(
                    tooltip: 'Configure',
                    onPressed: () => _edit(row),
                    icon: const Icon(Icons.tune_outlined),
                  ),
                ),
              );
            },
          ),
  );
}
