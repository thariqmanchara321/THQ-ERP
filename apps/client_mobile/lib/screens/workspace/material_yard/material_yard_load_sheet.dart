import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/mobile_session.dart';
import '../../../services/mobile_client_service.dart';
import 'material_yard_types.dart';

class MobileMaterialLoadSheet extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? initialDirection; // 'inbound' or 'outbound'
  final String? initialLocationId;
  final Map<String, dynamic>? editingLoad; // If editing an existing draft load
  final VoidCallback onSaved;

  const MobileMaterialLoadSheet({
    super.key,
    required this.session,
    required this.service,
    this.initialDirection,
    this.initialLocationId,
    this.editingLoad,
    required this.onSaved,
  });

  @override
  State<MobileMaterialLoadSheet> createState() => _MobileMaterialLoadSheetState();
}

class _MobileMaterialLoadSheetState extends State<MobileMaterialLoadSheet> {
  bool _loadingContext = true;
  String? _contextError;
  Map<String, dynamic> _yardContext = const {};

  late String _direction;
  String? _selectedLocationId;
  String? _selectedVariantId;
  String? _selectedPartyId; // supplier_id for inbound, customer_id for outbound
  String? _selectedVehicleId;
  String? _selectedDriverId;

  // Measurement state
  String _measurementMethod = 'dimensions'; // 'dimensions', 'manual', 'weighbridge'
  String _unitCode = 'CFT';
  String _dimensionUnit = 'in'; // 'in', 'ft', 'ft_in', 'm', 'cm'

  // Dimensions controllers
  final _lengthCtrl = TextEditingController();
  final _lengthInCtrl = TextEditingController();
  final _widthCtrl = TextEditingController();
  final _widthInCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _heightInCtrl = TextEditingController();

  // Weighbridge controllers
  final _grossWeightCtrl = TextEditingController();
  final _tareWeightCtrl = TextEditingController();
  final _densityCtrl = TextEditingController(text: '1.6'); // default aggregate density MT/m3

  // Manual quantity controller
  final _manualQtyCtrl = TextEditingController();

  // Adjustments & Pricing controllers
  final _heapAdjCtrl = TextEditingController();
  final _heapReasonCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _slipRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _overrideReasonCtrl = TextEditingController();

  bool _capacityOverride = false;
  double _calculatedCft = 0.0;
  double _effectivePhysicalQty = 0.0;
  double _effectiveBillableQty = 0.0;

  // Additional expenses
  final List<Map<String, dynamic>> _costs = [];

  bool _saving = false;

  bool get isEditing => widget.editingLoad != null;

  @override
  void initState() {
    super.initState();
    _direction = widget.initialDirection ??
        widget.editingLoad?['direction']?.toString() ??
        'inbound';
    _selectedLocationId = widget.initialLocationId ??
        widget.editingLoad?['location_id']?.toString() ??
        widget.session.locationId;
    _initFromEditing();
    _loadYardContext();
  }

