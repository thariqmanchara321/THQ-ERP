import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_direct_supply_service.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import 'purchases_screen.dart';
import 'sales_screen.dart';

class AggregateDirectSupplyScreen extends StatefulWidget {
  final ClientSession session;

  const AggregateDirectSupplyScreen({super.key, required this.session});

  @override
  State<AggregateDirectSupplyScreen> createState() =>
      _AggregateDirectSupplyScreenState();
}

class _AggregateDirectSupplyScreenState
    extends State<AggregateDirectSupplyScreen> {
  final AggregateDirectSupplyService _direct = AggregateDirectSupplyService();
  final AggregateYardService _yard = AggregateYardService();
  final TextEditingController _search = TextEditingController();

  Map<String, dynamic> _context = const {};
  List<Map<String, dynamic>> _materials = const [];
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _status;

  ClientSession get _session => widget.session;

  bool get _canView =>
      _session.hasRole('owner') ||
      _session.hasPermission('aggregate_yard.manage') ||
      _session.hasPermission('aggregate_yard.direct.view') ||
      _session.hasPermission('aggregate_yard.direct.manage');

  bool get _canManage =>
      _session.hasRole('owner') ||
      _session.hasPermission('aggregate_yard.direct.manage');

  String? get _locationId => LocationScopeService.selectedLocationId.value;

  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_locationChanged);
    _reload(all: true);
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_locationChanged);
    _search.dispose();
    super.dispose();
  }

  void _locationChanged() {
    if (mounted) _reload();
  }

  List<Map<String, dynamic>> _list(String key) =>
      (_context[key] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  String? _id(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? null : text;
  }

  double _number(dynamic value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  double? _double(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  String _qty(dynamic value) {
    final number = _number(value);
    if ((number - number.roundToDouble()).abs() < 0.000001) {
      return number.toStringAsFixed(0);
    }
    return number.toStringAsFixed(3);
  }

  String _label(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Future<void> _reload({bool all = false}) async {
    if (!_canView) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Direct Supply view permission required.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      if (all || _context.isEmpty) {
        final values = await Future.wait([
          _yard.context(tenantId: _session.business.id),
          _direct.materials(tenantId: _session.business.id),
        ]);
        _context = values[0] as Map<String, dynamic>;
        _materials = values[1] as List<Map<String, dynamic>>;
      }

      var rows = await _direct.loads(
        tenantId: _session.business.id,
        operatingLocationId: _locationId,
        query: _search.text.trim(),
      );

      final status = _status;
      if (status != null && status.isNotEmpty) {
        rows = rows
            .where((row) => row['status']?.toString() == status)
            .toList(growable: false);
      }

      _rows = rows;
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _material(String? variantId) {
    if (variantId == null) return null;
    for (final row in _materials) {
      if (row['variant_id']?.toString() == variantId) return row;
    }
    return null;
  }

  List<Map<String, dynamic>> _unitsFor(String? variantId) =>
      ((_material(variantId)?['units'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  String? _defaultUnit(String? variantId) {
    final material = _material(variantId);
    final units = _unitsFor(variantId);
    if (material == null || units.isEmpty) return null;

    final base = _id(material['base_unit_code']);
    if (base != null &&
        units.any((row) => row['code']?.toString().toUpperCase() == base)) {
      return base.toUpperCase();
    }
    return _id(units.first['code'])?.toUpperCase();
  }

  bool _supportsCft(String? variantId) => _unitsFor(
    variantId,
  ).any((row) => row['code']?.toString().toUpperCase() == 'CFT');

  Future<void> _createLoad() async {
    if (!_canManage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Direct Supply manage permission required.'),
        ),
      );
      return;
    }

    final locations = _list('locations');
    final vehicles = _list('vehicles');
    final drivers = _list('drivers');
    final suppliers = _list('suppliers');
    final customers = _list('customers');

    if (_materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No stock material has a unit valid for both Purchase and Sale.',
          ),
        ),
      );
      return;
    }
    if (locations.isEmpty || suppliers.isEmpty || customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Direct Supply requires a physical location, supplier/quarry and customer.',
          ),
        ),
      );
      return;
    }

    String? locationId = _locationId;
    if (locationId == null && locations.length == 1) {
      locationId = _id(locations.first['location_id']);
    }

    String? variantId;
    String? unitCode;
    String measurement = 'manual';
    String? vehicleId;
    String? driverId;
    String? supplierId;
    String? customerId;
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
            final materialUnits = _unitsFor(variantId);
            final supportsCft = _supportsCft(variantId);
            final calculated =
                (_double(length.text) ?? 0) *
                (_double(width.text) ?? 0) *
                (_double(height.text) ?? 0);

            return AlertDialog(
              title: const Text('New Direct Supply'),
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
                          color: Theme.of(context).colorScheme.tertiaryContainer
                              .withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Quarry → Customer uses a hidden controlled transit '
                          'location. Post and link the Purchase first; the Sale '
                          'is enabled only after that Purchase is linked.',
                          style: TextStyle(fontSize: 10.5, height: 1.35),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: locationId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Operating yard / store',
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
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: variantId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Material',
                          helperText:
                              'Only units valid for both Purchase and Sale are offered.',
                        ),
                        items: _materials
                            .map(
                              (row) => DropdownMenuItem<String>(
                                value: row['variant_id']?.toString(),
                                child: Text(
                                  '${row['product_name'] ?? ''}'
                                  '${(row['variant_name'] ?? '').toString().trim().isEmpty ? '' : ' | ${row['variant_name']}'}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setLocalState(() {
                            variantId = value;
                            unitCode = _defaultUnit(value);
                            if (measurement == 'dimensions' &&
                                !_supportsCft(value)) {
                              measurement = 'manual';
                            }
                          });
                        },
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
                                if (supportsCft)
                                  const DropdownMenuItem(
                                    value: 'dimensions',
                                    child: Text('Truck dimensions (CFT)'),
                                  ),
                              ],
                              onChanged: (value) {
                                setLocalState(() {
                                  measurement = value ?? 'manual';
                                  if (measurement == 'dimensions') {
                                    unitCode = 'CFT';
                                  } else {
                                    unitCode ??= _defaultUnit(variantId);
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey(
                                'direct-unit-$variantId-$unitCode-$measurement',
                              ),
                              initialValue: measurement == 'dimensions'
                                  ? 'CFT'
                                  : unitCode,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                              ),
                              items: materialUnits
                                  .map(
                                    (row) => DropdownMenuItem<String>(
                                      value: row['code']
                                          ?.toString()
                                          .toUpperCase(),
                                      child: Text(
                                        '${row['code'] ?? ''} | ${row['name'] ?? ''}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: measurement == 'dimensions'
                                  ? null
                                  : (value) =>
                                        setLocalState(() => unitCode = value),
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
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
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
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
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
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
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
                              initialValue: supplierId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Supplier / Quarry',
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
                          ),
                          const SizedBox(width: 10),
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
                                        '${row['name'] ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setLocalState(() => customerId = value),
                            ),
                          ),
                        ],
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
                                labelText: 'Destination / Customer site',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: reference,
                        decoration: const InputDecoration(
                          labelText: 'Quarry slip / supplier invoice reference',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: freightMode,
                              decoration: const InputDecoration(
                                labelText: 'Freight mode',
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
                                helperText:
                                    'Use Freight & Profit later to select transporter/settle.',
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
                          'Requires the existing capacity override permission and a reason.',
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
                FilledButton.icon(
                  onPressed: () async {
                    if (locationId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Select the operating yard / store.'),
                        ),
                      );
                      return;
                    }
                    if (variantId == null || unitCode == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Select a material and unit.'),
                        ),
                      );
                      return;
                    }
                    if (supplierId == null || customerId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Select both Supplier / Quarry and Customer.',
                          ),
                        ),
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
                    if (measurement == 'dimensions' && !supportsCft) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'This material is not configured for CFT in both Purchase and Sale.',
                          ),
                        ),
                      );
                      return;
                    }

                    try {
                      await _direct.createLoad(
                        tenantId: _session.business.id,
                        operatingLocationId: locationId!,
                        variantId: variantId!,
                        quantity: quantity,
                        unitCode: measurement == 'dimensions'
                            ? 'CFT'
                            : unitCode!,
                        measurementMethod: measurement,
                        bodyLengthFt: _double(length.text),
                        bodyWidthFt: _double(width.text),
                        bodyHeightFt: _double(height.text),
                        vehicleId: vehicleId,
                        driverId: driverId,
                        supplierId: supplierId!,
                        customerId: customerId!,
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
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: const Text('Create Direct Supply'),
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

  String _transactionNote(Map<String, dynamic> row) {
    final parts = <String>[
      'Direct Supply ${row['load_number'] ?? ''}',
      if (_id(row['vehicle_registration']) != null)
        'Truck ${row['vehicle_registration']}',
      if (_id(row['source_name']) != null) 'From ${row['source_name']}',
      if (_id(row['destination_name']) != null) 'To ${row['destination_name']}',
      if (_id(row['source_reference']) != null)
        'Ref ${row['source_reference']}',
    ];
    return parts.join(' | ');
  }

  Future<void> _postPurchase(Map<String, dynamic> row) async {
    if (!_canManage || _id(row['purchase_id']) != null) return;

    final transitLocationId = _id(row['transit_location_id']);
    if (transitLocationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Controlled transit location is missing.'),
        ),
      );
      return;
    }

    String? createdPurchaseId;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewPurchaseScreen(
          session: _session,
          locationId: transitLocationId,
          initialSupplierId: _id(row['supplier_id']),
          initialVariantId: _id(row['variant_id']),
          initialQuantity: _number(row['quantity']),
          initialUnitCode: _id(row['unit_code']),
          initialSupplierInvoiceNumber: _id(row['source_reference']),
          initialNotes: _transactionNote(row),
          onCreated: (id) => createdPurchaseId = id,
        ),
      ),
    );

    if (!mounted || completed != true || createdPurchaseId == null) return;

    try {
      await _direct.linkDocument(
        tenantId: _session.business.id,
        loadId: row['load_id'].toString(),
        documentType: 'purchase',
        documentId: createdPurchaseId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase posted and linked. Sale is now permitted.'),
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
            'Purchase $createdPurchaseId was posted, but linking failed: $error\n'
            'Do not post it again. Use Recover Purchase Link.',
          ),
        ),
      );
      await _reload();
    }
  }

  Future<void> _postSale(Map<String, dynamic> row) async {
    if (!_canManage || _id(row['sale_id']) != null) return;
    if (_id(row['purchase_id']) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post and link the Purchase before the Sale.'),
        ),
      );
      return;
    }

    final transitLocationId = _id(row['transit_location_id']);
    if (transitLocationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Controlled transit location is missing.'),
        ),
      );
      return;
    }

    String? createdSaleId;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewSaleScreen(
          session: _session,
          locationId: transitLocationId,
          initialCustomerId: _id(row['customer_id']),
          initialVariantId: _id(row['variant_id']),
          initialQuantity: _number(row['quantity']),
          initialUnitCode: _id(row['unit_code']),
          initialNotes: _transactionNote(row),
          onCreated: (id) => createdSaleId = id,
        ),
      ),
    );

    if (!mounted || completed != true || createdSaleId == null) return;

    try {
      await _direct.linkDocument(
        tenantId: _session.business.id,
        loadId: row['load_id'].toString(),
        documentType: 'sale',
        documentId: createdSaleId!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale posted and linked. Commercial flow is complete.'),
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(
            'Sale $createdSaleId was posted, but linking failed: $error\n'
            'Do not post it again. Use Recover Sale Link.',
          ),
        ),
      );
      await _reload();
    }
  }

  Future<void> _recoverLink(
    Map<String, dynamic> row,
    String documentType,
  ) async {
    if (!_canManage) return;

    try {
      final candidates = await _direct.documentCandidates(
        tenantId: _session.business.id,
        loadId: row['load_id'].toString(),
        documentType: documentType,
      );

      if (!mounted) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No matching posted ${_label(documentType)} was found at the controlled transit location.',
            ),
          ),
        );
        return;
      }

      final selectedId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Recover ${_label(documentType)} Link'),
          content: SizedBox(
            width: 620,
            height: 360,
            child: ListView.separated(
              itemCount: candidates.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final candidate = candidates[index];
                final id = _id(candidate['document_id']);
                return ListTile(
                  enabled: id != null,
                  title: Text(
                    '${candidate['document_number'] ?? ''} • '
                    '${candidate['party_name'] ?? ''}',
                  ),
                  subtitle: Text(
                    '${candidate['document_date'] ?? ''} • '
                    'remaining ${_qty(candidate['remaining_quantity'])} '
                    '${candidate['unit_code'] ?? ''}',
                  ),
                  trailing: const Icon(Icons.link_rounded),
                  onTap: id == null
                      ? null
                      : () => Navigator.of(dialogContext).pop(id),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedId == null || !mounted) return;

      await _direct.linkDocument(
        tenantId: _session.business.id,
        loadId: row['load_id'].toString(),
        documentType: documentType,
        documentId: selectedId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_label(documentType)} link recovered successfully.'),
        ),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  List<String> _nextStatuses(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    final purchaseLinked = _id(row['purchase_id']) != null;
    final saleLinked = _id(row['sale_id']) != null;
    final anyCommercial = purchaseLinked || saleLinked;

    var next = switch (status) {
      'draft' => <String>['loading', 'cancelled'],
      'loading' => <String>['dispatched', 'in_transit', 'cancelled'],
      'dispatched' => <String>['in_transit', 'arrived', 'cancelled'],
      'in_transit' => <String>['arrived', 'cancelled'],
      'arrived' => <String>['delivered', 'cancelled'],
      'delivered' =>
        purchaseLinked && saleLinked ? <String>['completed'] : <String>[],
      _ => <String>[],
    };

    if (anyCommercial) {
      next = next.where((value) => value != 'cancelled').toList();
    }
    return next;
  }

  Future<void> _changeStatus(Map<String, dynamic> row, String status) async {
    try {
      await _direct.updateStatus(
        tenantId: _session.business.id,
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

  Future<void> _handleAction(Map<String, dynamic> row, String action) async {
    switch (action) {
      case 'post_purchase':
        await _postPurchase(row);
        return;
      case 'recover_purchase':
        await _recoverLink(row, 'purchase');
        return;
      case 'post_sale':
        await _postSale(row);
        return;
      case 'recover_sale':
        await _recoverLink(row, 'sale');
        return;
    }

    if (action.startsWith('status:')) {
      await _changeStatus(row, action.substring('status:'.length));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!_canView) {
      return const Scaffold(
        body: Center(child: Text('Direct Supply view permission required.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Direct Supply | Quarry → Customer'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _reload(all: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _createLoad,
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('New Direct Supply'),
            )
          : null,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Controlled flow: create load → Purchase into hidden transit '
                    '→ link Purchase → Sale from transit → link Sale → Complete. '
                    'Never repost a document after a link interruption; use Recover Link.',
                    style: TextStyle(fontSize: 10.5, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText:
                          'Search load, material, quarry, customer, truck or document',
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _search.clear();
                                _reload();
                              },
                              icon: const Icon(Icons.clear_rounded),
                            ),
                    ),
                    onSubmitted: (_) => _reload(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
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
                        value: 'dispatched',
                        child: Text('Dispatched'),
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
                      'No Direct Supply loads yet.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final next = _nextStatuses(row);
                      final purchaseLinked = _id(row['purchase_id']) != null;
                      final saleLinked = _id(row['sale_id']) != null;
                      final active = row['status'] != 'cancelled';

                      final canPurchase =
                          _canManage && active && !purchaseLinked;
                      final canSale =
                          _canManage && active && purchaseLinked && !saleLinked;
                      final hasActions =
                          canPurchase ||
                          canSale ||
                          (_canManage && next.isNotEmpty);

                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: scheme.tertiaryContainer,
                                child: const Icon(
                                  Icons.compare_arrows_rounded,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${row['load_number'] ?? ''} • '
                                            '${row['product_name'] ?? ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(
                                            _label(
                                              row['commercial_state']
                                                      ?.toString() ??
                                                  'awaiting_purchase',
                                            ),
                                            style: const TextStyle(fontSize: 8),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${_qty(row['quantity'])} ${row['unit_code'] ?? ''}'
                                      ' • ${row['vehicle_registration'] ?? 'No truck'}'
                                      ' • ${row['operating_location_name'] ?? ''}',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${row['supplier_name'] ?? row['source_name'] ?? 'Quarry'}'
                                      ' → '
                                      '${row['customer_name'] ?? row['destination_name'] ?? 'Customer'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 7,
                                      runSpacing: 5,
                                      children: [
                                        _MiniTag(
                                          text: purchaseLinked
                                              ? 'Purchase ${row['purchase_number'] ?? 'linked'}'
                                              : 'Purchase pending',
                                          positive: purchaseLinked,
                                        ),
                                        _MiniTag(
                                          text: saleLinked
                                              ? 'Sale ${row['sale_number'] ?? 'linked'}'
                                              : 'Sale pending',
                                          positive: saleLinked,
                                        ),
                                        _MiniTag(
                                          text:
                                              'Transit stock ${_qty(row['transit_stock_balance'])} ${row['unit_code'] ?? ''}',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      _label(row['status']?.toString() ?? ''),
                                    ),
                                  ),
                                  if (hasActions)
                                    PopupMenuButton<String>(
                                      tooltip: 'Direct Supply actions',
                                      onSelected: (value) =>
                                          _handleAction(row, value),
                                      itemBuilder: (context) => [
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
                                        if (canPurchase)
                                          const PopupMenuItem(
                                            value: 'recover_purchase',
                                            child: ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(Icons.link_rounded),
                                              title: Text(
                                                'Recover Purchase Link',
                                              ),
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
                                        if (canSale)
                                          const PopupMenuItem(
                                            value: 'recover_sale',
                                            child: ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: Icon(Icons.link_rounded),
                                              title: Text('Recover Sale Link'),
                                            ),
                                          ),
                                        if ((canPurchase || canSale) &&
                                            next.isNotEmpty)
                                          const PopupMenuDivider(),
                                        for (final status in next)
                                          PopupMenuItem(
                                            value: 'status:$status',
                                            child: ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(
                                                Icons.arrow_forward_rounded,
                                              ),
                                              title: Text(
                                                'Move to ${_label(status)}',
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
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

class _MiniTag extends StatelessWidget {
  final String text;
  final bool positive;

  const _MiniTag({required this.text, this.positive = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: positive
            ? scheme.primaryContainer.withValues(alpha: .55)
            : scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
