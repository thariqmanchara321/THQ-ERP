import 'package:thq_ui/thq_ui.dart';
import 'package:uuid/uuid.dart';

import '../services/staff_load_service.dart';
import '../widgets/load_cost_editor.dart';
import 'material_load_detail_screen.dart';
import 'material_load_reports_screen.dart';

import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import 'purchase_detail_screen.dart';
import 'purchases_screen.dart';
import 'sale_detail_screen.dart';
import 'sales_screen.dart';
import 'transport_logistics_hub_screen.dart';

class AggregateLoadsScreen extends StatefulWidget {
  final ClientSession session;
  final String? initialCreateDirection;
  final String? initialLoadId;

  const AggregateLoadsScreen({
    super.key,
    required this.session,
    this.initialCreateDirection,
    this.initialLoadId,
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
  String? _direction;
  bool _autoCreateOpened = false;
  final Set<String> _busyLoads = {};

  String? get _locationId =>
      LocationScopeService.currentForRead(widget.session);
  bool get _canManage =>
      widget.session.hasRole('owner') ||
      widget.session.hasPermission('aggregate_yard.manage');
  bool get _hasTransport =>
      widget.session.hasModule('vehicle_logistics') ||
      widget.session.hasModule('logistics_operations') ||
      widget.session.hasModule('transport_service');

  List<Map<String, dynamic>> _list(String key) =>
      (_context[key] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_locationChanged);
    _reload(all: true).then((_) {
      if (!mounted || _error != null || _autoCreateOpened) {
        return;
      }
      _autoCreateOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.initialLoadId != null) {
            _showLoad({'load_id': widget.initialLoadId});
          } else if (widget.initialCreateDirection != null && _canManage) {
            _createLoad(initialDirection: widget.initialCreateDirection);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_locationChanged);
    _search.dispose();
    super.dispose();
  }

  void _locationChanged() => _reload(all: true);

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
      if (_direction != null) {
        _rows = _rows.where((row) => row['direction'] == _direction).toList();
      }
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
    String? locationId = LocationScopeService.currentForCreate(widget.session);
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
    var costs = <Map<String, dynamic>>[];
    var delivery = <String, dynamic>{};
    final requestId = const Uuid().v4();
    var saving = false;

    try {
      final created = await showThqDialog<bool>(
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
                            style: TextStyle(fontSize: 11, height: 1.3),
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                      if (_context['can_manage_costs'] == true &&
                          locationId != null)
                        LoadCostEditor(
                          session: widget.session,
                          locationId: locationId!,
                          direction: direction,
                          driverId: driverId,
                          contextData: _context,
                          costs: costs,
                          onChanged: (v) => setLocalState(() => costs = v),
                        ),
                      OutlinedButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final details = await editLoadDelivery(
                                  context,
                                  initial: delivery,
                                );
                                if (details != null && context.mounted) {
                                  setLocalState(() => delivery = details);
                                }
                              },
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: Text(
                          delivery.isEmpty
                              ? 'Add driver & delivery details'
                              : 'Edit driver & delivery details',
                        ),
                      ),
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
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (productId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Select a material.'),
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
                          setLocalState(() => saving = true);
                          try {
                            await _service.createLoad(
                              tenantId: widget.session.business.id,
                              direction: direction,
                              locationId: locationId,
                              variantId: productId!,
                              quantity: quantity,
                              unitCode: measurement == 'dimensions'
                                  ? 'CFT'
                                  : unit,
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
                              costs: costs,
                              delivery: delivery,
                              requestId: requestId,
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            if (!context.mounted) return;
                            setLocalState(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Create Draft Load'),
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
    return _canManage &&
        !_busyLoads.contains(_id(row['load_id'])) &&
        status != 'completed' &&
        status != 'cancelled';
  }

  bool _canEdit(Map<String, dynamic> row) =>
      _canConfirm(row) && !_hasProtectedLinks(row);

  bool _canDelete(Map<String, dynamic> row) =>
      _canManage &&
      !_busyLoads.contains(_id(row['load_id'])) &&
      !['completed', 'cancelled'].contains(row['status']?.toString()) &&
      !_hasProtectedLinks(row);

  bool _canOpenBilling(Map<String, dynamic> row) {
    if (row['status'] != 'completed' ||
        _busyLoads.contains(_id(row['load_id']))) {
      return false;
    }
    final outbound = row['direction'] == 'outbound';
    if (!outbound && row['direction'] != 'inbound') return false;
    final module = outbound ? 'sales' : 'purchases';
    final linked = _id(row[outbound ? 'sale_id' : 'purchase_id']) != null;
    return widget.session.hasRole('owner') ||
        (linked && widget.session.hasPermission('$module.view')) ||
        (linked
            ? widget.session.hasPermission('$module.manage')
            : _canManage && widget.session.hasPermission('$module.manage'));
  }

  String _billingLabel(Map<String, dynamic> row) {
    final outbound = row['direction'] == 'outbound';
    final linked = _id(row[outbound ? 'sale_id' : 'purchase_id']) != null;
    return '${linked ? 'View' : 'Create'} ${outbound ? 'Sale' : 'Purchase'}';
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openBilling(Map<String, dynamic> row) async {
    final loadId = _id(row['load_id']);
    if (loadId == null || !_canOpenBilling(row)) return;
    setState(() => _busyLoads.add(loadId));
    try {
      final load = await _service.loadDetail(
        tenantId: widget.session.business.id,
        loadId: loadId,
      );
      if (!mounted) return;
      if (load['status'] != 'completed') {
        throw StateError('Confirm the load before creating its invoice.');
      }
      final outbound = load['direction'] == 'outbound';
      final documentId = _id(load[outbound ? 'sale_id' : 'purchase_id']);
      if (documentId != null) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => outbound
                ? SaleDetailScreen(session: widget.session, saleId: documentId)
                : PurchaseDetailScreen(
                    session: widget.session,
                    purchaseId: documentId,
                  ),
          ),
        );
      } else {
        final locationId = _id(load['location_id']);
        if (locationId == null) throw StateError('The load has no yard/store.');
        final notes = [
          'Material load ${load['load_number']}',
          if (_id(load['vehicle_registration']) != null)
            'Truck: ${load['vehicle_registration']}',
          if (_id(load['driver_name']) != null)
            'Driver: ${load['driver_name']}',
          if (_id(load['notes']) != null) load['notes'].toString(),
        ].join('\n');
        final quantity = double.tryParse('${load['quantity']}');
        final completed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => outbound
                ? NewSaleScreen(
                    session: widget.session,
                    locationId: locationId,
                    materialLoadId: loadId,
                    initialCustomerId: _id(load['customer_id']),
                    initialVariantId: _id(load['variant_id']),
                    initialQuantity: quantity,
                    initialUnitCode: _id(load['unit_code']),
                    initialNotes: notes,
                  )
                : NewPurchaseScreen(
                    session: widget.session,
                    locationId: locationId,
                    materialLoadId: loadId,
                    initialSupplierId: _id(load['supplier_id']),
                    initialVariantId: _id(load['variant_id']),
                    initialQuantity: quantity,
                    initialUnitCode: _id(load['unit_code']),
                    initialSupplierInvoiceNumber: _id(load['source_reference']),
                    initialNotes: notes,
                  ),
          ),
        );
        if (completed == true) {
          _message(
            '${outbound ? 'Sale' : 'Purchase'} posted and linked to the load.',
          );
        }
      }
      if (mounted) await _reload();
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busyLoads.remove(loadId));
    }
  }

