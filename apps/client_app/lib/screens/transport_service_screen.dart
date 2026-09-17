import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/transport_service.dart';
import '../widgets/searchable_select.dart';

class TransportServiceScreen extends StatefulWidget {
  final ClientSession session;
  final bool startInCreate;

  const TransportServiceScreen({
    super.key,
    required this.session,
    this.startInCreate = false,
  });

  @override
  State<TransportServiceScreen> createState() => _TransportServiceScreenState();
}

class _TransportServiceScreenState extends State<TransportServiceScreen> {
  final TransportService _transport = TransportService();
  final CustomerService _customers = CustomerService();
  final InventoryService _inventory = InventoryService();

  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _jobs = [];
  List<Customer> _customerRows = [];
  List<InventoryProduct> _billingProducts = [];

  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('transport_service.manage');

  bool get _canCreate =>
      _canManage || widget.session.hasPermission('transport_service.create');

  String get _tenantId => widget.session.business.id;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _load();
    if (!mounted || !widget.startInCreate || _error != null || !_canCreate) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jobDialog();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final locationId = LocationScopeService.currentForRead(widget.session);
      final results = await Future.wait([
        _transport.vehicles(_tenantId, locationId: locationId),
        _transport.jobs(
          _tenantId,
          locationId: locationId,
          status: _statusFilter == 'all' ? null : _statusFilter,
        ),
        _customers.getCustomers(tenantId: _tenantId),
        _inventory.getProducts(tenantId: _tenantId),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicles = results[0] as List<Map<String, dynamic>>;
        _jobs = results[1] as List<Map<String, dynamic>>;
        _customerRows = (results[2] as List<Customer>)
            .where((customer) => customer.isActive && !customer.isWalkIn)
            .toList();
        _billingProducts = (results[3] as List<InventoryProduct>)
            .where(
              (product) =>
                  product.productStatus == 'active' &&
                  product.variantStatus == 'active' &&
                  product.itemType != 'stock',
            )
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _clean(Object error) => error
      .toString()
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '');

  void _message(String text) {
    if (!mounted) return;
    ThqNotify.showSnackBar(context, SnackBar(content: Text(text)));
  }

  double _number(dynamic value) =>
      (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0;

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  DateTime _date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();

  String _money(dynamic value) {
    final number = _number(value);
    if (widget.session.currencyCode == 'INR') {
      return '₹${number.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${number.toStringAsFixed(2)}';
  }

  Future<void> _vehicleDialog([Map<String, dynamic>? vehicle]) async {
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

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(vehicle == null ? 'Add Vehicle' : 'Edit Vehicle'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: registration,
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
                  if (vehicle != null)
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
                if (registration.text.trim().isEmpty) {
                  _message('Registration number is required.');
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
        await _transport.saveVehicle(
          tenantId: _tenantId,
          vehicleId: vehicle?['id']?.toString(),
          locationId: LocationScopeService.currentForCreate(widget.session),
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

  Future<void> _jobDialog([Map<String, dynamic>? job]) async {
    if (job == null && !_canCreate) {
      _message('Transport service create permission required.');
      return;
    }
    if (job != null && !_canManage) {
      _message('Transport service manage permission required.');
      return;
    }

    final locationId = LocationScopeService.currentForCreate(widget.session);
    final activeVehicles = _vehicles
        .where((vehicle) => vehicle['active'] != false)
        .toList();
    String? vehicleId = job?['vehicle_id']?.toString();
    if (vehicleId == null && activeVehicles.isNotEmpty) {
      vehicleId = activeVehicles.first['id']?.toString();
    }
    String? customerId = job?['customer_id']?.toString();
    DateTime serviceDate = job == null
        ? DateTime.now()
        : _date(job['service_date']);
    String status = job?['status']?.toString() ?? 'planned';

    final from = TextEditingController(
      text: job?['from_location']?.toString() ?? '',
    );
    final to = TextEditingController(
      text: job?['to_location']?.toString() ?? '',
    );
    final distance = TextEditingController(
      text: job == null ? '' : '${job['distance_km'] ?? ''}',
    );
    final quantity = TextEditingController(
      text: job == null ? '1' : '${job['quantity'] ?? 1}',
    );
    final quantityUnit = TextEditingController(
      text: job?['quantity_unit']?.toString() ?? 'trip',
    );
    final rate = TextEditingController(
      text: job == null ? '' : '${job['rate'] ?? ''}',
    );
    final notes = TextEditingController(text: job?['notes']?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            job == null
                ? 'New Transport / Service Job'
                : 'Edit ${job['job_number']}',
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: vehicleId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Vehicle (optional)',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No vehicle'),
                            ),
                            ...activeVehicles.map(
                              (vehicle) => DropdownMenuItem<String?>(
                                value: vehicle['id']?.toString(),
                                child: Text(
                                  '${vehicle['registration_number']} • ${vehicle['make_model'] ?? vehicle['vehicle_type'] ?? ''}',
                                ),
                              ),
                            ),
                          ],
                          onChanged: job?['sale_id'] != null
                              ? null
                              : (value) =>
                                    setLocalState(() => vehicleId = value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: serviceDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(
                                const Duration(days: 3650),
                              ),
                            );
                            if (picked != null) {
                              setLocalState(() => serviceDate = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Service date',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              '${serviceDate.day.toString().padLeft(2, '0')}/${serviceDate.month.toString().padLeft(2, '0')}/${serviceDate.year}',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SearchableSelect<String>(
                    value: customerId,
                    labelText: 'Customer',
                    allowClear: job?['sale_id'] == null,
                    hintText: 'Search customer name, phone or GSTIN',
                    prefixIcon: Icons.person_search_outlined,
                    options: _customerRows
                        .map(
                          (customer) => SearchableSelectOption<String>(
                            value: customer.id,
                            label: customer.name,
                            subtitle:
                                [
                                      customer.publicId,
                                      customer.phone,
                                      customer.taxNumber,
                                    ]
                                    .whereType<String>()
                                    .where((v) => v.trim().isNotEmpty)
                                    .join(' • '),
                            searchText:
                                '${customer.name} ${customer.publicId} ${customer.phone ?? ''} ${customer.email ?? ''} ${customer.taxNumber ?? ''}',
                          ),
                        )
                        .toList(),
                    onChanged: job?['sale_id'] != null
                        ? null
                        : (value) => setLocalState(() => customerId = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: from,
                          decoration: const InputDecoration(
                            labelText: 'From location',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: to,
                          decoration: const InputDecoration(
                            labelText: 'To location',
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
                          controller: distance,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Distance (km)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: quantity,
                          enabled: job?['sale_id'] == null,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Quantity *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: quantityUnit,
                          decoration: const InputDecoration(
                            labelText: 'Unit *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: rate,
                          enabled: job?['sale_id'] == null,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Rate *',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (job != null)
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'planned',
                          child: Text('Planned'),
                        ),
                        DropdownMenuItem(
                          value: 'in_progress',
                          child: Text('In Progress'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
                        ),
                        DropdownMenuItem(
                          value: 'cancelled',
                          child: Text('Cancelled'),
                        ),
                      ],
                      onChanged: job['sale_id'] != null
                          ? null
                          : (value) =>
                                setLocalState(() => status = value ?? status),
                    ),
                  if (job != null) const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(job == null ? 'Create Job' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      try {
        final result = await _transport.saveJob(
          tenantId: _tenantId,
          jobId: job?['id']?.toString(),
          locationId: locationId,
          customerId: customerId,
          vehicleId: vehicleId,
          date: serviceDate,
          from: from.text,
          to: to.text,
          distanceKm: double.tryParse(distance.text.trim()) ?? 0,
          quantity: double.tryParse(quantity.text.trim()) ?? 0,
          quantityUnit: quantityUnit.text,
          rate: double.tryParse(rate.text.trim()) ?? 0,
          notes: notes.text,
          status: status,
        );
        _message('${result['job_number']} saved.');
        await _load();
      } catch (error) {
        _message(_clean(error));
      }
    }

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

  Future<void> _setStatus(Map<String, dynamic> job, String status) async {
    try {
      await _transport.setJobStatus(
        tenantId: _tenantId,
        jobId: job['id'].toString(),
        status: status,
      );
      await _load();
    } catch (error) {
      _message(_clean(error));
    }
  }

  Future<void> _billJob(Map<String, dynamic> job) async {
    if (job['sale_id'] != null) {
      _message(
        'This service job is already linked to ${job['sale_number'] ?? 'a sale'}.',
      );
      return;
    }
    if (job['status'] == 'cancelled') {
      _message('Cancelled service jobs cannot be billed.');
      return;
    }
    if (job['customer_id'] == null) {
      _message('Assign a customer to the service job before billing.');
      return;
    }
    if (_billingProducts.isEmpty) {
      _message('Create an active Service or Non-stock inventory item first.');
      return;
    }

    InventoryProduct selected = _billingProducts.first;
    String paymentMethod = 'cash';
    String paymentReference = '';
    bool paidNow = true;
    Map<String, dynamic> quote;
    try {
      quote = await _transport.quoteJobBill(
        tenantId: _tenantId,
        jobId: job['id'].toString(),
        billingVariantId: selected.variantId,
      );
    } catch (error) {
      _message(_clean(error));
      return;
    }
    if (!mounted) return;

    String? quoteError;
    bool quoteLoading = false;
    final referenceController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final totals = _map(quote['totals']);
          final taxable = _number(totals['taxable_value']);
          final tax = _number(totals['tax_collected_total']);
          final grandTotal = _number(totals['grand_total']);
          final cgst = _number(totals['cgst']);
          final sgst = _number(totals['sgst']);
          final utgst = _number(totals['utgst']);
          final igst = _number(totals['igst']);
          final cess = _number(totals['cess']);
          final ready = quote['ready_for_compliance'] == true;
          final supply = quote['supply_type']?.toString() ?? '-';
          final pos = quote['place_of_supply_code']?.toString() ?? '-';

          Future<void> refreshQuote(InventoryProduct product) async {
            setLocalState(() {
              selected = product;
              quoteLoading = true;
              quoteError = null;
            });
            try {
              final next = await _transport.quoteJobBill(
                tenantId: _tenantId,
                jobId: job['id'].toString(),
                billingVariantId: product.variantId,
              );
              if (!dialogContext.mounted) return;
              setLocalState(() {
                quote = next;
                quoteLoading = false;
              });
            } catch (error) {
              if (!dialogContext.mounted) return;
              setLocalState(() {
                quoteError = _clean(error);
                quoteLoading = false;
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 10),
                Expanded(child: Text('Bill ${job['job_number']}')),
              ],
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Creates a posted Sale through the authoritative GST v5.2 service writer.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SearchableSelect<String>(
                      value: selected.variantId,
                      labelText: 'Billing service item',
                      isRequired: true,
                      hintText: 'Search service, SKU, barcode or part number',
                      prefixIcon: Icons.search_outlined,
                      options: _billingProducts
                          .map(
                            (product) => SearchableSelectOption<String>(
                              value: product.variantId,
                              label: product.productName,
                              subtitle:
                                  [
                                        product.sku,
                                        product.barcode,
                                        product.partNumber,
                                      ]
                                      .where(
                                        (v) =>
                                            v != null &&
                                            v.toString().trim().isNotEmpty,
                                      )
                                      .join(' • '),
                              searchText:
                                  '${product.productName} ${product.variantName} ${product.sku} ${product.barcode ?? ''} ${product.partNumber ?? ''} ${product.searchCodes}',
                            ),
                          )
                          .toList(),
                      onChanged: quoteLoading
                          ? null
                          : (variantId) {
                              if (variantId == null ||
                                  variantId == selected.variantId) {
                                return;
                              }
                              final product = _billingProducts.firstWhere(
                                (item) => item.variantId == variantId,
                              );
                              refreshQuote(product);
                            },
                    ),
                    if (quoteLoading) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                    ],
                    if (quoteError != null) ...[
                      const SizedBox(height: 10),
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(quoteError!),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Wrap(
                              spacing: 24,
                              runSpacing: 10,
                              children: [
                                _quoteValue('Taxable', _money(taxable)),
                                _quoteValue('GST', _money(tax)),
                                _quoteValue(
                                  'Invoice total',
                                  _money(grandTotal),
                                  strong: true,
                                ),
                              ],
                            ),
                            const Divider(height: 22),
                            Wrap(
                              spacing: 18,
                              runSpacing: 8,
                              children: [
                                if (cgst != 0)
                                  _quoteValue('CGST', _money(cgst)),
                                if (sgst != 0)
                                  _quoteValue('SGST', _money(sgst)),
                                if (utgst != 0)
                                  _quoteValue('UTGST', _money(utgst)),
                                if (igst != 0)
                                  _quoteValue('IGST', _money(igst)),
                                if (cess != 0)
                                  _quoteValue('Cess', _money(cess)),
                                _quoteValue(
                                  'Supply',
                                  supply.replaceAll('_', ' ').toUpperCase(),
                                ),
                                _quoteValue('POS', pos),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'GST preview is calculated by the server. Flutter does not calculate tax.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Receive full payment now'),
                      subtitle: Text(
                        paidNow
                            ? 'Payment will use the authoritative invoice total above.'
                            : 'Invoice will be created on credit with a 30-day due date.',
                      ),
                      value: paidNow,
                      onChanged: quoteLoading || quoteError != null || !ready
                          ? null
                          : (value) => setLocalState(() => paidNow = value),
                    ),
                    if (paidNow) ...[
                      DropdownButtonFormField<String>(
                        initialValue: paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Payment method',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Cash')),
                          DropdownMenuItem(value: 'upi', child: Text('UPI')),
                          DropdownMenuItem(value: 'card', child: Text('Card')),
                          DropdownMenuItem(value: 'bank', child: Text('Bank')),
                          DropdownMenuItem(
                            value: 'cheque',
                            child: Text('Cheque'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) => setLocalState(
                          () => paymentMethod = value ?? paymentMethod,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Payment reference (optional)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => paymentReference = value,
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
              FilledButton.icon(
                onPressed:
                    quoteLoading ||
                        quoteError != null ||
                        !ready ||
                        grandTotal < 0
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Create & Link Sale'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final totals = _map(quote['totals']);
        final invoiceTotal = _number(totals['grand_total']);
        final result = await _transport.billJob(
          tenantId: _tenantId,
          jobId: job['id'].toString(),
          billingVariantId: selected.variantId,
          dueDate: paidNow
              ? null
              : DateTime.now().add(const Duration(days: 30)),
          initialPayment: paidNow ? invoiceTotal : 0,
          paymentMethod: paidNow ? paymentMethod : 'credit',
          paymentReference: paymentReference,
        );
        final invoiceNumber =
            result['invoice_number']?.toString() ??
            result['sale_number']?.toString() ??
            'Sale';
        _message('$invoiceNumber created and linked to ${job['job_number']}.');
        await _load();
      } catch (error) {
        _message(_clean(error));
      }
    }
    referenceController.dispose();
  }

  Future<void> _linkExistingSale(Map<String, dynamic> job) async {
    if (job['sale_id'] != null) return;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Link Sale to ${job['job_number']}'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Sale number',
              hintText: 'SAL-000001',
              border: OutlineInputBorder(),
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
            child: const Text('Link'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await _transport.linkSaleByReference(
          tenantId: _tenantId,
          jobId: job['id'].toString(),
          saleNumber: controller.text,
        );
        _message('Sale linked.');
        await _load();
      } catch (error) {
        _message(_clean(error));
      }
    }
    controller.dispose();
  }

  Widget _vehicleCard(Map<String, dynamic> vehicle) {
    final active = vehicle['active'] != false;
    return SizedBox(
      width: 330,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    color: active ? Colors.green.shade700 : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      vehicle['registration_number']?.toString() ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_canManage)
                    IconButton(
                      tooltip: 'Edit vehicle',
                      onPressed: () => _vehicleDialog(vehicle),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                ],
              ),
              Text(
                '${vehicle['vehicle_type'] ?? '-'} • ${vehicle['make_model'] ?? '-'}',
              ),
              Text(
                'Driver: ${vehicle['driver_name'] ?? '-'} • ${vehicle['driver_phone'] ?? '-'}',
              ),
              Text(
                'Capacity: ${vehicle['capacity'] ?? 0} ${vehicle['capacity_unit'] ?? ''}',
              ),
              Text(
                '${vehicle['open_jobs'] ?? 0} open jobs • ${active ? 'ACTIVE' : 'INACTIVE'}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> job) {
    final status = job['status']?.toString() ?? 'planned';
    final billed = job['sale_id'] != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.route_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${job['job_number'] ?? ''} • ${job['registration_number'] ?? 'No vehicle'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(status.replaceAll('_', ' ').toUpperCase()),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(billed ? 'BILLED' : 'UNBILLED'),
                      ),
                    ],
                  ),
                  Text(
                    '${job['from_location'] ?? '-'} → ${job['to_location'] ?? '-'} • ${job['distance_km'] ?? 0} km • ${job['service_date'] ?? '-'}',
                  ),
                  Text(
                    'Qty ${job['quantity'] ?? 0} ${job['quantity_unit'] ?? ''} × ${_money(job['rate'])} • Customer: ${job['customer_name'] ?? 'Not assigned'}',
                  ),
                  Text(
                    billed
                        ? 'Sale: ${job['sale_number'] ?? job['sale_id']} • ${job['sale_status'] ?? ''}'
                        : 'Tracking: ${job['tracking_code'] ?? '-'}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _money(job['total_amount']),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    if (_canCreate && !billed && status != 'cancelled')
                      FilledButton.tonal(
                        onPressed: () => _billJob(job),
                        child: const Text('Bill'),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Service actions',
                      onSelected: (value) {
                        if (value == 'edit') {
                          _jobDialog(job);
                        } else if (value == 'start') {
                          _setStatus(job, 'in_progress');
                        } else if (value == 'complete') {
                          _setStatus(job, 'completed');
                        } else if (value == 'cancel') {
                          _setStatus(job, 'cancelled');
                        } else if (value == 'link') {
                          _linkExistingSale(job);
                        }
                      },
                      itemBuilder: (_) => [
                        if (_canManage)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                        if (_canCreate && !billed && status == 'planned')
                          const PopupMenuItem(
                            value: 'start',
                            child: Text('Start'),
                          ),
                        if (_canCreate &&
                            !billed &&
                            status != 'completed' &&
                            status != 'cancelled')
                          const PopupMenuItem(
                            value: 'complete',
                            child: Text('Mark completed'),
                          ),
                        if (_canCreate && !billed && status != 'cancelled')
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Cancel job'),
                          ),
                        if (_canCreate && !billed)
                          const PopupMenuItem(
                            value: 'link',
                            child: Text('Link existing sale'),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 178,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quoteValue(String label, String value, {bool strong = false}) {
    return SizedBox(
      width: 145,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 17 : 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final scheme = Theme.of(context).colorScheme;
    final activeVehicles = _vehicles.where((v) => v['active'] != false).length;
    final unbilled = _jobs.where((j) => j['sale_id'] == null).length;
    final scope = widget.session.device?.locationName.trim().isNotEmpty == true
        ? widget.session.device!.locationName
        : 'Current store scope';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                  if (_canManage)
                    FilledButton.tonalIcon(
                      onPressed: () => _vehicleDialog(),
                      icon: const Icon(Icons.local_shipping_outlined, size: 18),
                      label: const Text('Add Vehicle'),
                    ),
                  if (_canCreate)
                    FilledButton.icon(
                      onPressed: () => _jobDialog(),
                      icon: const Icon(Icons.add_road, size: 18),
                      label: const Text('New Service Job'),
                    ),
                ],
              );

              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transport / Service',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Customer transport jobs, vehicle assignment, route tracking and GST-linked Sales billing.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
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
          if (_error != null) ...[
            const SizedBox(height: 10),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryTile(
                icon: Icons.local_shipping_outlined,
                label: 'Active vehicles',
                value: '$activeVehicles',
              ),
              _summaryTile(
                icon: Icons.route_outlined,
                label: 'Visible jobs',
                value: '${_jobs.length}',
              ),
              _summaryTile(
                icon: Icons.receipt_long_outlined,
                label: 'Unbilled',
                value: '$unbilled',
              ),
              _summaryTile(
                icon: Icons.store_outlined,
                label: 'Scope',
                value: scope,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fleet',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Shared vehicle master used by Transport / Service and Logistics Operations.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                '${_vehicles.length} vehicle${_vehicles.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_vehicles.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'No vehicles yet. A vehicle is optional for a service job.',
                ),
              ),
            )
          else
            SizedBox(
              height: 164,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _vehicles.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) => _vehicleCard(_vehicles[index]),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Service Jobs',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${_jobs.length} shown',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'planned', label: Text('Planned')),
                ButtonSegment(value: 'in_progress', label: Text('In progress')),
                ButtonSegment(value: 'completed', label: Text('Completed')),
                ButtonSegment(value: 'cancelled', label: Text('Cancelled')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (value) {
                setState(() => _statusFilter = value.first);
                _load();
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_jobs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Center(
                  child: Text('No service jobs found for this filter.'),
                ),
              ),
            )
          else
            ..._jobs.map(_jobCard),
        ],
      ),
    );
  }
}
