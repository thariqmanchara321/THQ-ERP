import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/sales_service.dart';
import '../services/transport_service.dart';

class TransportServiceScreen extends StatefulWidget {
  final ClientSession session;

  const TransportServiceScreen({super.key, required this.session});

  @override
  State<TransportServiceScreen> createState() => _TransportServiceScreenState();
}

class _TransportServiceScreenState extends State<TransportServiceScreen> {
  final TransportService _transport = TransportService();
  final CustomerService _customers = CustomerService();
  final InventoryService _inventory = InventoryService();
  final SalesService _sales = SalesService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _jobs = [];
  List<Customer> _customerRows = [];
  List<InventoryProduct> _billingProducts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _transport.vehicles(
          widget.session.business.id,
          locationId: LocationScopeService.currentForRead(widget.session),
        ),
        _transport.jobs(
          widget.session.business.id,
          locationId: LocationScopeService.currentForRead(widget.session),
        ),
        _customers.getCustomers(tenantId: widget.session.business.id),
        _inventory.getProducts(tenantId: widget.session.business.id),
      ]);

      if (!mounted) return;

      final customers = (results[2] as List<Customer>)
          .where((customer) => customer.isActive)
          .toList();
      final products = (results[3] as List<InventoryProduct>)
          .where(
            (product) =>
                product.productStatus == 'active' &&
                product.variantStatus == 'active' &&
                product.itemType != 'stock',
          )
          .toList();

      setState(() {
        _vehicles = results[0] as List<Map<String, dynamic>>;
        _jobs = results[1] as List<Map<String, dynamic>>;
        _customerRows = customers;
        _billingProducts = products;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addVehicle() async {
    if (!widget.session.hasPermission('transport_service.manage')) {
      _message('transport_service.manage permission required.');
      return;
    }

    final registration = TextEditingController();
    final type = TextEditingController(text: 'Truck');
    final model = TextEditingController();
    final capacity = TextEditingController();
    final unit = TextEditingController(text: 'kg');
    final driver = TextEditingController();
    final phone = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Vehicle'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: registration,
                  decoration: const InputDecoration(
                    labelText: 'Registration number',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: type,
                  decoration: const InputDecoration(labelText: 'Vehicle type'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: 'Make / model'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: capacity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Capacity',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: unit,
                        decoration: const InputDecoration(
                          labelText: 'Capacity unit',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: driver,
                        decoration: const InputDecoration(labelText: 'Driver'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: phone,
                        decoration: const InputDecoration(
                          labelText: 'Driver phone',
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _transport.saveVehicle(
                  tenantId: widget.session.business.id,
                  locationId: LocationScopeService.currentForCreate(
                    widget.session,
                  ),
                  registration: registration.text,
                  vehicleType: type.text,
                  makeModel: model.text,
                  capacity: double.tryParse(capacity.text) ?? 0,
                  capacityUnit: unit.text,
                  driverName: driver.text,
                  driverPhone: phone.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _load();
              } catch (error) {
                _message(error.toString());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

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

  Future<void> _addJob() async {
    if (!widget.session.hasPermission('transport_service.create') &&
        !widget.session.hasPermission('transport_service.manage')) {
      _message('Transport service permission required.');
      return;
    }

    final locationId = LocationScopeService.currentForCreate(widget.session);

    String? vehicleId = _vehicles.isEmpty
        ? null
        : _vehicles.first['id']?.toString();
    final nonWalkIn = _customerRows
        .where((customer) => !customer.isWalkIn)
        .toList();
    String? customerId = nonWalkIn.isEmpty ? null : nonWalkIn.first.id;

    final from = TextEditingController();
    final to = TextEditingController();
    final distance = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final quantityUnit = TextEditingController(text: 'trip');
    final rate = TextEditingController();
    final notes = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('New Taxi / Truck Service'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: vehicleId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Vehicle'),
                    items: _vehicles
                        .map(
                          (vehicle) => DropdownMenuItem<String?>(
                            value: vehicle['id']?.toString(),
                            child: Text(
                              '${vehicle['registration_number']} • ${vehicle['make_model'] ?? ''}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setLocalState(() => vehicleId = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: customerId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Customer'),
                    items: _customerRows
                        .where((customer) => !customer.isWalkIn)
                        .map(
                          (customer) => DropdownMenuItem<String?>(
                            value: customer.id,
                            child: Text(customer.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setLocalState(() => customerId = value),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: from,
                          decoration: const InputDecoration(
                            labelText: 'From location',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: to,
                          decoration: const InputDecoration(
                            labelText: 'To location',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: distance,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Distance (km)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: quantity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: quantityUnit,
                          decoration: const InputDecoration(labelText: 'Unit'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: rate,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Rate'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final result = await _transport.createJob(
                    tenantId: widget.session.business.id,
                    locationId: locationId,
                    customerId: customerId,
                    vehicleId: vehicleId,
                    date: DateTime.now(),
                    from: from.text,
                    to: to.text,
                    distanceKm: double.tryParse(distance.text) ?? 0,
                    quantity: double.tryParse(quantity.text) ?? 0,
                    quantityUnit: quantityUnit.text,
                    rate: double.tryParse(rate.text) ?? 0,
                    notes: notes.text,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  _message(
                    '${result['job_number']} saved • ${result['tracking_code']}',
                  );
                  await _load();
                } catch (error) {
                  _message(error.toString());
                }
              },
              child: const Text('Save Job'),
            ),
          ],
        ),
      ),
    );

    for (final controller in [
      from,
      to,
      distance,
      quantity,
      quantityUnit,
      rate,
      notes,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _billJob(Map<String, dynamic> job) async {
    if (job['sale_id'] != null) {
      _message('This service job is already linked to a Sale.');
      return;
    }
    final customerId = job['customer_id']?.toString();
    if (customerId == null || customerId.isEmpty) {
      _message('Assign a customer to the service job before billing.');
      return;
    }
    if (_billingProducts.isEmpty) {
      _message(
        'Create a Service or Non-stock item in Inventory first (for example Taxi Service / Freight Charge).',
      );
      return;
    }

    InventoryProduct selected = _billingProducts.first;
    String paymentMethod = 'cash';
    bool paidNow = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Bill ${job['job_number']}'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected.variantId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Billing service item',
                  ),
                  items: _billingProducts
                      .map(
                        (product) => DropdownMenuItem<String>(
                          value: product.variantId,
                          child: Text(
                            '${product.productName} • ${product.sku}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (variantId) {
                    if (variantId == null) return;
                    setLocalState(() {
                      selected = _billingProducts.firstWhere(
                        (product) => product.variantId == variantId,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Receive payment now'),
                  value: paidNow,
                  onChanged: (value) => setLocalState(() => paidNow = value),
                ),
                if (paidNow)
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => paymentMethod = value);
                      }
                    },
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Quantity ${job['quantity'] ?? 0} ${job['quantity_unit'] ?? ''} × ${_money(job['rate'])}\nTax ${selected.taxRate.toStringAsFixed(2)}%',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Create Sale'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final quantity =
          (job['quantity'] as num?)?.toDouble() ??
          double.tryParse('${job['quantity']}') ??
          1.0;
      final rate =
          (job['rate'] as num?)?.toDouble() ??
          double.tryParse('${job['rate']}') ??
          0.0;
      final taxable = quantity * rate;
      final total = taxable + (taxable * selected.taxRate / 100.0);

      final sale = await _sales.createSale(
        tenantId: widget.session.business.id,
        customerId: customerId,
        saleDate: DateTime.now(),
        dueDate: paidNow ? null : DateTime.now().add(const Duration(days: 30)),
        items: [
          {
            'variant_id': selected.variantId,
            'quantity': quantity,
            'unit_price': rate,
            'discount_amount': 0.0,
            'tax_rate': selected.taxRate,
          },
        ],
        additionalCharges: 0,
        initialPayment: paidNow ? total : 0,
        paymentMethod: paidNow ? paymentMethod : 'credit',
        paymentReference: '',
        notes:
            'Transport service ${job['job_number']} • ${job['tracking_code']}',
        locationId: job['location_id']?.toString(),
      );

      final saleNumber = sale['sale_number']?.toString();
      if (saleNumber == null || saleNumber.isEmpty) {
        throw Exception('Sale was created but no sale number was returned.');
      }

      await _transport.linkSaleByReference(
        tenantId: widget.session.business.id,
        jobId: job['id'].toString(),
        saleNumber: saleNumber,
      );
      _message('$saleNumber created and linked to ${job['job_number']}.');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  String _money(dynamic value) {
    final number =
        (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0.0;
    if (widget.session.currencyCode == 'INR') {
      return '₹${number.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${number.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transport Service',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Taxi / truck vehicles, route, distance, quantity and linked billing.',
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _addVehicle,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Add Vehicle'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _addJob,
                icon: const Icon(Icons.add_road),
                label: const Text('New Service'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.local_shipping_outlined),
                label: Text('${_vehicles.length} vehicles'),
              ),
              Chip(
                avatar: const Icon(Icons.route),
                label: Text('${_jobs.length} service records'),
              ),
              Chip(
                avatar: const Icon(Icons.store),
                label: Text(widget.session.device?.locationName ?? '-'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Recent Services',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._jobs.map(
            (job) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.route)),
                title: Text(
                  '${job['job_number'] ?? ''} • ${job['registration_number'] ?? 'Vehicle'}',
                ),
                subtitle: Text(
                  '${job['from_location'] ?? '-'} → ${job['to_location'] ?? '-'} • ${job['distance_km'] ?? 0} km\n'
                  'Qty ${job['quantity'] ?? 0} ${job['quantity_unit'] ?? ''} • '
                  '${job['customer_name'] ?? 'No customer'} • ${job['tracking_code'] ?? ''}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _money(job['total_amount']),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          job['sale_id'] == null ? 'UNBILLED' : 'BILLED',
                          style: TextStyle(
                            fontSize: 11,
                            color: job['sale_id'] == null
                                ? Colors.orange.shade800
                                : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    if (job['sale_id'] == null) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => _billJob(job),
                        child: const Text('Bill'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
