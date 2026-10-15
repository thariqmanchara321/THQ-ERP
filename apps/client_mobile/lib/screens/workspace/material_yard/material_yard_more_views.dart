import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/mobile_session.dart';
import '../../../services/mobile_client_service.dart';
import 'material_yard_types.dart';

// ============================================================================
// 1. DAILY MATERIAL RATE BOARD
// ============================================================================
class MobileDailyRatesBoard extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileDailyRatesBoard({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileDailyRatesBoard> createState() => _MobileDailyRatesBoardState();
}

class _MobileDailyRatesBoardState extends State<MobileDailyRatesBoard> {
  late Future<List<Map<String, dynamic>>> _ratesFuture;
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _ratesFuture = widget.service.materialDailyRates(
      widget.session,
      locationId: widget.locationId ?? widget.session.locationId,
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveRates(List<Map<String, dynamic>> rates) async {
    setState(() => _saving = true);
    try {
      final updates = rates.map((r) {
        final key = (r['variant_id'] ?? r['product_id'] ?? r['id']).toString();
        final textVal = _controllers[key]?.text.trim() ?? '0';
        final rateNum = double.tryParse(textVal) ?? 0.0;
        return {
          'variant_id': key,
          'product_id': r['product_id'] ?? key,
          'base_rate': rateNum,
          'min_rate': r['min_rate'] ?? rateNum,
        };
      }).toList();

      await widget.service.saveMaterialDailyRates(
        widget.session,
        locationId: widget.locationId ?? widget.session.locationId,
        date: DateTime.now(),
        rates: updates,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      ThqNotify.success(context, 'Rates Updated', message: 'Today\'s daily rates saved successfully.');
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ThqNotify.error(context, 'Save Failed', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.session.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Rate Board')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ratesFuture,
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
                    const Icon(Icons.error_outline, size: 40, color: Colors.red),
                    const SizedBox(height: 10),
                    Text('Error loading rates: ${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => setState(_reload), child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final rates = snapshot.data ?? [];
          if (rates.isEmpty) {
            return const Center(
              child: Text('No products or daily rates found for this store.'),
            );
          }

          for (final r in rates) {
            final key = (r['variant_id'] ?? r['product_id'] ?? r['id']).toString();
            if (!_controllers.containsKey(key)) {
              final val = r['base_rate'] ?? r['rate'] ?? r['unit_price'] ?? 0;
              _controllers[key] = TextEditingController(text: val.toString());
            }
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: rates.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = rates[i];
              final key = (r['variant_id'] ?? r['product_id'] ?? r['id']).toString();
              final name = r['product_name'] ?? r['name'] ?? 'Material';
              final variant = r['variant_name'] ?? '';
              final unit = r['unit_code'] ?? 'CFT';
              final ctrl = _controllers[key];

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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$name${variant.toString().isNotEmpty ? " • $variant" : ""}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text('Unit: $unit', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Rate',
                            prefixText: '$currency ',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -3)),
            ],
          ),
          child: FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    final rates = await _ratesFuture;
                    _saveRates(rates);
                  },
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Saving Rates...' : 'Save Daily Rates'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 2. TRUCKS & FLEET MASTER
// ============================================================================
class MobileTrucksFleetView extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobileTrucksFleetView({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileTrucksFleetView> createState() => _MobileTrucksFleetViewState();
}

class _MobileTrucksFleetViewState extends State<MobileTrucksFleetView> {
  late Future<Map<String, dynamic>> _contextFuture;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    _contextFuture = widget.service.materialYardContext(
      widget.session,
      locationId: widget.locationId,
    );
  }

  void _addTruck() async {
    final regCtrl = TextEditingController();
    final capCtrl = TextEditingController();
    final lenCtrl = TextEditingController();
    final widCtrl = TextEditingController();
    final hgtCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Yard Truck'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: regCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Registration Number *', hintText: 'e.g. KL-07-CD-5678'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: capCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Nominal Capacity (CFT)', hintText: 'e.g. 350'),
              ),
              const SizedBox(height: 10),
              const Text('Default Body Dimensions (Inches)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: TextField(controller: lenCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'L (in)'))),
                  const SizedBox(width: 6),
                  Expanded(child: TextField(controller: widCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'W (in)'))),
                  const SizedBox(width: 6),
                  Expanded(child: TextField(controller: hgtCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'H (in)'))),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final reg = regCtrl.text.trim().toUpperCase();
              if (reg.isEmpty) {
                ThqNotify.error(ctx, 'Required', message: 'Registration number is required.');
                return;
              }
              try {
                final newVeh = await widget.service.createServiceVehicle(
                  widget.session,
                  registration: reg,
                  nominalCapacityCft: double.tryParse(capCtrl.text.trim()),
                );
                final vehId = newVeh['id']?.toString() ?? newVeh['vehicle_id']?.toString();
                if (vehId != null && (lenCtrl.text.isNotEmpty || widCtrl.text.isNotEmpty || hgtCtrl.text.isNotEmpty)) {
                  await widget.service.saveServiceVehicleProfile(
                    widget.session,
                    vehicleId: vehId,
                    bodyLengthIn: double.tryParse(lenCtrl.text.trim()),
                    bodyWidthIn: double.tryParse(widCtrl.text.trim()),
                    bodyHeightIn: double.tryParse(hgtCtrl.text.trim()),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                setState(_reload);
                if (mounted) ThqNotify.success(context, 'Truck Saved', message: 'Vehicle added to fleet.');
              } catch (e) {
                if (ctx.mounted) ThqNotify.error(ctx, 'Failed', message: '$e');
              }
            },
            child: const Text('Save Truck'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yard Trucks & Fleet')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTruck,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Truck'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _contextFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final vehicles = (snapshot.data?['vehicles'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          if (vehicles.isEmpty) {
            return const Center(child: Text('No vehicles found in fleet. Tap "+ Add Truck" to register one.'));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Search registration or type...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  itemCount: vehicles.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final v = vehicles[i];
                    final reg = v['registration_number'] ?? v['vehicle_registration'] ?? 'Truck';
                    final cap = v['nominal_capacity_cft'];
                    final l = v['body_length_in'] ?? v['body_length_ft'];
                    final w = v['body_width_in'] ?? v['body_width_ft'];
                    final h = v['body_height_in'] ?? v['body_height_ft'];

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                        title: Text(reg, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${cap != null ? "Capacity: $cap CFT" : "Capacity: N/A"}'
                          '${l != null ? " • Dims: $l × $w × $h" : ""}',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// 3. DRIVER MASTER VIEW
// ============================================================================
class MobileDriverMasterView extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;

  const MobileDriverMasterView({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  State<MobileDriverMasterView> createState() => _MobileDriverMasterViewState();
}

class _MobileDriverMasterViewState extends State<MobileDriverMasterView> {
  late Future<List<Map<String, dynamic>>> _driversFuture;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    _driversFuture = widget.service.logisticsDrivers(
      widget.session,
      query: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    );
  }

  void _addDriver() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final licCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Yard Driver'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Driver Name *')),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number')),
            const SizedBox(height: 10),
            TextField(controller: licCtrl, decoration: const InputDecoration(labelText: 'License Number')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ThqNotify.error(ctx, 'Required', message: 'Driver name is required.');
                return;
              }
              try {
                await widget.service.saveLogisticsDriver(
                  widget.session,
                  fullName: name,
                  phone: phoneCtrl.text.trim(),
                  licenseNumber: licCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                setState(_reload);
                if (mounted) ThqNotify.success(context, 'Driver Saved', message: 'Driver registered successfully.');
              } catch (e) {
                if (ctx.mounted) ThqNotify.error(ctx, 'Failed', message: '$e');
              }
            },
            child: const Text('Save Driver'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yard Driver Master')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDriver,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Driver'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search driver name or phone...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: (_) => setState(_reload),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _driversFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final drivers = snapshot.data ?? [];
                if (drivers.isEmpty) {
                  return const Center(child: Text('No drivers found. Tap "+ Add Driver" to register one.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  itemCount: drivers.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = drivers[i];
                    final name = d['full_name'] ?? d['driver_name'] ?? 'Driver';
                    final phone = d['phone'] ?? 'No phone';
                    final lic = d['license_number'] ?? '';

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('$phone${lic.isNotEmpty ? " • Lic: $lic" : ""}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. CUSTOMER ORDERS VIEW
// ============================================================================
class MobileCustomerOrdersView extends StatelessWidget {
  final MobileSession session;
  final MobileClientService service;

  const MobileCustomerOrdersView({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Bulk Orders')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: service.materialOrders(session),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return const Center(child: Text('No open customer bulk orders.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final o = orders[i];
              final cust = o['customer_name'] ?? 'Customer';
              final prod = o['product_name'] ?? 'Material';
              final ordered = o['ordered_qty'] ?? o['quantity'] ?? 0;
              final disp = o['dispatched_qty'] ?? 0;
              final bal = o['balance_qty'] ?? (ordered - disp);

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(cust, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (o['status'] ?? 'OPEN').toString().toUpperCase(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('$prod • Ordered: $ordered CFT', style: const TextStyle(fontSize: 12)),
                      Text('Dispatched: $disp CFT • Balance: $bal CFT', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// 5. FREIGHT & LOGISTICS VIEW
// ============================================================================
class MobileFreightLogisticsView extends StatelessWidget {
  final MobileSession session;
  final MobileClientService service;

  const MobileFreightLogisticsView({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Freight & Logistics')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: service.materialFreightLoads(session),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final loads = snapshot.data ?? [];
          if (loads.isEmpty) {
            return const Center(child: Text('No freight loads configured yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: loads.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final fl = loads[i];
              final truck = fl['vehicle_registration'] ?? 'Truck';
              final amt = fl['freight_amount'] ?? 0;
              final settled = fl['is_settled'] == true;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: Text(truck, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Freight: ${MaterialYardFormat.money(amt, currency: session.currency)}'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (settled ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      settled ? 'SETTLED' : 'PENDING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: settled ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
