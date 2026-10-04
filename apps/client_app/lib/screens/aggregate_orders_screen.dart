import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import 'aggregate_loads_screen.dart';

class AggregateOrdersScreen extends StatefulWidget {
  final ClientSession session;

  const AggregateOrdersScreen({super.key, required this.session});

  @override
  State<AggregateOrdersScreen> createState() => _AggregateOrdersScreenState();
}

class _AggregateOrdersScreenState extends State<AggregateOrdersScreen> {
  final AggregateYardService _service = AggregateYardService();
  final TextEditingController _search = TextEditingController();

  Map<String, dynamic> _context = const {};
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  String? _error;
  String? _status;

  String? get _locationId => LocationScopeService.selectedLocationId.value;

  List<Map<String, dynamic>> _list(String key) =>
      (_context[key] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  String _qty(dynamic value) {
    final number = _number(value);
    if ((number - number.roundToDouble()).abs() < 0.000001) {
      return number.toStringAsFixed(0);
    }
    return number.toStringAsFixed(2);
  }

  String? _id(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? null : text;
  }

  @override
  void initState() {
    super.initState();
    _reload(all: true);
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

      _orders = await _service.orders(
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

  Map<String, dynamic>? _product(String? variantId) {
    if (variantId == null) return null;
    for (final product in _list('products')) {
      if (product['variant_id']?.toString() == variantId) return product;
    }
    return null;
  }

  List<String> _unitCodes(Map<String, dynamic>? product) {
    if (product == null) return const [];

    final values = <String>{};
    final base = product['base_unit_code']?.toString().trim().toUpperCase();
    if (base != null && base.isNotEmpty) values.add(base);

    for (final unit in (product['sale_units'] as List? ?? const [])) {
      if (unit is! Map) continue;
      final code = unit['code']?.toString().trim().toUpperCase();
      if (code != null && code.isNotEmpty) values.add(code);
    }

    final result = values.toList();
    result.sort((a, b) {
      if (a == 'CFT') return -1;
      if (b == 'CFT') return 1;
      return a.compareTo(b);
    });
    return result;
  }

  String? _preferredUnit(Map<String, dynamic>? product) {
    final units = _unitCodes(product);
    if (units.contains('CFT')) return 'CFT';
    if (units.isNotEmpty) return units.first;
    return null;
  }

  Future<void> _createOrder() async {
    final customers = _list('customers');
    final products = _list('products');
    final locations = _list('locations');

    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a customer before creating an order.'),
        ),
      );
      return;
    }

    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a material product first.')),
      );
      return;
    }

    String? customerId;
    String? locationId = _locationId;
    if (locationId == null && locations.isNotEmpty) {
      locationId = locations.first['location_id']?.toString();
    }

    DateTime? requestedDate;
    final site = TextEditingController();
    final address = TextEditingController();
    final notes = TextEditingController();
    final lines = <_OrderDraftLine>[
      _OrderDraftLine(
        variantId: products.first['variant_id']?.toString(),
        unitCode: _preferredUnit(products.first),
      ),
    ];

    try {
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> pickDate() async {
              final value = await showDatePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
                initialDate: requestedDate ?? DateTime.now(),
              );
              if (value != null) {
                setLocalState(() => requestedDate = value);
              }
            }

            return AlertDialog(
              title: const Text('New Customer Order — no GST invoice'),
              content: SizedBox(
                width: 860,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
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
                                        '${row['name'] ?? ''}'
                                        '${(row['phone'] ?? '').toString().trim().isEmpty ? '' : ' • ${row['phone']}'}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setLocalState(() => customerId = value),
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
                                    (row) => DropdownMenuItem<String>(
                                      value: row['location_id']?.toString(),
                                      child: Text(
                                        '${row['code'] ?? ''} • ${row['name'] ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setLocalState(() => locationId = value),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: pickDate,
                            icon: const Icon(Icons.event_outlined, size: 16),
                            label: Text(
                              requestedDate == null
                                  ? 'Requested date'
                                  : '${requestedDate!.day.toString().padLeft(2, '0')}/'
                                        '${requestedDate!.month.toString().padLeft(2, '0')}/'
                                        '${requestedDate!.year}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: site,
                              decoration: const InputDecoration(
                                labelText: 'Delivery site / project name',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: address,
                              decoration: const InputDecoration(
                                labelText: 'Delivery address',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Materials',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () {
                              final product = products.first;
                              setLocalState(
                                () => lines.add(
                                  _OrderDraftLine(
                                    variantId: product['variant_id']
                                        ?.toString(),
                                    unitCode: _preferredUnit(product),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add material'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...List.generate(lines.length, (index) {
                        final line = lines[index];
                        final product = _product(line.variantId);
                        final units = _unitCodes(product);
                        if (line.unitCode != null &&
                            !units.contains(line.unitCode)) {
                          line.unitCode = units.isEmpty ? null : units.first;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 4,
                                child: DropdownButtonFormField<String>(
                                  initialValue: line.variantId,
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
                                            '${(row['variant_name'] ?? '').toString().trim().isEmpty ? '' : ' • ${row['variant_name']}'}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    final selected = _product(value);
                                    setLocalState(() {
                                      line.variantId = value;
                                      line.unitCode = _preferredUnit(selected);
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  initialValue: line.unitCode,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                  ),
                                  items: units
                                      .map(
                                        (unit) => DropdownMenuItem(
                                          value: unit,
                                          child: Text(unit),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: units.isEmpty
                                      ? null
                                      : (value) => setLocalState(
                                          () => line.unitCode = value,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: line.quantity,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Quantity',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: line.rate,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Agreed rate',
                                    helperText: 'Reference',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: 'Remove line',
                                onPressed: lines.length == 1
                                    ? null
                                    : () {
                                        final removed = lines.removeAt(index);
                                        removed.dispose();
                                        setLocalState(() {});
                                      },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                        );
                      }),
                      TextField(
                        controller: notes,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Order notes',
                        ),
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
                    if (customerId == null || locationId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Customer and yard/store are required.',
                          ),
                        ),
                      );
                      return;
                    }

                    final payload = <Map<String, dynamic>>[];
                    final seen = <String>{};

                    for (final line in lines) {
                      final variantId = line.variantId;
                      final unit = line.unitCode;
                      final quantity =
                          double.tryParse(line.quantity.text.trim()) ?? 0;

                      if (variantId == null ||
                          unit == null ||
                          unit.isEmpty ||
                          quantity <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Every material line needs a material, unit and positive quantity.',
                            ),
                          ),
                        );
                        return;
                      }

                      final key = '$variantId|$unit';
                      if (!seen.add(key)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'The same material/unit cannot be added twice.',
                            ),
                          ),
                        );
                        return;
                      }

                      final rate = double.tryParse(line.rate.text.trim());

                      payload.add({
                        'variant_id': variantId,
                        'unit_code': unit,
                        'quantity': quantity,
                        'agreed_rate': ?rate,
                      });
                    }

                    try {
                      final result = await _service.createOrder(
                        tenantId: widget.session.business.id,
                        locationId: locationId!,
                        customerId: customerId!,
                        requestedDate: requestedDate,
                        deliverySiteName: site.text,
                        deliveryAddress: address.text,
                        notes: notes.text,
                        lines: payload,
                      );

                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop(true);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Order ${result['order_number'] ?? ''} created.',
                            ),
                          ),
                        );
                      }
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  },
                  child: const Text('Create Order'),
                ),
              ],
            );
          },
        ),
      );

      if (created == true) await _reload();
    } finally {
      site.dispose();
      address.dispose();
      notes.dispose();
      for (final line in lines) {
        line.dispose();
      }
    }
  }

  Future<void> _createLoad(
    Map<String, dynamic> order,
    Map<String, dynamic> line,
  ) async {
    final vehicles = _list('vehicles');
    final drivers = _list('drivers');

    final unit = (line['unit_code'] ?? '').toString().toUpperCase();
    final maxQuantity = _number(line['remaining_to_plan']);

    if (maxQuantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This order line is fully allocated.')),
      );
      return;
    }

    String measurement = 'manual';
    String? vehicleId;
    String? driverId;
    String freightMode = 'none';
    bool capacityOverride = false;

    final quantity = TextEditingController(text: _qty(maxQuantity));
    final length = TextEditingController();
    final width = TextEditingController();
    final height = TextEditingController();
    final source = TextEditingController();
    final destination = TextEditingController(
      text:
          _id(order['delivery_site_name']) ??
          _id(order['delivery_address']) ??
          '',
    );
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
                (_number(length.text)) *
                (_number(width.text)) *
                (_number(height.text));
            final effective = measurement == 'dimensions'
                ? calculated
                : _number(quantity.text);

            return AlertDialog(
              title: Text('Create Load • ${order['order_number'] ?? ''}'),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: .45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${line['product_name'] ?? ''} • '
                          'Ordered ${_qty(line['ordered_quantity'])} $unit • '
                          'Allocated ${_qty(line['allocated_quantity'])} $unit • '
                          'Available ${_qty(maxQuantity)} $unit',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                              items: [
                                const DropdownMenuItem(
                                  value: 'manual',
                                  child: Text('Manual quantity'),
                                ),
                                if (unit == 'CFT')
                                  const DropdownMenuItem(
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
                            child: measurement == 'manual'
                                ? TextField(
                                    controller: quantity,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: 'Load quantity $unit',
                                    ),
                                    onChanged: (_) => setLocalState(() {}),
                                  )
                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '${calculated.toStringAsFixed(3)} CFT',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      if (measurement == 'dimensions') ...[
                        const SizedBox(height: 10),
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
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: vehicleId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Truck',
                              ),
                              items: vehicles
                                  .map(
                                    (row) => DropdownMenuItem<String>(
                                      value: row['vehicle_id']?.toString(),
                                      child: Text(
                                        '${row['registration_number'] ?? ''}'
                                        '${row['nominal_capacity_cft'] == null ? '' : ' • ${row['nominal_capacity_cft']} CFT'}',
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
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: source,
                              decoration: const InputDecoration(
                                labelText: 'Source / Yard',
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
                      const SizedBox(height: 4),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: capacityOverride,
                        title: const Text('Allow truck capacity override'),
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
                        decoration: const InputDecoration(
                          labelText: 'Load note',
                        ),
                      ),
                      if (effective > maxQuantity + 0.0001) ...[
                        const SizedBox(height: 8),
                        Text(
                          'This load exceeds the remaining unallocated order quantity.',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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
                    final effectiveQuantity = measurement == 'dimensions'
                        ? calculated
                        : _number(quantity.text);

                    if (effectiveQuantity <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a positive load quantity.'),
                        ),
                      );
                      return;
                    }

                    if (effectiveQuantity > maxQuantity + 0.0001) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Maximum remaining allocation is '
                            '${_qty(maxQuantity)} $unit.',
                          ),
                        ),
                      );
                      return;
                    }

                    try {
                      final result = await _service.createOrderLoad(
                        tenantId: widget.session.business.id,
                        orderLineId: line['line_id'].toString(),
                        quantity: effectiveQuantity,
                        measurementMethod: measurement,
                        bodyLengthFt: measurement == 'dimensions'
                            ? _number(length.text)
                            : null,
                        bodyWidthFt: measurement == 'dimensions'
                            ? _number(width.text)
                            : null,
                        bodyHeightFt: measurement == 'dimensions'
                            ? _number(height.text)
                            : null,
                        vehicleId: vehicleId,
                        driverId: driverId,
                        sourceName: source.text,
                        destinationName: destination.text,
                        freightMode: freightMode,
                        freightAmount: _number(freight.text),
                        capacityOverride: capacityOverride,
                        capacityOverrideReason: overrideReason.text,
                        notes: notes.text,
                      );

                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop(true);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Load ${result['load_number'] ?? ''} created. '
                              'Post the THQ Sale from Load Register.',
                            ),
                          ),
                        );
                      }
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  },
                  child: const Text('Create Load'),
                ),
              ],
            );
          },
        ),
      );

      if (created == true) await _reload();
    } finally {
      quantity.dispose();
      length.dispose();
      width.dispose();
      height.dispose();
      source.dispose();
      destination.dispose();
      freight.dispose();
      overrideReason.dispose();
      notes.dispose();
    }
  }

  Future<void> _closeOrder(Map<String, dynamic> order) async {
    final reason = TextEditingController();

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Close ${order['order_number'] ?? 'order'}'),
          content: TextField(
            controller: reason,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason',
              helperText:
                  'Active truck loads must be completed or cancelled first.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().isEmpty) return;
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Close Order'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      await _service.closeOrder(
        tenantId: widget.session.business.id,
        orderId: order['order_id'].toString(),
        reason: reason.text.trim(),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      reason.dispose();
    }
  }

  Future<void> _openLoadRegister() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AggregateLoadsScreen(session: widget.session),
      ),
    );
    if (mounted) await _reload(all: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Orders'),
        actions: [
          IconButton(
            tooltip: 'Load Register',
            onPressed: _openLoadRegister,
            icon: const Icon(Icons.local_shipping_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _reload(all: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _createOrder,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Order'),
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
                          'Order no, customer, phone, site or material...',
                    ),
                    onSubmitted: (_) => _reload(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _status,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All'),
                      ),
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(
                        value: 'partially_dispatched',
                        child: Text('In fulfillment'),
                      ),
                      DropdownMenuItem(
                        value: 'completed',
                        child: Text('Completed'),
                      ),
                      DropdownMenuItem(
                        value: 'closed_partial',
                        child: Text('Closed partial'),
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
                : _orders.isEmpty
                ? const Center(
                    child: Text(
                      'No customer orders yet.\nCreate one with + New Order.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                    itemCount: _orders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      final lines = (order['lines'] as List? ?? const [])
                          .whereType<Map>()
                          .map((row) => Map<String, dynamic>.from(row))
                          .toList();
                      final status = order['status']?.toString() ?? '';
                      final canManage =
                          status == 'open' || status == 'partially_dispatched';

                      return Card(
                        margin: EdgeInsets.zero,
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${order['order_number'] ?? ''} • '
                                  '${order['customer_name'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  status
                                      .replaceAll('_', ' ')
                                      .replaceAll(
                                        'partially dispatched',
                                        'in fulfillment',
                                      ),
                                  style: const TextStyle(fontSize: 9),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'CFT: ordered ${_qty(order['ordered_cft'])} • '
                            'delivered ${_qty(order['delivered_cft'])} • '
                            'remaining ${_qty(order['remaining_cft'])}'
                            '${_id(order['delivery_site_name']) == null ? '' : '\n${order['delivery_site_name']}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          children: [
                            const Divider(height: 1),
                            ...lines.map((line) {
                              final ordered = _number(line['ordered_quantity']);
                              final delivered = _number(
                                line['delivered_quantity'],
                              );
                              final progress = ordered <= 0
                                  ? 0.0
                                  : (delivered / ordered)
                                        .clamp(0.0, 1.0)
                                        .toDouble();
                              final remainingPlan = _number(
                                line['remaining_to_plan'],
                              );

                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  6,
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${line['product_name'] ?? ''}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Ordered ${_qty(line['ordered_quantity'])} '
                                                '${line['unit_code'] ?? ''} • '
                                                'Allocated ${_qty(line['allocated_quantity'])} • '
                                                'Delivered ${_qty(line['delivered_quantity'])} • '
                                                'Remaining ${_qty(line['remaining_to_deliver'])}',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (canManage && remainingPlan > 0.0001)
                                          FilledButton.tonalIcon(
                                            onPressed: () =>
                                                _createLoad(order, line),
                                            icon: const Icon(
                                              Icons.local_shipping_outlined,
                                              size: 15,
                                            ),
                                            label: const Text('Create Load'),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 4,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                              child: Row(
                                children: [
                                  if (_id(order['requested_date']) != null)
                                    Text(
                                      'Requested: ${order['requested_date']}',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  const Spacer(),
                                  if (canManage)
                                    TextButton.icon(
                                      onPressed: () => _closeOrder(order),
                                      icon: const Icon(
                                        Icons.block_outlined,
                                        size: 15,
                                      ),
                                      label: const Text('Close Order'),
                                    ),
                                ],
                              ),
                            ),
                          ],
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

class _OrderDraftLine {
  String? variantId;
  String? unitCode;
  final TextEditingController quantity = TextEditingController();
  final TextEditingController rate = TextEditingController();

  _OrderDraftLine({this.variantId, this.unitCode});

  void dispose() {
    quantity.dispose();
    rate.dispose();
  }
}
