import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';

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
      final rows = await _service.loads(
        tenantId: widget.session.business.id,
        locationId: _locationId,
        status: null,
        query: _search.text.trim(),
      );

      _rows = switch (_status) {
        'draft' =>
          rows
              .where((row) => _simpleStatus(row) == 'draft')
              .toList(growable: false),
        'completed' =>
          rows
              .where((row) => _simpleStatus(row) == 'confirmed')
              .toList(growable: false),
        'cancelled' =>
          rows
              .where((row) => _simpleStatus(row) == 'cancelled')
              .toList(growable: false),
        _ => rows,
      };
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

  String? _id(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? null : text;
  }

  String _simpleStatus(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    if (status == 'completed') return 'confirmed';
    if (status == 'cancelled') return 'cancelled';
    return 'draft';
  }

  bool _hasProtectedLinks(Map<String, dynamic> row) {
    return _id(row['purchase_id']) != null ||
        _id(row['sale_id']) != null ||
        _id(row['order_id']) != null;
  }

  bool _canConfirm(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    return status != 'completed' && status != 'cancelled';
  }

  bool _canEdit(Map<String, dynamic> row) =>
      _canConfirm(row) && !_hasProtectedLinks(row);

  bool _canDelete(Map<String, dynamic> row) =>
      row['status']?.toString() != 'completed' && !_hasProtectedLinks(row);

  Future<void> _confirmLoad(Map<String, dynamic> row) async {
    if (!_canConfirm(row)) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Load'),
        content: Text(
          'Confirm ${row['load_number']}?\n\n'
          'After confirmation this load is read-only in the Load Register.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm Load'),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) return;

    try {
      await _service.confirmLoad(
        tenantId: widget.session.business.id,
        loadId: row['load_id'].toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Load confirmed.')));
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteLoad(Map<String, dynamic> row) async {
    if (!_canDelete(row)) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Load'),
        content: Text(
          'Delete ${row['load_number']}?\n\n'
          'This removes the unconfirmed Load Ticket and its operational history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete Load'),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) return;

    try {
      await _service.deleteLoad(
        tenantId: widget.session.business.id,
        loadId: row['load_id'].toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Load deleted.')));
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _editLoad(Map<String, dynamic> row) async {
    if (!_canEdit(row)) return;

    try {
      final detail = await _service.loadDetail(
        tenantId: widget.session.business.id,
        loadId: row['load_id'].toString(),
      );
      if (!mounted) return;

      final products = _list('products');
      final vehicles = _list('vehicles');
      final drivers = _list('drivers');
      final suppliers = _list('suppliers');
      final customers = _list('customers');
      final locations = _list('locations');

      String direction = detail['direction']?.toString() == 'outbound'
          ? 'outbound'
          : 'inbound';
      String measurement =
          detail['measurement_method']?.toString() == 'dimensions'
          ? 'dimensions'
          : 'manual';
      String unit = _id(detail['unit_code']) ?? 'CFT';

      final unitCodes = <String>{
        'CFT',
        'CBM',
        'TON',
        'LOAD',
        'BRASS',
        unit,
      }.toList();

      String? validSelection(
        List<Map<String, dynamic>> rows,
        String key,
        dynamic raw,
      ) {
        final value = _id(raw);
        if (value == null) return null;
        return rows.any((entry) => _id(entry[key]) == value) ? value : null;
      }

      String? productId = validSelection(
        products,
        'variant_id',
        detail['variant_id'],
      );
      String? vehicleId = validSelection(
        vehicles,
        'vehicle_id',
        detail['vehicle_id'],
      );
      String? driverId = validSelection(
        drivers,
        'driver_id',
        detail['driver_id'],
      );
      String? supplierId = validSelection(
        suppliers,
        'supplier_id',
        detail['supplier_id'],
      );
      String? customerId = validSelection(
        customers,
        'customer_id',
        detail['customer_id'],
      );
      String? locationId = validSelection(
        locations,
        'location_id',
        detail['location_id'],
      );

      final quantity = TextEditingController(
        text: '${detail['quantity'] ?? ''}',
      );
      final length = TextEditingController(
        text: _id(detail['body_length_ft']) ?? '',
      );
      final width = TextEditingController(
        text: _id(detail['body_width_ft']) ?? '',
      );
      final height = TextEditingController(
        text: _id(detail['body_height_ft']) ?? '',
      );
      final source = TextEditingController(
        text: _id(detail['source_name']) ?? '',
      );
      final destination = TextEditingController(
        text: _id(detail['destination_name']) ?? '',
      );
      final reference = TextEditingController(
        text: _id(detail['source_reference']) ?? '',
      );
      String freightMode = _id(detail['freight_mode']) ?? 'none';
      final freight = TextEditingController(
        text: '${detail['freight_amount'] ?? 0}',
      );
      bool capacityOverride = detail['capacity_override'] == true;
      final overrideReason = TextEditingController(
        text: _id(detail['capacity_override_reason']) ?? '',
      );
      final notes = TextEditingController(text: _id(detail['notes']) ?? '');

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
                title: Text('Edit ${detail['load_number']}'),
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
                                    child: Text('Inbound | Quarry â†’ Yard'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'outbound',
                                    child: Text('Outbound | Yard â†’ Customer'),
                                  ),
                                ],
                                onChanged: (value) => setLocalState(() {
                                  direction = value ?? 'inbound';
                                  if (direction == 'inbound') {
                                    customerId = null;
                                  } else {
                                    supplierId = null;
                                  }
                                }),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: locationId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Yard / Store',
                                ),
                                items: locations
                                    .map(
                                      (entry) => DropdownMenuItem<String>(
                                        value: entry['location_id']?.toString(),
                                        child: Text(
                                          '${entry['code'] ?? ''} | ${entry['name'] ?? ''}',
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
                                (entry) => DropdownMenuItem<String>(
                                  value: entry['variant_id']?.toString(),
                                  child: Text(
                                    '${entry['name'] ?? ''}'
                                    '${(entry['variant_name'] ?? '').toString().trim().isEmpty ? '' : ' | ${entry['variant_name']}'}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setLocalState(() => productId = value),
                        ),
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
                                items: unitCodes
                                    .map(
                                      (code) => DropdownMenuItem(
                                        value: code,
                                        child: Text(code),
                                      ),
                                    )
                                    .toList(),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ] else
                          TextField(
                            controller: quantity,
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
                                      (entry) => DropdownMenuItem<String>(
                                        value: entry['vehicle_id']?.toString(),
                                        child: Text(
                                          '${entry['registration_number'] ?? ''}',
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
                                      (entry) => DropdownMenuItem<String>(
                                        value: entry['driver_id']?.toString(),
                                        child: Text(
                                          '${entry['name'] ?? ''}',
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
                        if (direction == 'inbound')
                          DropdownButtonFormField<String>(
                            initialValue: supplierId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Supplier / Quarry company',
                            ),
                            items: suppliers
                                .map(
                                  (entry) => DropdownMenuItem<String>(
                                    value: entry['supplier_id']?.toString(),
                                    child: Text(
                                      '${entry['name'] ?? ''}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setLocalState(() => supplierId = value),
                          )
                        else
                          DropdownButtonFormField<String>(
                            initialValue: customerId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Customer',
                            ),
                            items: customers
                                .map(
                                  (entry) => DropdownMenuItem<String>(
                                    value: entry['customer_id']?.toString(),
                                    child: Text(
                                      '${entry['name'] ?? ''}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setLocalState(() => customerId = value),
                          ),
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: destination,
                                decoration: const InputDecoration(
                                  labelText: 'Destination',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: reference,
                          decoration: const InputDecoration(
                            labelText: 'Reference',
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
                                    child: Text('Own'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'hired',
                                    child: Text('Hired'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'supplier',
                                    child: Text('Supplier'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'customer',
                                    child: Text('Customer'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'included',
                                    child: Text('Included'),
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
                                  labelText: 'Freight amount',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Override truck capacity'),
                          value: capacityOverride,
                          onChanged: (value) =>
                              setLocalState(() => capacityOverride = value),
                        ),
                        if (capacityOverride)
                          TextField(
                            controller: overrideReason,
                            decoration: const InputDecoration(
                              labelText: 'Capacity override reason',
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
                      if (productId == null || locationId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select a store and material.'),
                          ),
                        );
                        return;
                      }

                      final editedQuantity = measurement == 'dimensions'
                          ? calculated
                          : (_double(quantity.text) ?? 0);
                      if (editedQuantity <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Quantity must be greater than zero.',
                            ),
                          ),
                        );
                        return;
                      }

                      try {
                        await _service.editLoad(
                          tenantId: widget.session.business.id,
                          loadId: row['load_id'].toString(),
                          direction: direction,
                          locationId: locationId,
                          variantId: productId!,
                          quantity: editedQuantity,
                          unitCode: measurement == 'dimensions' ? 'CFT' : unit,
                          measurementMethod: measurement,
                          bodyLengthFt: _double(length.text),
                          bodyWidthFt: _double(width.text),
                          bodyHeightFt: _double(height.text),
                          vehicleId: vehicleId,
                          driverId: driverId,
                          supplierId: direction == 'inbound'
                              ? supplierId
                              : null,
                          customerId: direction == 'outbound'
                              ? customerId
                              : null,
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    },
                    child: const Text('Save Changes'),
                  ),
                ],
              );
            },
          ),
        );

        if (saved == true) {
          await _reload();
        }
      } finally {
        quantity.dispose();
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _loadActions(Map<String, dynamic> row) {
    final scheme = Theme.of(context).colorScheme;
    final canConfirm = _canConfirm(row);
    final canEdit = _canEdit(row);
    final canDelete = _canDelete(row);

    return SizedBox(
      width: 420,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Chip(
            label: Text(_simpleStatus(row)),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          FilledButton.tonalIcon(
            onPressed: canConfirm ? () => _confirmLoad(row) : null,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Confirm'),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: canEdit ? () => _editLoad(row) : null,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: canDelete ? () => _deleteLoad(row) : null,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
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
                        value: 'completed',
                        child: Text('Confirmed'),
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
                          trailing: _loadActions(row),
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
