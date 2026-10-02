import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import 'purchases_screen.dart';
import 'sales_screen.dart';

class AggregateLoadsScreen extends StatefulWidget {
  final ClientSession session;
  final String? initialCreateDirection;

  const AggregateLoadsScreen({
    super.key,
    required this.session,
    this.initialCreateDirection,
  });

  @override
  State<AggregateLoadsScreen> createState() => _AggregateLoadsScreenState();
}

class _AggregateLoadsScreenState extends State<AggregateLoadsScreen> {
  final AggregateYardService _service = AggregateYardService();
  final TextEditingController _search = TextEditingController();

  Map<String, dynamic> _context = const {};
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _status;
  bool _autoCreateOpened = false;

  String? get _locationId => LocationScopeService.selectedLocationId.value;

  List<Map<String, dynamic>> _list(String key) =>
      (_context[key] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  @override
  void initState() {
    super.initState();
    _reload(all: true).then((_) {
      if (!mounted ||
          _autoCreateOpened ||
          widget.initialCreateDirection == null) {
        return;
      }
      _autoCreateOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _createLoad(initialDirection: widget.initialCreateDirection);
        }
      });
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload({bool all = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      if (all || _context.isEmpty) {
        _context = await _service.context(tenantId: widget.session.business.id);
      }
      _rows = await _service.loads(
        tenantId: widget.session.business.id,
        locationId: _locationId,
        status: _status,
        query: _search.text.trim(),
      );
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _double(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  Future<void> _createLoad({String? initialDirection}) async {
    final products = _list('products');
    final vehicles = _list('vehicles');
    final drivers = _list('drivers');
    final suppliers = _list('suppliers');
    final customers = _list('customers');
    final locations = _list('locations');

    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one product first.')),
      );
      return;
    }

    String direction = initialDirection == 'direct_delivery'
        ? 'inbound'
        : initialDirection ?? 'inbound';
    String measurement = 'manual';
    String unit = 'CFT';
    String? productId;
    String? vehicleId;
    String? driverId;
    String? supplierId;
    String? customerId;
    String? locationId = _locationId;
    String freightMode = 'none';
    bool capacityOverride = false;

    final qty = TextEditingController();
    final length = TextEditingController();
    final width = TextEditingController();
    final height = TextEditingController();
    final source = TextEditingController();
    final destination = TextEditingController();
    final reference = TextEditingController();
    final freight = TextEditingController(text: '0');
    final overrideReason = TextEditingController();
    final notes = TextEditingController();

    try {
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            final calculated =
                (_double(length.text) ?? 0) *
                (_double(width.text) ?? 0) *
                (_double(height.text) ?? 0);

            return AlertDialog(
              title: const Text('New Load Ticket'),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: direction,
                              decoration: const InputDecoration(
                                labelText: 'Direction',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'inbound',
                                  child: Text('Inbound | Quarry → Yard'),
                                ),
                                DropdownMenuItem(
                                  value: 'outbound',
                                  child: Text('Outbound | Yard → Customer'),
                                ),
                              ],
                              onChanged: (value) => setLocalState(
                                () => direction = value ?? 'inbound',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: locationId,
                              decoration: const InputDecoration(
                                labelText: 'Yard / Store',
                              ),
                              items: locations
                                  .map(
                                    (row) => DropdownMenuItem<String>(
                                      value: row['location_id']?.toString(),
                                      child: Text(
                                        '${row['code'] ?? ''} | ${row['name'] ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setLocalState(() => locationId = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: productId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Material',
                        ),
                        items: products
                            .map(
                              (row) => DropdownMenuItem<String>(
                                value: row['variant_id']?.toString(),
                                child: Text(
                                  '${row['name'] ?? ''}'
                                  '${(row['variant_name'] ?? '').toString().trim().isEmpty ? '' : ' | ${row['variant_name']}'}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setLocalState(() => productId = value),
                      ),
                      if (direction == 'direct_delivery') ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiaryContainer
                                .withValues(alpha: .55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Direct delivery is available for operational '
                            'tracking only in this stage. Purchase/Sale posting '
                            'is locked until the transit-stock workflow is installed.',
                            style: TextStyle(fontSize: 10.5, height: 1.3),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: measurement,
                              decoration: const InputDecoration(
                                labelText: 'Measurement',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'manual',
                                  child: Text('Manual quantity'),
                                ),
                                DropdownMenuItem(
                                  value: 'dimensions',
                                  child: Text('Truck dimensions'),
                                ),
                              ],
                              onChanged: (value) => setLocalState(
                                () => measurement = value ?? 'manual',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: unit,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'CFT',
                                  child: Text('CFT'),
                                ),
                                DropdownMenuItem(
                                  value: 'CBM',
                                  child: Text('CBM'),
                                ),
                                DropdownMenuItem(
                                  value: 'TON',
                                  child: Text('TON'),
                                ),
                                DropdownMenuItem(
                                  value: 'LOAD',
                                  child: Text('LOAD'),
                                ),
                                DropdownMenuItem(
                                  value: 'BRASS',
                                  child: Text('BRASS'),
                                ),
                              ],
                              onChanged: measurement == 'dimensions'
                                  ? null
                                  : (value) => setLocalState(
                                      () => unit = value ?? 'CFT',
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (measurement == 'dimensions') ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: length,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Length ft',
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
                                  labelText: 'Width ft',
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
                                  labelText: 'Height ft',
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
                            'Calculated: ${calculated.toStringAsFixed(3)} CFT',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ] else
                        TextField(
                          controller: qty,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: vehicleId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Truck / Vehicle',
                              ),
                              items: vehicles
                                  .map(
                                    (row) => DropdownMenuItem<String>(
                                      value: row['vehicle_id']?.toString(),
                                      child: Text(
                                        '${row['registration_number'] ?? ''}'
                                        '${row['nominal_capacity_cft'] == null ? '' : ' | ${row['nominal_capacity_cft']} CFT'}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setLocalState(() => vehicleId = value),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: driverId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Driver',
                              ),
                              items: drivers
                                  .map(
                                    (row) => DropdownMenuItem<String>(
                                      value: row['driver_id']?.toString(),
                                      child: Text(
                                        '${row['name'] ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setLocalState(() => driverId = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (direction == 'inbound' ||
                          direction == 'direct_delivery')
                        DropdownButtonFormField<String>(
                          initialValue: supplierId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Supplier / Quarry company',
                          ),
                          items: suppliers
                              .map(
                                (row) => DropdownMenuItem<String>(
                                  value: row['supplier_id']?.toString(),
                                  child: Text(
                                    '${row['name'] ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setLocalState(() => supplierId = value),
                        ),
                      if (direction == 'outbound' ||
                          direction == 'direct_delivery') ...[
                        if (direction == 'direct_delivery')
                          const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: customerId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Customer',
                          ),
                          items: customers
                              .map(
                                (row) => DropdownMenuItem<String>(
                                  value: row['customer_id']?.toString(),
                                  child: Text(
                                    '${row['name'] ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setLocalState(() => customerId = value),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: source,
                              decoration: const InputDecoration(
                                labelText: 'Source / Quarry',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: destination,
                              decoration: const InputDecoration(
                                labelText: 'Destination / Site',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reference,
                        decoration: const InputDecoration(
                          labelText: 'Quarry slip / reference',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: freightMode,
                              decoration: const InputDecoration(
                                labelText: 'Freight',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'none',
                                  child: Text('None'),
                                ),
                                DropdownMenuItem(
                                  value: 'own',
                                  child: Text('Own vehicle'),
                                ),
                                DropdownMenuItem(
                                  value: 'hired',
                                  child: Text('Hired transporter'),
                                ),
                                DropdownMenuItem(
                                  value: 'supplier',
                                  child: Text('Supplier delivery'),
                                ),
                                DropdownMenuItem(
                                  value: 'customer',
                                  child: Text('Customer vehicle'),
                                ),
                                DropdownMenuItem(
                                  value: 'included',
                                  child: Text('Included in rate'),
                                ),
                              ],
                              onChanged: (value) => setLocalState(
                                () => freightMode = value ?? 'none',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: freight,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Freight cost',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: capacityOverride,
                        title: const Text('Allow capacity override'),
                        subtitle: const Text(
                          'Requires permission and a reason if this load exceeds configured truck capacity.',
                        ),
                        onChanged: (value) =>
                            setLocalState(() => capacityOverride = value),
                      ),
                      if (capacityOverride)
                        TextField(
                          controller: overrideReason,
                          decoration: const InputDecoration(
                            labelText: 'Override reason',
                          ),
                        ),
                      const SizedBox(height: 10),
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
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (productId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Select a material.')),
                      );
                      return;
                    }
                    final quantity = measurement == 'dimensions'
                        ? calculated
                        : (_double(qty.text) ?? 0);
                    if (quantity <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a positive quantity.'),
                        ),
                      );
                      return;
                    }
                    try {
                      await _service.createLoad(
                        tenantId: widget.session.business.id,
                        direction: direction,
                        locationId: locationId,
                        variantId: productId!,
                        quantity: quantity,
                        unitCode: measurement == 'dimensions' ? 'CFT' : unit,
                        measurementMethod: measurement,
                        bodyLengthFt: _double(length.text),
                        bodyWidthFt: _double(width.text),
                        bodyHeightFt: _double(height.text),
                        vehicleId: vehicleId,
                        driverId: driverId,
                        supplierId: supplierId,
                        customerId: customerId,
                        sourceName: source.text,
                        destinationName: destination.text,
                        sourceReference: reference.text,
                        freightMode: freightMode,
                        freightAmount: _double(freight.text) ?? 0,
                        capacityOverride: capacityOverride,
                        capacityOverrideReason: overrideReason.text,
                        notes: notes.text,
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
                  child: const Text('Create Draft Load'),
                ),
              ],
            );
          },
        ),
      );

      if (created == true) await _reload();
    } finally {
      qty.dispose();
      length.dispose();
      width.dispose();
      height.dispose();
      source.dispose();
      destination.dispose();
      reference.dispose();
      freight.dispose();
      overrideReason.dispose();
      notes.dispose();
    }
  }

  List<String> _nextStatuses(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    final direction = row['direction']?.toString() ?? '';
    return switch (status) {
      'draft' => const ['loading', 'cancelled'],
      'loading' => const ['dispatched', 'in_transit', 'cancelled'],
      'dispatched' => const ['in_transit', 'arrived', 'cancelled'],
      'in_transit' => const ['arrived', 'cancelled'],
      'arrived' =>
        direction == 'inbound'
            ? const ['received', 'cancelled']
            : const ['delivered', 'cancelled'],
      'received' || 'delivered' => const ['completed'],
      _ => const [],
    };
  }

  String? _id(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? null : text;
  }

  String _loadTransactionNote(Map<String, dynamic> row) {
    final parts = <String>[
      'Material Yard Load ${row['load_number'] ?? ''}',
      if (_id(row['vehicle_registration']) != null)
        'Truck ${row['vehicle_registration']}',
      if (_id(row['driver_name']) != null) 'Driver ${row['driver_name']}',
      if (_id(row['source_name']) != null) 'From ${row['source_name']}',
      if (_id(row['destination_name']) != null) 'To ${row['destination_name']}',
      if (_id(row['source_reference']) != null)
        'Ref ${row['source_reference']}',
    ];
    return parts.join(' | ');
  }

  Future<void> _postPurchaseForLoad(Map<String, dynamic> row) async {
    if (_id(row['purchase_id']) != null) return;

    final locationId = _id(row['location_id']) ?? _locationId;
    if (locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a specific yard / store before posting the Purchase.',
          ),
        ),
      );
      return;
    }

    String? createdPurchaseId;

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewPurchaseScreen(
          session: widget.session,
          locationId: locationId,
          initialSupplierId: _id(row['supplier_id']),
          initialVariantId: _id(row['variant_id']),
          initialQuantity: double.tryParse('${row['quantity'] ?? ''}'),
          initialUnitCode: _id(row['unit_code']),
          initialSupplierInvoiceNumber: _id(row['source_reference']),
          initialNotes: _loadTransactionNote(row),
          onCreated: (purchaseId) => createdPurchaseId = purchaseId,
        ),
      ),
    );

    if (!mounted) return;
    if (completed != true || createdPurchaseId == null) return;

    try {
      await _service.linkDocument(
        tenantId: widget.session.business.id,
        loadId: row['load_id'].toString(),
        documentType: 'purchase',
        documentId: createdPurchaseId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase posted and linked to the Load Ticket.'),
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Purchase $createdPurchaseId was posted successfully, but the '
            'Load Ticket link was rejected: $error\n'
            'Do not post the Purchase again. Correct the load/document and link it.',
          ),
        ),
      );
    }
  }

  Future<void> _postSaleForLoad(Map<String, dynamic> row) async {
    if (_id(row['sale_id']) != null) return;

    final locationId = _id(row['location_id']) ?? _locationId;
    if (locationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a specific yard / store before posting the Sale.',
          ),
        ),
      );
      return;
    }

    String? createdSaleId;

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewSaleScreen(
          session: widget.session,
          locationId: locationId,
          initialCustomerId: _id(row['customer_id']),
          initialVariantId: _id(row['variant_id']),
          initialQuantity: double.tryParse('${row['quantity'] ?? ''}'),
          initialUnitCode: _id(row['unit_code']),
          initialNotes: _loadTransactionNote(row),
          onCreated: (saleId) => createdSaleId = saleId,
        ),
      ),
    );

    if (!mounted) return;
    if (completed != true || createdSaleId == null) return;

    try {
      await _service.linkDocument(
        tenantId: widget.session.business.id,
        loadId: row['load_id'].toString(),
        documentType: 'sale',
        documentId: createdSaleId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale posted and linked to the Load Ticket.'),
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Sale $createdSaleId was posted successfully, but the '
            'Load Ticket link was rejected: $error\n'
            'Do not post the Sale again. Correct the load/document and link it.',
          ),
        ),
      );
    }
  }

  Future<void> _handleAction(Map<String, dynamic> row, String action) async {
    if (action == 'post_purchase') {
      await _postPurchaseForLoad(row);
      return;
    }
    if (action == 'post_sale') {
      await _postSaleForLoad(row);
      return;
    }
    if (action.startsWith('status:')) {
      await _changeStatus(row, action.substring('status:'.length));
    }
  }

  Future<void> _changeStatus(Map<String, dynamic> row, String status) async {
    try {
      await _service.updateStatus(
        tenantId: widget.session.business.id,
        loadId: row['load_id'].toString(),
        status: status,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Load / Trip Register'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _reload(all: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _createLoad(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Load'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText:
                          'Load no, material, truck, driver, supplier, customer...',
                    ),
                    onSubmitted: (_) => _reload(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _status,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All'),
                      ),
                      DropdownMenuItem(value: 'draft', child: Text('Draft')),
                      DropdownMenuItem(
                        value: 'loading',
                        child: Text('Loading'),
                      ),
                      DropdownMenuItem(
                        value: 'in_transit',
                        child: Text('In transit'),
                      ),
                      DropdownMenuItem(
                        value: 'arrived',
                        child: Text('Arrived'),
                      ),
                      DropdownMenuItem(
                        value: 'received',
                        child: Text('Received'),
                      ),
                      DropdownMenuItem(
                        value: 'delivered',
                        child: Text('Delivered'),
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
                    onChanged: (value) {
                      setState(() => _status = value);
                      _reload();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? const Center(
                    child: Text(
                      'No load tickets yet.\nCreate the first truck load from + New Load.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final next = _nextStatuses(row);
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              row['direction'] == 'inbound'
                                  ? Icons.south_west_rounded
                                  : row['direction'] == 'outbound'
                                  ? Icons.north_east_rounded
                                  : Icons.compare_arrows_rounded,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            '${row['load_number']}  •  ${row['product_name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${row['quantity']} ${row['unit_code']}'
                            '  |  ${row['vehicle_registration'] ?? 'No truck'}'
                            '  |  ${row['driver_name'] ?? 'No driver'}'
                            '\n${row['source_name'] ?? row['supplier_name'] ?? ''}'
                            ' → ${row['destination_name'] ?? row['customer_name'] ?? ''}'
                            '${row['purchase_id'] == null ? '' : '  • Purchase linked'}'
                            '${row['sale_id'] == null ? '' : '  • Sale linked'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: SizedBox(
                            width: 190,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Chip(
                                    label: Text(
                                      (row['status'] ?? '')
                                          .toString()
                                          .replaceAll('_', ' '),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                if (next.isNotEmpty ||
                                    (row['status'] != 'cancelled' &&
                                        row['purchase_id'] == null &&
                                        row['direction'] == 'inbound') ||
                                    (row['status'] != 'cancelled' &&
                                        row['sale_id'] == null &&
                                        row['direction'] == 'outbound'))
                                  PopupMenuButton<String>(
                                    tooltip: 'Load actions',
                                    onSelected: (value) =>
                                        _handleAction(row, value),
                                    itemBuilder: (context) {
                                      final canPurchase =
                                          row['status'] != 'cancelled' &&
                                          row['purchase_id'] == null &&
                                          row['direction'] == 'inbound';
                                      final canSale =
                                          row['status'] != 'cancelled' &&
                                          row['sale_id'] == null &&
                                          row['direction'] == 'outbound';

                                      return <PopupMenuEntry<String>>[
                                        if (canPurchase)
                                          const PopupMenuItem(
                                            value: 'post_purchase',
                                            child: ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(
                                                Icons.shopping_cart_outlined,
                                              ),
                                              title: Text('Post THQ Purchase'),
                                            ),
                                          ),
                                        if (canSale)
                                          const PopupMenuItem(
                                            value: 'post_sale',
                                            child: ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(
                                                Icons.receipt_long_outlined,
                                              ),
                                              title: Text('Post THQ Sale'),
                                            ),
                                          ),
                                        if ((canPurchase || canSale) &&
                                            next.isNotEmpty)
                                          const PopupMenuDivider(),
                                        ...next.map(
                                          (value) => PopupMenuItem(
                                            value: 'status:$value',
                                            child: Text(
                                              'Mark ${value.replaceAll('_', ' ')}',
                                            ),
                                          ),
                                        ),
                                      ];
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