  Future<void> _openTransport(Map<String, dynamic> row) async {
    if (!_hasTransport) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TransportLogisticsHubScreen(
          session: widget.session,
          initialMaterialLoadId: _id(row['load_id']),
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _showLoad(Map<String, dynamic> row) async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialLoadDetailScreen(
          session: widget.session,
          loadId: row['load_id'].toString(),
        ),
      ),
    );
    if (!mounted) return;
    await _reload();
    final fresh = await _service.loadDetail(
      tenantId: widget.session.business.id,
      loadId: row['load_id'].toString(),
    );
    if (!mounted) return;
    switch (action) {
      case 'confirm':
        await _confirmLoad(fresh);
      case 'billing':
        await _openBilling(fresh);
      case 'transport':
        await _openTransport(fresh);
    }
  }

  Future<void> _confirmLoad(Map<String, dynamic> row) async {
    if (!_canConfirm(row)) return;

    final accepted = await showThqDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Load'),
        content: Text(
          'Confirm ${row['load_number']}?\n\n'
          'The load becomes read-only. '
          '${row['direction'] == 'outbound' ? 'Sales' : 'Purchase'} will open next. '
          'Review and post the invoice to update stock and accounts.',
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

    final loadId = row['load_id'].toString();
    if (!_canConfirm(row)) return;
    var confirmed = false;
    setState(() => _busyLoads.add(loadId));
    try {
      await _service.confirmLoad(
        tenantId: widget.session.business.id,
        loadId: loadId,
      );
      if (!mounted) return;
      confirmed = true;
      _message('Load confirmed.');
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busyLoads.remove(loadId));
    }
    if (confirmed && mounted) {
      final load = {...row, 'status': 'completed'};
      if (_canOpenBilling(load)) {
        await _openBilling(load);
      } else {
        _message(
          'Load confirmed. ${row['direction'] == 'outbound' ? 'Sales' : 'Purchases'} manage permission is required to create its invoice.',
        );
      }
    }
  }

  Future<void> _deleteLoad(Map<String, dynamic> row) async {
    if (!_canDelete(row)) return;

    final accepted = await showThqDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel unconfirmed load'),
        content: Text(
          'Cancel ${row['load_number']}?\n\n'
          'Its driver, delivery details and draft costs will remain available in the register and reports.',
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
            child: const Text('Cancel load'),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) return;

    try {
      await StaffLoadService().load(
        tenantId: widget.session.business.id,
        action: 'cancel',
        data: {
          'load_id': row['load_id'],
          'reason': 'Cancelled before confirmation',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Load cancelled; saved history retained.'),
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
      var costs = StaffLoadService.rows(
        detail['costs'],
      ).where((c) => c['status'] == 'draft').toList();
      var delivery = detail['delivery'] is Map
          ? Map<String, dynamic>.from(detail['delivery'] as Map)
          : <String, dynamic>{};
      var saving = false;

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
                                    child: Text('Inbound | Quarry to Yard'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'outbound',
                                    child: Text('Outbound | Yard to Customer'),
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
                                fontWeight: FontWeight.w600,
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
                        if (_context['can_manage_costs'] == true &&
                            locationId != null)
                          LoadCostEditor(
                            session: widget.session,
                            locationId: locationId!,
                            direction: direction,
                            driverId: driverId,
                            contextData: _context,
                            costs: costs,
                            onChanged: (v) => setLocalState(() => costs = v),
                          ),
                        OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  final details = await editLoadDelivery(
                                    context,
                                    initial: delivery,
                                  );
                                  if (details != null && context.mounted) {
                                    setLocalState(() => delivery = details);
                                  }
                                },
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: Text(
                            delivery.isEmpty
                                ? 'Add driver & delivery details'
                                : 'Edit driver & delivery details',
                          ),
                        ),
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
                    onPressed: saving
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
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

                            setLocalState(() => saving = true);
                            try {
                              await _service.editLoad(
                                tenantId: widget.session.business.id,
                                loadId: row['load_id'].toString(),
                                direction: direction,
                                locationId: locationId,
                                variantId: productId!,
                                quantity: editedQuantity,
                                unitCode: measurement == 'dimensions'
                                    ? 'CFT'
                                    : unit,
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
                                costs: costs,
                                delivery: delivery,
                              );
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(true);
                              }
                            } catch (error) {
                              if (!context.mounted) return;
                              setLocalState(() => saving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          },
                    child: Text(saving ? 'Saving…' : 'Save Changes'),
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

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: [
        Chip(
          label: Text(_simpleStatus(row)),
          visualDensity: VisualDensity.compact,
        ),
        if (canConfirm)
          FilledButton.tonalIcon(
            onPressed: () => _confirmLoad(row),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Confirm'),
          ),
        if (_canOpenBilling(row))
          FilledButton.tonalIcon(
            onPressed: () => _openBilling(row),
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: Text(_billingLabel(row)),
          ),
        if (_hasTransport)
          OutlinedButton.icon(
            onPressed: () => _openTransport(row),
            icon: const Icon(Icons.route_outlined, size: 16),
            label: const Text('Trip'),
          ),
        if (canEdit)
          OutlinedButton.icon(
            onPressed: () => _editLoad(row),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
          ),
        if (canDelete)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () => _deleteLoad(row),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Delete'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Load Register'),
        actions: [
          IconButton(
            tooltip: 'Load, expense and payment reports',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    MaterialLoadReportsScreen(session: widget.session),
              ),
            ),
            icon: const Icon(Icons.assessment_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _reload(all: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: !_canManage
          ? null
          : FloatingActionButton.extended(
              onPressed: _loading ? null : () => _createLoad(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Load'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: constraints.maxWidth > 720
                        ? constraints.maxWidth - 336
                        : constraints.maxWidth,
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
                  SizedBox(
                    width: constraints.maxWidth < 340
                        ? (constraints.maxWidth - 8) / 2
                        : 160,
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
                  SizedBox(
                    width: constraints.maxWidth < 340
                        ? (constraints.maxWidth - 8) / 2
                        : 160,
                    child: DropdownButtonFormField<String?>(
                      initialValue: _direction,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'Direction'),
                      items: const [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All loads'),
                        ),
                        DropdownMenuItem(
                          value: 'inbound',
                          child: Text('Inward'),
                        ),
                        DropdownMenuItem(
                          value: 'outbound',
                          child: Text('Dispatch'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _direction = value);
                        _reload();
                      },
                    ),
                  ),
                ],
              ),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
                              onTap: () => _showLoad(row),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
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
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                              child: _loadActions(row),
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
