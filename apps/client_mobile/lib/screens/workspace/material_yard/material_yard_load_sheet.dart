import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';
import 'package:thq_ui/thq_ui.dart';

import 'package:uuid/uuid.dart';

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

    final rawCosts = load['costs'] ?? load['expenses'];
    if (rawCosts is List) {
      _costs.clear();
      for (final c in rawCosts) {
        if (c is Map) {
          _costs.add(Map<String, dynamic>.from(c));
        }
      }
    }

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

  List<Map<String, dynamic>> get _staff =>
      (_yardContext['staff'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _billingServices =>
      (_yardContext['billing_services'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> get _expenseCategories {
    final list = (_yardContext['expense_categories'] as List? ??
            _yardContext['cost_types'] as List? ??
            const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (list.isNotEmpty) return list;
    return const [
      {'id': 'diesel', 'name': 'Diesel'},
      {'id': 'driver_wage', 'name': 'Driver Wages'},
      {'id': 'vehicle_rent', 'name': 'Vehicle Rent'},
      {'id': 'freight', 'name': 'Freight'},
      {'id': 'loading', 'name': 'Loading Charges'},
      {'id': 'unloading', 'name': 'Unloading Charges'},
      {'id': 'repairs', 'name': 'Repairs & Maintenance'},
      {'id': 'toll', 'name': 'Toll & Transit'},
      {'id': 'other', 'name': 'Other Expense'},
    ];
  }

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

  void _addExpense([int? editIndex]) async {
    final old = editIndex != null && editIndex >= 0 && editIndex < _costs.length ? _costs[editIndex] : null;

    // Resolve driver/staff linkage
    Map<String, dynamic>? linkedStaff;
    if (_selectedDriverId != null) {
      for (final s in _staff) {
        if ('${s['driver_id']}' == _selectedDriverId) {
          linkedStaff = s;
          break;
        }
      }
    }

    final isMonthly = linkedStaff?['wage_basis'] == 'monthly';

    // State variables
    String? selectedCatId = old?['category_id']?.toString() ??
        (old?['cost_type_code'] ?? old?['cost_kind'] ?? (linkedStaff != null ? 'driver_wage' : 'diesel'));
    String staffId = old?['staff_id']?.toString() ?? linkedStaff?['staff_id']?.toString() ?? '';
    String staffMode = old?['staff_mode']?.toString() ?? (isMonthly ? 'salary_allocation' : 'extra_wage');
    String paymentMethod = old?['payment_method']?.toString() ?? 'cash';
    String billingVariantId = old?['billing_variant_id']?.toString() ?? '';

    final initialQty = (old?['quantity'] as num?)?.toDouble() ?? 1.0;
    final initialRate = isMonthly && old == null
        ? 0.0
        : ((old?['rate'] as num?)?.toDouble() ?? (old?['amount'] as num?)?.toDouble() ?? (linkedStaff?['base_rate'] as num?)?.toDouble() ?? 0.0);
    final initialAmt = (old?['amount'] as num?)?.toDouble() ?? (initialQty * initialRate);
    final initialPay = (old?['initial_payment'] as num?)?.toDouble() ?? (old?['payment_amount'] as num?)?.toDouble() ?? 0.0;
    final initialBill = (old?['bill_amount'] as num?)?.toDouble() ?? 0.0;

    String paymentStatus = initialPay >= initialAmt && initialAmt > 0
        ? 'paid'
        : (initialPay > 0 ? 'partially_paid' : 'not_paid');

    final descCtrl = TextEditingController(text: old?['description']?.toString() ?? (linkedStaff != null ? 'Driver wage' : ''));
    final payeeCtrl = TextEditingController(text: old?['payee']?.toString() ?? linkedStaff?['name']?.toString() ?? '');
    final qtyCtrl = TextEditingController(text: initialQty > 0 ? (initialQty == initialQty.roundToDouble() ? initialQty.toInt().toString() : initialQty.toString()) : '1');
    final rateCtrl = TextEditingController(text: initialRate > 0 ? (initialRate == initialRate.roundToDouble() ? initialRate.toInt().toString() : initialRate.toString()) : (initialAmt > 0 ? initialAmt.toString() : ''));
    final billCtrl = TextEditingController(text: initialBill > 0 ? (initialBill == initialBill.roundToDouble() ? initialBill.toInt().toString() : initialBill.toString()) : '0');
    final payCtrl = TextEditingController(text: initialPay > 0 ? (initialPay == initialPay.roundToDouble() ? initialPay.toInt().toString() : initialPay.toString()) : '0');
    final payRefCtrl = TextEditingController(text: old?['payment_reference']?.toString() ?? '');
    final receiptRefCtrl = TextEditingController(text: old?['receipt_reference']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: old?['notes']?.toString() ?? '');

    bool chargeCustomer = initialBill > 0;
    bool showMoreDetails = (old?['receipt_reference']?.toString().isNotEmpty ?? false) || (old?['notes']?.toString().isNotEmpty ?? false);
    String? dialogError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final theme = Theme.of(ctx);
          final scheme = theme.colorScheme;
          final categories = _expenseCategories;

          final costQty = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;
          final costRate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
          final totalCost = costQty * costRate;
          final custCharge = chargeCustomer ? (double.tryParse(billCtrl.text.trim()) ?? 0.0) : 0.0;
          final enteredPay = double.tryParse(payCtrl.text.trim()) ?? 0.0;
          final payMade = paymentStatus == 'paid'
              ? (enteredPay > 0 ? enteredPay : totalCost)
              : (paymentStatus == 'not_paid' ? 0.0 : enteredPay);
          final remainingPay = (totalCost - payMade).clamp(0.0, double.infinity);

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            title: Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    old == null ? 'Add Load Expense' : 'Edit Load Expense',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dialogError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 16, color: scheme.onErrorContainer),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: TextStyle(color: scheme.onErrorContainer, fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Category dropdown with inline "+ Add Type"
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: categories.any((c) => '${c['id']}' == selectedCatId || '${c['code']}' == selectedCatId || '${c['name']}' == selectedCatId)
                                ? selectedCatId
                                : (categories.isNotEmpty ? '${categories.first['id'] ?? categories.first['code']}' : null),
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: 'Expense Category *', isDense: true),
                            items: categories.map((cat) {
                              final val = '${cat['id'] ?? cat['code']}';
                              final name = '${cat['name'] ?? cat['label'] ?? val}';
                              return DropdownMenuItem<String>(
                                value: val,
                                child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setDlg(() {
                                selectedCatId = val;
                                final match = categories.firstWhere(
                                  (c) => '${c['id'] ?? c['code']}' == val,
                                  orElse: () => const {},
                                );
                                if (descCtrl.text.isEmpty && match.isNotEmpty) {
                                  descCtrl.text = '${match['name'] ?? match['label'] ?? ''}';
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _showInlineCreateCategory(ctx, (created) {
                            setDlg(() {
                              selectedCatId = '${created['id']}';
                              if (descCtrl.text.trim().isEmpty) {
                                descCtrl.text = '${created['name']}';
                              }
                            });
                          }),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('+ Add', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Description
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Description *', isDense: true),
                    ),
                    const SizedBox(height: 10),

                    // Quantity and Rate
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Qty / Trips', isDense: true),
                            onChanged: (_) => setDlg(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: rateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Rate / Unit *',
                              prefixText: '${widget.session.currency} ',
                              isDense: true,
                            ),
                            onChanged: (_) => setDlg(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Payee / Staff
                    TextField(
                      controller: payeeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Payee / Transporter / Driver *',
                        isDense: true,
                        helperText: linkedStaff != null ? 'Linked to driver staff: ${linkedStaff['name']}' : null,
                      ),
                    ),

                    // Monthly staff wage treatment
                    if (isMonthly) ...[
                      const SizedBox(height: 8),
                      Material(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Monthly Staff Wage', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: 'salary_allocation',
                                groupValue: staffMode,
                                title: const Text('Covered by monthly salary', style: TextStyle(fontSize: 11.5)),
                                subtitle: const Text('Internal cost, no duplicate wage liability', style: TextStyle(fontSize: 10)),
                                onChanged: (val) => setDlg(() {
                                  staffMode = val!;
                                  paymentStatus = 'not_paid';
                                  payCtrl.text = '0';
                                }),
                              ),
                              RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: 'extra_wage',
                                groupValue: staffMode,
                                title: const Text('Extra incentive / overtime owed', style: TextStyle(fontSize: 11.5)),
                                subtitle: const Text('Records extra payable wage on this load', style: TextStyle(fontSize: 10)),
                                onChanged: (val) => setDlg(() => staffMode = val!),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),

                    // Payment status
                    const Text('Payment Settlement', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'not_paid', label: Text('Unpaid', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'paid', label: Text('Paid', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: 'partially_paid', label: Text('Partial', style: TextStyle(fontSize: 11))),
                      ],
                      selected: {paymentStatus},
                      onSelectionChanged: (set) => setDlg(() {
                        paymentStatus = set.first;
                        if (paymentStatus == 'paid') {
                          payCtrl.text = totalCost > 0 ? (totalCost == totalCost.roundToDouble() ? totalCost.toInt().toString() : totalCost.toStringAsFixed(2)) : '0';
                        } else if (paymentStatus == 'not_paid') {
                          payCtrl.text = '0';
                        }
                      }),
                    ),
                    const SizedBox(height: 8),

                    // Payment details
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: payCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Payment Made',
                              prefixText: '${widget.session.currency} ',
                              isDense: true,
                              helperText: paymentStatus == 'not_paid'
                                  ? 'Unpaid (₹${totalCost.toStringAsFixed(0)} payable)'
                                  : 'Due: ₹${remainingPay.toStringAsFixed(0)}',
                            ),
                            onChanged: (val) {
                              final amt = double.tryParse(val.trim()) ?? 0.0;
                              setDlg(() {
                                if (amt <= 0) {
                                  paymentStatus = 'not_paid';
                                } else if (amt >= totalCost && totalCost > 0) {
                                  paymentStatus = 'paid';
                                } else {
                                  paymentStatus = 'partially_paid';
                                }
                              });
                            },
                          ),
                        ),
                        if (paymentStatus != 'not_paid' || (double.tryParse(payCtrl.text.trim()) ?? 0.0) > 0) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: paymentMethod,
                              decoration: const InputDecoration(labelText: 'Method', isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'cash', child: Text('Cash', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'bank', child: Text('Bank', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'upi', child: Text('UPI', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'card', child: Text('Card', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: 'cheque', child: Text('Cheque', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: (val) => setDlg(() => paymentMethod = val ?? 'cash'),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Customer invoice charge (outbound only)
                    if (_direction == 'outbound') ...[
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Charge to Customer Invoice', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Add as line item on sales invoice', style: TextStyle(fontSize: 10)),
                        value: chargeCustomer,
                        onChanged: (val) => setDlg(() {
                          chargeCustomer = val;
                          if (val && (double.tryParse(billCtrl.text.trim()) ?? 0) <= 0) {
                            billCtrl.text = totalCost > 0 ? (totalCost == totalCost.roundToDouble() ? totalCost.toInt().toString() : totalCost.toStringAsFixed(2)) : '0';
                          }
                        }),
                      ),
                      if (chargeCustomer) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: billCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Customer Charge *',
                                  prefixText: '${widget.session.currency} ',
                                  isDense: true,
                                ),
                                onChanged: (_) => setDlg(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: billingVariantId.isEmpty ? null : billingVariantId,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Service Tax *', isDense: true),
                                items: [
                                  const DropdownMenuItem(value: '', child: Text('Select service', style: TextStyle(fontSize: 12))),
                                  for (final s in _billingServices)
                                    DropdownMenuItem(
                                      value: '${s['variant_id']}',
                                      child: Text(
                                        '${s['name']} (${s['gst_rate'] ?? 0}%)',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                ],
                                onChanged: (val) => setDlg(() => billingVariantId = val ?? ''),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    // Expandable Reference & Notes
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => setDlg(() => showMoreDetails = !showMoreDetails),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(showMoreDetails ? Icons.expand_less : Icons.expand_more, size: 18, color: scheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              showMoreDetails ? 'Hide References' : 'Add Receipt / Notes',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (showMoreDetails) ...[
                      const SizedBox(height: 6),
                      TextField(
                        controller: receiptRefCtrl,
                        decoration: const InputDecoration(labelText: 'Receipt / Voucher #', isDense: true),
                      ),
                      const SizedBox(height: 8),
                      if (paymentMethod != 'cash') ...[
                        TextField(
                          controller: payRefCtrl,
                          decoration: const InputDecoration(labelText: 'Payment Reference / UTR', isDense: true),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Internal Notes', isDense: true),
                      ),
                    ],

                    // Live Summary Box
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total: ₹${totalCost.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                              if (chargeCustomer)
                                Text('Bill: ₹${custCharge.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF635BFF))),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Paid: ₹${payMade.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF00875A))),
                              if (remainingPay > 0 && staffMode != 'salary_allocation')
                                Text('Due: ₹${remainingPay.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFC06200))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final freshQty = double.tryParse(qtyCtrl.text.trim()) ?? 1.0;
                  final freshRate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                  final freshAmt = freshQty * freshRate;
                  final freshCustCharge = chargeCustomer ? (double.tryParse(billCtrl.text.trim()) ?? 0.0) : 0.0;
                  final freshEnteredPay = double.tryParse(payCtrl.text.trim()) ?? 0.0;
                  final freshPayMade = paymentStatus == 'paid'
                      ? (freshEnteredPay > 0 ? freshEnteredPay : freshAmt)
                      : (paymentStatus == 'not_paid' ? 0.0 : freshEnteredPay);

                  if (freshAmt <= 0) {
                    setDlg(() => dialogError = 'Enter a positive quantity and rate.');
                    return;
                  }
                  if (descCtrl.text.trim().isEmpty) {
                    setDlg(() => dialogError = 'Description is required.');
                    return;
                  }
                  if (payeeCtrl.text.trim().isEmpty && staffId.isEmpty) {
                    setDlg(() => dialogError = 'Enter the payee name.');
                    return;
                  }
                  if (staffMode == 'salary_allocation' && (staffId.isEmpty || freshPayMade > 0 || freshEnteredPay > 0)) {
                    setDlg(() => dialogError = 'Salary allocation cannot have a separate load payment.');
                    return;
                  }
                  if (_direction == 'outbound' && chargeCustomer && freshCustCharge > 0 && billingVariantId.isEmpty) {
                    setDlg(() => dialogError = 'Select a service tax classification for customer billing.');
                    return;
                  }
                  if (freshPayMade > 0 && paymentMethod != 'cash' && payRefCtrl.text.trim().isEmpty) {
                    setDlg(() => dialogError = 'Enter payment reference for non-cash payment.');
                    return;
                  }

                  final catMatch = categories.firstWhere(
                    (c) => '${c['id'] ?? c['code']}' == selectedCatId,
                    orElse: () => const {'id': 'other', 'name': 'Other'},
                  );

                  final costRow = <String, dynamic>{
                    'id': old?['id'] ?? const Uuid().v4(),
                    'cost_kind': selectedCatId ?? 'other',
                    'category_id': catMatch['id']?.toString() ?? selectedCatId,
                    'category_name': catMatch['name']?.toString() ?? 'Other',
                    'description': descCtrl.text.trim(),
                    'staff_id': staffId,
                    'payee': payeeCtrl.text.trim(),
                    'staff_mode': staffMode,
                    'quantity': freshQty,
                    'rate': freshRate,
                    'amount': freshAmt,
                    'bill_amount': (_direction != 'outbound' || !chargeCustomer) ? 0.0 : freshCustCharge,
                    'billing_variant_id': chargeCustomer ? billingVariantId : '',
                    'initial_payment': freshPayMade,
                    'payment_method': paymentMethod,
                    'payment_reference': payRefCtrl.text.trim(),
                    'receipt_reference': receiptRefCtrl.text.trim(),
                    'notes': notesCtrl.text.trim(),
                  };

                  setState(() {
                    if (editIndex != null && editIndex >= 0 && editIndex < _costs.length) {
                      _costs[editIndex] = costRow;
                    } else {
                      _costs.add(costRow);
                    }
                  });
                  Navigator.pop(ctx);
                },
                child: Text(old == null ? 'Add Expense' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showInlineCreateCategory(
    BuildContext parentCtx,
    ValueChanged<Map<String, dynamic>> onCreated,
  ) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? err;
    bool saving = false;

    await showDialog(
      context: parentCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AlertDialog(
          title: const Text('New Expense Type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (err != null) ...[
                Text(err!, style: const TextStyle(color: Colors.red, fontSize: 11)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Expense Type Name *', isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description (optional)', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setM(() => err = 'Please enter a name.');
                        return;
                      }
                      setM(() {
                        saving = true;
                        err = null;
                      });
                      try {
                        final created = await widget.service.createExpenseCategory(
                          widget.session,
                          name: name,
                          description: descCtrl.text.trim(),
                        );
                        // Add to local yardContext
                        final existing = List<Map<String, dynamic>>.from(
                          (_yardContext['expense_categories'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
                        );
                        existing.removeWhere((c) => '${c['name']}'.toLowerCase() == name.toLowerCase());
                        existing.add(created);
                        _yardContext['expense_categories'] = existing;

                        onCreated(created);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          setM(() {
                            saving = false;
                            err = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Create'),
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
                final amt = (c['amount'] as num?)?.toDouble() ?? 0.0;
                final pay = (c['initial_payment'] as num?)?.toDouble() ?? 0.0;
                final bill = (c['bill_amount'] as num?)?.toDouble() ?? 0.0;
                final isSalary = c['staff_mode'] == 'salary_allocation';

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: ListTile(
                    dense: true,
                    onTap: () => _addExpense(idx),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${c['category_name'] ?? c['cost_kind'] ?? 'Expense'}: ${c['description']}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          MaterialYardFormat.money(amt, currency: currency),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text('Payee: ${c['payee']?.toString().isEmpty ?? true ? "Self" : c['payee']}'),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (isSalary)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Salary Allocation', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                              )
                            else if (pay >= amt && amt > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3FCEF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Paid', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF006644))),
                              )
                            else if (pay > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF0B3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Partial (Paid ₹${pay.toStringAsFixed(0)})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF172B4D))),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEBE6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Unpaid (Due ₹${amt.toStringAsFixed(0)})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDE350B))),
                              ),
                            if (bill > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAE6FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Billed: ₹${bill.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF403294))),
                              ),
                          ],
                        ),
                      ],
                    ),
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