  void _initFromEditing() {
    final load = widget.editingLoad;
    if (load == null) return;

    _selectedVariantId = load['variant_id']?.toString() ?? load['product_id']?.toString();
    _selectedVehicleId = load['vehicle_id']?.toString();
    _selectedDriverId = load['driver_id']?.toString();
    if (_direction == 'inbound') {
      _selectedPartyId = load['supplier_id']?.toString();
    } else {
      _selectedPartyId = load['customer_id']?.toString();
    }

    _sourceCtrl.text = load['source_name']?.toString() ?? '';
    _destinationCtrl.text = load['destination_name']?.toString() ?? '';
    _slipRefCtrl.text = load['source_reference']?.toString() ?? '';
    _notesCtrl.text = load['notes']?.toString() ?? '';
    _unitCode = load['unit_code']?.toString() ?? 'CFT';

    final rawRate = load['rate'] ?? load['unit_price'];
    if (rawRate != null && (double.tryParse(rawRate.toString()) ?? 0) > 0) {
      _rateCtrl.text = rawRate.toString();
    }

    _measurementMethod = load['measurement_method']?.toString() ?? 'dimensions';
    _dimensionUnit = load['dimension_unit']?.toString() ?? 'in';

    if (load['body_length_ft'] != null) {
      _lengthCtrl.text = load['body_length_ft'].toString();
    }
    if (load['body_width_ft'] != null) {
      _widthCtrl.text = load['body_width_ft'].toString();
    }
    if (load['body_height_ft'] != null) {
      _heightCtrl.text = load['body_height_ft'].toString();
    }

    final rawDims = load['raw_dimensions'];
    if (rawDims is Map) {
      if (rawDims['length'] != null) _lengthCtrl.text = rawDims['length'].toString();
      if (rawDims['length_in'] != null) _lengthInCtrl.text = rawDims['length_in'].toString();
      if (rawDims['width'] != null) _widthCtrl.text = rawDims['width'].toString();
      if (rawDims['width_in'] != null) _widthInCtrl.text = rawDims['width_in'].toString();
      if (rawDims['height'] != null) _heightCtrl.text = rawDims['height'].toString();
      if (rawDims['height_in'] != null) _heightInCtrl.text = rawDims['height_in'].toString();
      if (rawDims['heap_adjustment_cft'] != null) {
        _heapAdjCtrl.text = rawDims['heap_adjustment_cft'].toString();
      }
      if (rawDims['heap_adjustment_reason'] != null) {
        _heapReasonCtrl.text = rawDims['heap_adjustment_reason'].toString();
      }
    }

    final qty = double.tryParse(load['quantity']?.toString() ?? '') ?? 0.0;
    _manualQtyCtrl.text = qty > 0 ? qty.toString() : '';

    _recalculateMeasurements();
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    _lengthInCtrl.dispose();
    _widthCtrl.dispose();
    _widthInCtrl.dispose();
    _heightCtrl.dispose();
    _heightInCtrl.dispose();
    _grossWeightCtrl.dispose();
    _tareWeightCtrl.dispose();
    _densityCtrl.dispose();
    _manualQtyCtrl.dispose();
    _heapAdjCtrl.dispose();
    _heapReasonCtrl.dispose();
    _rateCtrl.dispose();
    _sourceCtrl.dispose();
    _destinationCtrl.dispose();
    _slipRefCtrl.dispose();
    _notesCtrl.dispose();
    _overrideReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadYardContext() async {
    setState(() {
      _loadingContext = true;
      _contextError = null;
    });

    try {
      final data = await widget.service.materialYardContext(
        widget.session,
        locationId: _selectedLocationId,
      );
      if (!mounted) return;
      setState(() {
        _yardContext = data;
        _loadingContext = false;
        // If no variant selected, auto-select first
        final products = _products;
        if (_selectedVariantId == null && products.isNotEmpty) {
          _selectedVariantId = products.first['variant_id']?.toString();
          _applyDefaultRate();
        }
      });
      _recalculateMeasurements();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contextError = e.toString();
        _loadingContext = false;
      });
    }
  }

  List<Map<String, dynamic>> get _products =>
      (_yardContext['products'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _vehicles =>
      (_yardContext['vehicles'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _drivers =>
      (_yardContext['drivers'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _suppliers =>
      (_yardContext['suppliers'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _customers =>
      (_yardContext['customers'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _locations =>
      (_yardContext['locations'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _costTypes =>
      (_yardContext['cost_types'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  void _applyDefaultRate() {
    if (_selectedVariantId == null || _rateCtrl.text.isNotEmpty) return;
    final p = _products.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['variant_id']?.toString() == _selectedVariantId,
      orElse: () => null,
    );
    if (p != null) {
      final rawRate = _direction == 'inbound' ? p['cost_price'] : p['selling_price'];
      final numRate = double.tryParse(rawRate?.toString() ?? '') ?? 0.0;
      if (numRate > 0) {
        _rateCtrl.text = numRate.toStringAsFixed(2);
      }
    }
  }

  void _recalculateMeasurements() {
    final heapAdj = double.tryParse(_heapAdjCtrl.text.trim()) ?? 0.0;

    if (_measurementMethod == 'dimensions') {
      final l = double.tryParse(_lengthCtrl.text.trim()) ?? 0.0;
      final lIn = double.tryParse(_lengthInCtrl.text.trim()) ?? 0.0;
      final w = double.tryParse(_widthCtrl.text.trim()) ?? 0.0;
      final wIn = double.tryParse(_widthInCtrl.text.trim()) ?? 0.0;
      final h = double.tryParse(_heightCtrl.text.trim()) ?? 0.0;
      final hIn = double.tryParse(_heightInCtrl.text.trim()) ?? 0.0;

      final dimUnit = DimensionUnit.fromCode(_dimensionUnit);
      final cft = MaterialMeasurementEngine.calculateDimensionsVolume(
        length: l,
        lengthInchesPart: lIn,
        width: w,
        widthInchesPart: wIn,
        height: h,
        heightInchesPart: hIn,
        unit: dimUnit,
      );

      _calculatedCft = cft;
      _effectivePhysicalQty = cft;
      _effectiveBillableQty = (cft + heapAdj).clamp(0.0, double.infinity);
      _unitCode = 'CFT';
    } else if (_measurementMethod == 'weighbridge') {
      final gross = double.tryParse(_grossWeightCtrl.text.trim()) ?? 0.0;
      final tare = double.tryParse(_tareWeightCtrl.text.trim()) ?? 0.0;
      final density = double.tryParse(_densityCtrl.text.trim()) ?? 1.6;

      final net = (gross - tare).clamp(0.0, double.infinity);
      _effectivePhysicalQty = net;
      _effectiveBillableQty = net;
      _unitCode = 'TON';

      // Estimate equivalent CFT from tonnage and bulk density
      if (density > 0 && net > 0) {
        // 1 MT = (1 / density) m3 = (1 / density) * 35.3147 CFT
        _calculatedCft = (net / density) * MaterialMeasurementEngine.cftPerCubicMetre;
      } else {
        _calculatedCft = 0.0;
      }
    } else {
      // Manual
      final manualQty = double.tryParse(_manualQtyCtrl.text.trim()) ?? 0.0;
      _effectivePhysicalQty = manualQty;
      _effectiveBillableQty = (manualQty + heapAdj).clamp(0.0, double.infinity);
      _calculatedCft = _unitCode == 'CFT' ? manualQty : 0.0;
    }

    if (mounted) setState(() {});
  }

  void _onVehicleSelected(String? vehId) {
    _selectedVehicleId = vehId;
    if (vehId == null) return;

    final veh = _vehicles.cast<Map<String, dynamic>?>().firstWhere(
      (v) => v?['vehicle_id']?.toString() == vehId || v?['id']?.toString() == vehId,
      orElse: () => null,
    );

    if (veh != null) {
      // Auto-assign default driver if not already set
      if (_selectedDriverId == null && veh['default_driver_id'] != null) {
        _selectedDriverId = veh['default_driver_id']?.toString();
      }

      // If dimensions exist in vehicle profile, auto-populate dimensions!
      final l = veh['body_length_in'] ?? veh['body_length_ft'];
      final w = veh['body_width_in'] ?? veh['body_width_ft'];
      final h = veh['body_height_in'] ?? veh['body_height_ft'];

      if (l != null && _lengthCtrl.text.isEmpty) {
        _dimensionUnit = veh['body_length_in'] != null ? 'in' : 'ft';
        _lengthCtrl.text = l.toString();
      }
      if (w != null && _widthCtrl.text.isEmpty) {
        _widthCtrl.text = w.toString();
      }
      if (h != null && _heightCtrl.text.isEmpty) {
        _heightCtrl.text = h.toString();
      }
      _recalculateMeasurements();
    }
  }

  Future<void> _quickAddVehicle() async {
    final regCtrl = TextEditingController();
    final capCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'tipper');

    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Yard Truck / Vehicle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: regCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Registration Number *',
                hintText: 'e.g. KL-07-CD-5678',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: capCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Nominal Capacity (CFT)',
                hintText: 'e.g. 350',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final reg = regCtrl.text.trim().toUpperCase();
              if (reg.isEmpty) {
                ThqNotify.error(ctx, 'Required', message: 'Registration number is required.');
                return;
              }
              final cap = double.tryParse(capCtrl.text.trim());
              try {
                final newVeh = await widget.service.createServiceVehicle(
                  widget.session,
                  registration: reg,
                  vehicleType: typeCtrl.text.trim(),
                  nominalCapacityCft: cap,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
                await _loadYardContext();
                if (mounted) {
                  setState(() {
                    _selectedVehicleId = newVeh['id']?.toString() ?? newVeh['vehicle_id']?.toString();
                  });
                }
              } catch (e) {
                if (ctx.mounted) ThqNotify.error(ctx, 'Failed', message: '$e');
              }
            },
            child: const Text('Save Truck'),
          ),
        ],
      ),
    );
    regCtrl.dispose();
    capCtrl.dispose();
    typeCtrl.dispose();
  }

  Future<void> _quickAddDriver() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Yard Driver'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Driver Full Name *',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ThqNotify.error(ctx, 'Required', message: 'Driver name is required.');
                return;
              }
              try {
                final newDrv = await widget.service.saveLogisticsDriver(
                  widget.session,
                  fullName: name,
                  phone: phoneCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
                await _loadYardContext();
                if (mounted) {
                  setState(() {
                    _selectedDriverId = newDrv['id']?.toString() ?? newDrv['driver_id']?.toString();
                  });
                }
              } catch (e) {
                if (ctx.mounted) ThqNotify.error(ctx, 'Failed', message: '$e');
              }
            },
            child: const Text('Save Driver'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

  void _addExpense() async {
    String? selectedType;
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final payeeCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add Load Expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Expense Category *'),
                  items: _costTypes.map((ct) {
                    return DropdownMenuItem<String>(
                      value: ct['code']?.toString() ?? ct['id']?.toString(),
                      child: Text(ct['name']?.toString() ?? ct['label']?.toString() ?? 'Charge'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setDlg(() {
                      selectedType = val;
                      final match = _costTypes.firstWhere(
                        (ct) => (ct['code']?.toString() ?? ct['id']?.toString()) == val,
                        orElse: () => const {},
                      );
                      if (descCtrl.text.isEmpty) {
                        descCtrl.text = match['name']?.toString() ?? match['label']?.toString() ?? '';
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description *'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount *',
                    prefixText: '${widget.session.currency} ',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: payeeCtrl,
                  decoration: const InputDecoration(labelText: 'Payee / Transporter'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amt <= 0 || descCtrl.text.trim().isEmpty) {
                  ThqNotify.error(ctx, 'Required', message: 'Enter a valid description and amount.');
                  return;
                }
                setState(() {
                  _costs.add({
                    'cost_type_code': selectedType ?? 'other',
                    'description': descCtrl.text.trim(),
                    'amount': amt,
                    'payee': payeeCtrl.text.trim(),
                    'billing_service': 'internal',
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add Expense'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitLoad({required bool confirmImmediately}) async {
    if (_selectedLocationId == null) {
      ThqNotify.error(context, 'Store Scope', message: 'Select an operating yard/store location.');
      return;
    }

    if (_selectedVariantId == null) {
      ThqNotify.error(context, 'Required', message: 'Please select a material / product variant.');
      return;
    }

    final physicalQty = _effectivePhysicalQty;
    if (physicalQty <= 0) {
      ThqNotify.error(context, 'Quantity Required', message: 'Enter valid dimensions or quantity.');
      return;
    }

    // Validate Truck Capacity
    if (_selectedVehicleId != null) {
      final veh = _vehicles.cast<Map<String, dynamic>?>().firstWhere(
        (v) => v?['vehicle_id']?.toString() == _selectedVehicleId || v?['id']?.toString() == _selectedVehicleId,
        orElse: () => null,
      );
      final nomCap = double.tryParse(veh?['nominal_capacity_cft']?.toString() ?? '') ?? 0.0;
      if (nomCap > 0) {
        final loadCft = _calculatedCft > 0 ? _calculatedCft : (_unitCode == 'CFT' ? physicalQty : 0.0);
        final capError = MaterialMeasurementEngine.validateTruckCapacity(
          loadQtyCft: loadCft,
          nominalCapacityCft: nomCap,
          allowOverride: _capacityOverride,
          overrideReason: _overrideReasonCtrl.text,
        );
        if (capError != null) {
          ThqNotify.error(context, 'Capacity Overload', message: capError);
          return;
        }
      }
    }

    setState(() => _saving = true);

    try {
      final enteredRate = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
      final billableQty = _effectiveBillableQty > 0 ? _effectiveBillableQty : physicalQty;

      final rawDimensions = {
        'method': _measurementMethod,
        'unit': _dimensionUnit,
        'length': double.tryParse(_lengthCtrl.text.trim()),
        'length_in': double.tryParse(_lengthInCtrl.text.trim()),
        'width': double.tryParse(_widthCtrl.text.trim()),
        'width_in': double.tryParse(_widthInCtrl.text.trim()),
        'height': double.tryParse(_heightCtrl.text.trim()),
        'height_in': double.tryParse(_heightInCtrl.text.trim()),
        'gross_weight': double.tryParse(_grossWeightCtrl.text.trim()),
        'tare_weight': double.tryParse(_tareWeightCtrl.text.trim()),
        'bulk_density': double.tryParse(_densityCtrl.text.trim()),
        'heap_adjustment_cft': double.tryParse(_heapAdjCtrl.text.trim()) ?? 0.0,
        'heap_adjustment_reason': _heapReasonCtrl.text.trim(),
      };

      final deliveryData = <String, dynamic>{};
      if (enteredRate > 0) {
        if (_direction == 'inbound') {
          deliveryData['purchasing_price'] = enteredRate;
          deliveryData['purchasing_total'] = enteredRate * billableQty;
        } else {
          deliveryData['selling_price'] = enteredRate;
          deliveryData['selling_total'] = enteredRate * billableQty;
        }
      }

      if (isEditing) {
        // Edit existing draft
        await widget.service.editMaterialLoad(
          widget.session,
          loadId: widget.editingLoad!['id']?.toString() ?? widget.editingLoad!['load_id']?.toString() ?? '',
          locationId: _selectedLocationId!,
          direction: _direction,
          variantId: _selectedVariantId!,
          quantity: physicalQty,
          unitCode: _unitCode,
          measurementMethod: _measurementMethod,
          dimensionUnit: _dimensionUnit,
          calculatedCft: _calculatedCft,
          heapAdjustmentCft: double.tryParse(_heapAdjCtrl.text.trim()) ?? 0.0,
          approvedBillableQty: billableQty,
          rawDimensions: rawDimensions,
          vehicleId: _selectedVehicleId,
          driverId: _selectedDriverId,
          supplierId: _direction == 'inbound' ? _selectedPartyId : null,
          customerId: _direction == 'outbound' ? _selectedPartyId : null,
          sourceName: _sourceCtrl.text.trim(),
          destinationName: _destinationCtrl.text.trim(),
          sourceReference: _slipRefCtrl.text.trim(),
          capacityOverride: _capacityOverride,
          capacityOverrideReason: _overrideReasonCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
          costs: _costs,
          delivery: deliveryData,
        );

        if (confirmImmediately) {
          final loadId = widget.editingLoad!['id']?.toString() ?? widget.editingLoad!['load_id']?.toString() ?? '';
          await widget.service.confirmMaterialLoad(
            widget.session,
            loadId: loadId,
            locationId: _selectedLocationId,
          );
        }

        if (!mounted) return;
        setState(() => _saving = false);
        ThqNotify.success(
          context,
          confirmImmediately ? 'Load Confirmed' : 'Draft Updated',
          message: confirmImmediately ? 'Load has been verified and confirmed.' : 'Draft load updated successfully.',
        );
        widget.onSaved();
        Navigator.pop(context, true);
      } else {
        // Create new load
        final created = await widget.service.createMaterialLoad(
          widget.session,
          direction: _direction,
          locationId: _selectedLocationId!,
          variantId: _selectedVariantId!,
          quantity: physicalQty,
          unitCode: _unitCode,
          measurementMethod: _measurementMethod,
          dimensionUnit: _dimensionUnit,
          calculatedCft: _calculatedCft,
          heapAdjustmentCft: double.tryParse(_heapAdjCtrl.text.trim()) ?? 0.0,
          approvedBillableQty: billableQty,
          rawDimensions: rawDimensions,
          vehicleId: _selectedVehicleId,
          driverId: _selectedDriverId,
          supplierId: _direction == 'inbound' ? _selectedPartyId : null,
          customerId: _direction == 'outbound' ? _selectedPartyId : null,
          sourceName: _sourceCtrl.text.trim(),
          destinationName: _destinationCtrl.text.trim(),
          sourceReference: _slipRefCtrl.text.trim(),
          capacityOverride: _capacityOverride,
          capacityOverrideReason: _overrideReasonCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
          costs: _costs,
          delivery: deliveryData,
        );

        if (confirmImmediately) {
          final newLoadId = created['load_id']?.toString() ?? created['id']?.toString();
          if (newLoadId != null) {
            await widget.service.confirmMaterialLoad(
              widget.session,
              loadId: newLoadId,
              locationId: _selectedLocationId,
            );
          }
        }

        if (!mounted) return;
        setState(() => _saving = false);
        ThqNotify.success(
          context,
          confirmImmediately ? 'Load Confirmed' : 'Draft Created',
          message: confirmImmediately
              ? 'Material load recorded and confirmed.'
              : 'Draft load saved. You can verify and confirm it anytime.',
        );
        widget.onSaved();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ThqNotify.error(context, 'Save Failed', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = widget.session.currency;

    if (_loadingContext) {
      return Container(
        height: 380,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading yard products, fleet & pricing...'),
          ],
        ),
      );
    }

    if (_contextError != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('Error loading workspace: $_contextError', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadYardContext, child: const Text('Retry')),
          ],
        ),
      );
    }

    final estRate = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    final estTotal = estRate * (_effectiveBillableQty > 0 ? _effectiveBillableQty : _effectivePhysicalQty);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing
            ? 'Edit Draft Load'
            : _direction == 'inbound'
                ? 'New Inward Load'
                : 'New Outward Load'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // Direction Segmented Button (only when creating new)
            if (!isEditing) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'inbound',
                    label: Text('Inward (Quarry → Yard)'),
                    icon: Icon(Icons.south_west_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: 'outbound',
                    label: Text('Outward (Yard → Customer)'),
                    icon: Icon(Icons.north_east_rounded, size: 16),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (val) {
                  setState(() {
                    _direction = val.first;
                    _selectedPartyId = null;
                    _rateCtrl.clear();
                    _applyDefaultRate();
                  });
                },
              ),
              const SizedBox(height: 12),
            ],

            // Section 1: Location & Material
            _buildSectionHeader('1. Yard & Material', Icons.inventory_2_outlined),
            const SizedBox(height: 8),

            // Operating Yard Location Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedLocationId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Operating Yard / Store *',
                prefixIcon: Icon(Icons.warehouse_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _locations.map((loc) {
                return DropdownMenuItem<String>(
                  value: loc['location_id']?.toString() ?? loc['id']?.toString(),
                  child: Text('${loc['code'] ?? ''} • ${loc['name'] ?? ''}', overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedLocationId = val);
                _loadYardContext();
              },
            ),
            const SizedBox(height: 10),

            // Material Variant Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedVariantId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Material & Quality Grade *',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _products.map((p) {
                final name = p['name'] ?? 'Product';
                final variant = p['variant_name'] ?? '';
                final displayName = variant.toString().trim().isNotEmpty ? '$name ($variant)' : name;
                return DropdownMenuItem<String>(
                  value: p['variant_id']?.toString(),
                  child: Text(displayName, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedVariantId = val;
                  _rateCtrl.clear();
                  _applyDefaultRate();
                });
              },
            ),

            const SizedBox(height: 16),

            // Section 2: Party & Transport
            _buildSectionHeader(
              _direction == 'inbound' ? '2. Quarry Supplier & Fleet' : '2. Customer & Fleet',
              Icons.local_shipping_outlined,
            ),
            const SizedBox(height: 8),

            // Party Dropdown (Supplier or Customer)
            if (_direction == 'inbound')
              DropdownButtonFormField<String>(
                initialValue: _selectedPartyId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Supplier / Quarry Company *',
                  prefixIcon: Icon(Icons.business_outlined),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _suppliers.map((s) {
                  return DropdownMenuItem<String>(
                    value: s['supplier_id']?.toString() ?? s['id']?.toString(),
                    child: Text(s['name'] ?? 'Supplier', overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedPartyId = val),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedPartyId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Customer / Buyer *',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _customers.map((c) {
                  return DropdownMenuItem<String>(
                    value: c['customer_id']?.toString() ?? c['id']?.toString(),
                    child: Text(c['name'] ?? 'Customer', overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedPartyId = val),
              ),

            const SizedBox(height: 10),

            // Truck Selector with Quick Add
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedVehicleId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Yard Truck / Vehicle',
                      prefixIcon: Icon(Icons.fire_truck_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _vehicles.map((v) {
                      final reg = v['registration_number'] ?? v['vehicle_registration'] ?? 'Truck';
                      final cap = v['nominal_capacity_cft'];
                      final capText = cap != null ? ' ($cap CFT)' : '';
                      return DropdownMenuItem<String>(
                        value: v['vehicle_id']?.toString() ?? v['id']?.toString(),
                        child: Text('$reg$capText', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: _onVehicleSelected,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Add Truck',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _quickAddVehicle,
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Driver Selector with Quick Add
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedDriverId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Driver',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _drivers.map((d) {
                      final name = d['full_name'] ?? d['driver_name'] ?? 'Driver';
                      final phone = d['phone'] ?? '';
                      final phoneText = phone.isNotEmpty ? ' • $phone' : '';
                      return DropdownMenuItem<String>(
                        value: d['driver_id']?.toString() ?? d['id']?.toString(),
                        child: Text('$name$phoneText', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedDriverId = val),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Add Driver',
                  icon: const Icon(Icons.person_add_outlined),
                  onPressed: _quickAddDriver,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Section 3: Physical Measurement Engine
            _buildSectionHeader('3. Measurements & Quantity', Icons.straighten_rounded),
            const SizedBox(height: 8),

            // Method Selector
            Row(
              children: [
                _buildMethodChoice('dimensions', 'Body Dimensions', Icons.aspect_ratio_rounded),
                const SizedBox(width: 8),
                _buildMethodChoice('manual', 'Manual Qty', Icons.edit_note_rounded),
                const SizedBox(width: 8),
                _buildMethodChoice('weighbridge', 'Weighbridge', Icons.scale_rounded),
              ],
            ),

            const SizedBox(height: 12),

            if (_measurementMethod == 'dimensions') ...[
              // Dimension Unit Selector
              Row(
                children: [
                  const Text('Unit: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Wrap(
                    spacing: 6,
                    children: [
                      _buildDimUnitChip('in', 'Inches (in)'),
                      _buildDimUnitChip('ft', 'Feet (ft)'),
                      _buildDimUnitChip('ft_in', 'Ft + In'),
                      _buildDimUnitChip('m', 'Metres (m)'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Dimensions Input Rows
              if (_dimensionUnit == 'ft_in') ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _lengthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Length (ft)', border: OutlineInputBorder(), isDense: true),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _lengthInCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Length (in)', border: OutlineInputBorder(), isDense: true),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _widthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Width (ft)', border: OutlineInputBorder(), isDense: true),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _widthInCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Width (in)', border: OutlineInputBorder(), isDense: true),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _heightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Height (ft)', border: OutlineInputBorder(), isDense: true),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _heightInCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Height (in)', border: OutlineInputBorder(), isDense: true),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lengthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Length ($_dimensionUnit)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _widthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Width ($_dimensionUnit)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _heightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Height ($_dimensionUnit)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => _recalculateMeasurements(),
                      ),
                    ),
                  ],
                ),
              ],
            ] else if (_measurementMethod == 'weighbridge') ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _grossWeightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Gross (TON)', border: OutlineInputBorder(), isDense: true),
                      onChanged: (_) => _recalculateMeasurements(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _tareWeightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Tare (TON)', border: OutlineInputBorder(), isDense: true),
                      onChanged: (_) => _recalculateMeasurements(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _densityCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Density (MT/m³)', border: OutlineInputBorder(), isDense: true),
                      onChanged: (_) => _recalculateMeasurements(),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _manualQtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Quantity *', border: OutlineInputBorder(), isDense: true),
                      onChanged: (_) => _recalculateMeasurements(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _unitCode,
                      decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'CFT', child: Text('CFT')),
                        DropdownMenuItem(value: 'TON', child: Text('TON')),
                        DropdownMenuItem(value: 'CBM', child: Text('CBM')),
                        DropdownMenuItem(value: 'LOAD', child: Text('LOAD')),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _unitCode = val ?? 'CFT';
                          _recalculateMeasurements();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),

            // Heap Adjustment row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heapAdjCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Heap Adjustment (CFT +/-)',
                      hintText: '+/- 20',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _recalculateMeasurements(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _heapReasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Heap Reason',
                      hintText: 'e.g. Crown heap',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Live Calculation Highlight Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCalcStat('Calculated Volume', MaterialYardFormat.cft(_calculatedCft)),
                  Container(width: 1, height: 32, color: scheme.outlineVariant),
                  _buildCalcStat(
                    'Billable Quantity',
                    MaterialYardFormat.quantity(_effectiveBillableQty > 0 ? _effectiveBillableQty : _effectivePhysicalQty, _unitCode),
                    highlight: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Capacity override switch
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _capacityOverride,
              title: const Text('Allow Truck Capacity Override', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: const Text('Check if physical volume exceeds truck registered payload.', style: TextStyle(fontSize: 11)),
              onChanged: (val) => setState(() => _capacityOverride = val),
            ),
            if (_capacityOverride) ...[
              TextField(
                controller: _overrideReasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supervisor Override Reason *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
            ],

            const SizedBox(height: 16),

            // Section 4: Rates, Values & Reference
            _buildSectionHeader('4. Rate & Commercial Details', Icons.price_change_outlined),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Rate per $_unitCode',
                      prefixText: '$currency ',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Estimated Value', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                        Text(
                          estTotal > 0 ? MaterialYardFormat.money(estTotal, currency: currency) : 'Rate Pending',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: estTotal > 0 ? scheme.primary : null,
                          ),
                        ),
                      ],
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
                    controller: _sourceCtrl,
                    decoration: const InputDecoration(labelText: 'Source Location', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _destinationCtrl,
                    decoration: const InputDecoration(labelText: 'Destination Site', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _slipRefCtrl,
              decoration: const InputDecoration(
                labelText: 'Quarry Slip / Source Invoice Ref',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            const SizedBox(height: 16),

            // Section 5: Load Expenses (Freight, Driver, Fuel)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader('5. Expenses & Freight', Icons.receipt_long_outlined),
                TextButton.icon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Expense', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),

            if (_costs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No extra freight, diesel or driver wages recorded.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              )
            else
              ..._costs.asMap().entries.map((entry) {
                final idx = entry.key;
                final c = entry.value;
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text('${c['description']} • ${MaterialYardFormat.money(c['amount'], currency: currency)}'),
                    subtitle: Text('Payee: ${c['payee'].toString().isEmpty ? "Self" : c['payee']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () => setState(() => _costs.removeAt(idx)),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 10),

            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Internal Notes',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -3)),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _submitLoad(confirmImmediately: false),
                  child: Text(isEditing ? 'Save Draft' : 'Save as Draft'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _submitLoad(confirmImmediately: true),
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(_saving ? 'Saving...' : 'Confirm Load'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildMethodChoice(String method, String label, IconData icon) {
    final selected = _measurementMethod == method;
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _measurementMethod = method;
            _recalculateMeasurements();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.5),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDimUnitChip(String unit, String label) {
    final selected = _dimensionUnit == unit;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
      onSelected: (_) {
        setState(() {
          _dimensionUnit = unit;
          _recalculateMeasurements();
        });
      },
    );
  }

  Widget _buildCalcStat(String label, String value, {bool highlight = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: highlight ? scheme.primary : null,
          ),
        ),
      ],
    );
  }
}
