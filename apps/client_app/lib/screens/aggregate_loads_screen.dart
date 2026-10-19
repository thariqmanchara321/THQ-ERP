import 'package:intl/intl.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';

import '../models/material_measurement_engine.dart';
import '../services/staff_load_service.dart';
import '../widgets/load_cost_editor.dart';
import '../widgets/material_measurement_form.dart';
import 'material_load_detail_screen.dart';
import 'material_load_reports_screen.dart';

import '../models/client_session.dart';
import '../services/aggregate_yard_service.dart';
import '../services/location_scope_service.dart';
import '../widgets/searchable_material_selectors.dart';
import 'purchase_detail_screen.dart';
import 'purchases_screen.dart';
import 'sale_detail_screen.dart';
import 'sales_screen.dart';
import 'transport_logistics_hub_screen.dart';

class AggregateLoadsScreen extends StatefulWidget {
  final ClientSession session;
  final String? initialCreateDirection;
  final String? initialDirection;
  final String? initialLoadId;

  const AggregateLoadsScreen({
    super.key,
    required this.session,
    this.initialCreateDirection,
    this.initialDirection,
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
  Map<String, int> _counts = const {};
  bool _loading = true;
  String? _error;
  String? _status = 'needs_action';
  String? _direction;
  bool _autoCreateOpened = false;
  bool _isTableView = false;
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
    _direction = widget.initialDirection;
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

  // ==========================================
  // DERIVED WORKFLOW STATUS HELPERS
  // ==========================================
  bool _isRatePending(Map<String, dynamic> row) {
    if (row['is_rate_pending'] == true) return true;
    final invRate = row['invoice_rate'] is num
        ? (row['invoice_rate'] as num).toDouble()
        : double.tryParse(row['invoice_rate']?.toString() ?? '');
    return invRate == null || invRate <= 0;
  }

  bool _isBilled(Map<String, dynamic> row) {
    if (row['workflow_status'] == 'billed') return true;
    final status = row['status']?.toString();
    if (status != 'completed') return false;

    final isInbound = row['direction'] == 'inbound';
    final hasDoc = _id(row[isInbound ? 'purchase_id' : 'sale_id']) != null;
    if (!hasDoc) return false;

    final invStatus = row['invoice_status']?.toString().toLowerCase();
    if (invStatus != null && invStatus.isNotEmpty) {
      return invStatus == 'posted';
    }
    final invNum = row['invoice_number']?.toString();
    return invNum != null && invNum.isNotEmpty && invStatus != 'void' && invStatus != 'cancelled';
  }

  String _derivedWorkflowStatus(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    if (status == 'cancelled') return 'cancelled';
    if (status == 'draft') return 'draft';
    if (_isBilled(row)) return 'billed';
    if (status == 'completed' && _isRatePending(row)) return 'rate_pending';
    if (status == 'completed') return 'unbilled';
    return status ?? 'draft';
  }

  bool _isNeedsAction(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    if (status == 'cancelled') return false;
    return !_isBilled(row);
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

      // Fetch authoritative counts across complete dataset
      final countsFuture = _service.loadCounts(
        tenantId: widget.session.business.id,
        locationId: _locationId,
        direction: _direction,
      );

      final rowsFuture = _service.loads(
        tenantId: widget.session.business.id,
        locationId: _locationId,
        status: _status == 'all' ? null : _status,
        query: _search.text.trim(),
        direction: _direction,
      );

      final results = await Future.wait([countsFuture, rowsFuture]);
      _counts = results[0] as Map<String, int>;
      final rawRows = results[1] as List<Map<String, dynamic>>;

      _rows = switch (_status) {
        'needs_action' => rawRows.where(_isNeedsAction).toList(growable: false),
        'draft' => rawRows.where((r) => _derivedWorkflowStatus(r) == 'draft').toList(growable: false),
        'unbilled' => rawRows.where((r) => r['status'] == 'completed' && !_isBilled(r)).toList(growable: false),
        'rate_pending' => rawRows.where((r) => !_isBilled(r) && r['status'] != 'cancelled' && _isRatePending(r)).toList(growable: false),
        'billed' => rawRows.where(_isBilled).toList(growable: false),
        'cancelled' => rawRows.where((r) => r['status'] == 'cancelled').toList(growable: false),
        _ => rawRows,
      };

      if (_direction != null && _direction!.isNotEmpty && _direction != 'all') {
        _rows = _rows.where((row) => row['direction'] == _direction).toList(growable: false);
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

  // ==========================================
  // CREATE LOAD (4-GROUP COMPACT DIALOG)
  // ==========================================
  Future<void> _createLoad({String? initialDirection}) async {
    final products = _list('products');
    final vehicles = _list('vehicles');
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
    String? productId;
    String? vehicleId;
    String? driverId;
    String? supplierId;
    String? customerId;
    String? locationId = LocationScopeService.currentForCreate(widget.session);
    String freightMode = 'none';
    bool capacityOverride = false;
    var measurementData = MaterialMeasurementData(
      method: 'manual',
      unitCode: 'CFT',
      dimensionUnit: 'ft',
    );

    final source = TextEditingController();
    final destination = TextEditingController();
    final reference = TextEditingController();
    final freight = TextEditingController(text: '0');
    final overrideReason = TextEditingController();
    final notes = TextEditingController();
    final rateCtrl = TextEditingController();
    var costs = <Map<String, dynamic>>[];
    var delivery = <String, dynamic>{};
    final requestId = const Uuid().v4();
    var saving = false;

    void applyProductRate(String? pId, String dir) {
      if (pId == null) return;
      final p = products.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['variant_id']?.toString() == pId,
        orElse: () => null,
      );
      if (p != null) {
        final rawRate = dir == 'inbound' ? p['cost_price'] : p['selling_price'];
        final numRate = rawRate is num ? rawRate.toDouble() : double.tryParse(rawRate?.toString() ?? '') ?? 0.0;
        // Suggested price from Daily Rate Board; manual rates take priority
        if (numRate > 0 && rateCtrl.text.isEmpty) {
          rateCtrl.text = numRate.toStringAsFixed(2);
        }
      }
    }

    try {
      final created = await showThqDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            final scheme = Theme.of(context).colorScheme;

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 820,
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // DIALOG HEADER
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            direction == 'inbound'
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            color: direction == 'inbound'
                                ? const Color(0xFF00875A)
                                : scheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              direction == 'inbound'
                                  ? 'New Inward / Purchase Load Entry'
                                  : 'New Outward / Sales Dispatch Load',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
                          ),
                        ],
                      ),
                    ),

                    // DIALOG SCROLLABLE BODY (GROUPS 1, 2, 3)
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // GROUP 1: MATERIAL & MEASUREMENT
                            _FormSectionTitle(
                              number: '1',
                              title: 'Material & Measurement',
                              subtitle: 'Select material, store, and enter physical or weighment dimensions',
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: direction,
                                    decoration: const InputDecoration(
                                      labelText: 'Direction',
                                      isDense: true,
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
                                    onChanged: (value) => setLocalState(() {
                                      direction = value ?? 'inbound';
                                      applyProductRate(productId, direction);
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: locationId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Operating Yard / Store',
                                      isDense: true,
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
                                labelText: 'Material / Quality Grade *',
                                isDense: true,
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
                              onChanged: (value) => setLocalState(() {
                                productId = value;
                                applyProductRate(productId, direction);
                              }),
                            ),
                            const SizedBox(height: 10),
                            MaterialMeasurementForm(
                              initialData: measurementData,
                              onChanged: (data) {
                                measurementData = data;
                                setLocalState(() {});
                              },
                            ),

                            const SizedBox(height: 16),

                            // GROUP 2: PARTY & TRANSPORT
                            _FormSectionTitle(
                              number: '2',
                              title: 'Party & Transport Logistics',
                              subtitle: 'Assign truck, driver, quarry source or customer destination',
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: SearchableTruckSelector(
                                    vehicles: vehicles,
                                    initialVehicleId: vehicleId,
                                    session: widget.session,
                                    locationId: locationId,
                                    onVehicleCreated: (veh) {
                                      setLocalState(() {
                                        vehicles.insert(0, veh);
                                      });
                                    },
                                    onVehicleSelected: (veh) {
                                      setLocalState(() {
                                        vehicleId = veh?['vehicle_id']?.toString() ?? veh?['id']?.toString();
                                        if (veh != null &&
                                            veh['default_driver_id'] != null &&
                                            driverId == null) {
                                          driverId = veh['default_driver_id']?.toString();
                                        }
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SearchableDriverSelector(
                                    session: widget.session,
                                    initialDriverId: driverId,
                                    onDriverSelected: (drv) {
                                      setLocalState(() {
                                        driverId = drv?['driver_id']?.toString() ?? drv?['id']?.toString();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (direction == 'inbound' || direction == 'direct_delivery')
                              DropdownButtonFormField<String>(
                                initialValue: supplierId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Supplier / Quarry Company *',
                                  isDense: true,
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
                            if (direction == 'outbound' || direction == 'direct_delivery') ...[
                              if (direction == 'direct_delivery') const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: customerId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Customer *',
                                  isDense: true,
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
                                      labelText: 'Source / Quarry Location',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: destination,
                                    decoration: const InputDecoration(
                                      labelText: 'Destination / Customer Site',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: reference,
                              decoration: const InputDecoration(
                                labelText: 'Quarry Slip / Source Invoice Reference',
                                isDense: true,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // GROUP 3: RATES, EXPENSES & OVERRIDES
                            _FormSectionTitle(
                              number: '3',
                              title: 'Rates, Freight & Overrides',
                              subtitle: 'Per-load pricing, expenses, freight allowances, and truck capacity overrides',
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: rateCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: direction == 'inbound'
                                          ? 'Material Buy Rate / ${measurementData.unitCode} (Optional)'
                                          : 'Material Sell Rate / ${measurementData.unitCode} (Optional)',
                                      helperText: 'Optional. Final rate is confirmed on the invoice.',
                                      prefixText: '₹ ',
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setLocalState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Estimated Load Value',
                                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          (_double(rateCtrl.text) ?? 0.0) > 0
                                              ? '₹ ${NumberFormat('#,##0.00').format((measurementData.approvedBillableQty > 0 ? measurementData.approvedBillableQty : measurementData.physicalQty) * (_double(rateCtrl.text) ?? 0.0))}'
                                              : 'Rate pending',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: (_double(rateCtrl.text) ?? 0.0) > 0 ? null : const Color(0xFFC06200),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: capacityOverride,
                                title: const Text('Allow Truck Capacity Override', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                subtitle: const Text(
                                  'Requires supervisor reason if load volume exceeds vehicle registration tare/capacity.',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onChanged: (value) =>
                                    setLocalState(() => capacityOverride = value),
                              ),
                            ),
                            if (capacityOverride) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: overrideReason,
                                decoration: const InputDecoration(
                                  labelText: 'Capacity Override Reason *',
                                  isDense: true,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            if (_context['can_manage_costs'] == true && locationId != null)
                              LoadCostEditor(
                                session: widget.session,
                                locationId: locationId!,
                                direction: direction,
                                driverId: driverId,
                                contextData: _context,
                                costs: costs,
                                onChanged: (v) => setLocalState(() => costs = v),
                              ),
                            const SizedBox(height: 10),
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
                              icon: const Icon(Icons.local_shipping_outlined, size: 16),
                              label: Text(
                                delivery.isEmpty
                                    ? 'Optional Delivery & Trip Details'
                                    : 'Edit Delivery & Trip Details (Configured)',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: notes,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Internal Notes',
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // STICKY BOTTOM SUMMARY BAR (GROUP 4: REVIEW & CONFIRM)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        border: Border(top: BorderSide(color: scheme.outlineVariant)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    'Physical Qty: ${MaterialMeasurementEngine.formatQuantity(measurementData.physicalQty, measurementData.unitCode)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00875A).withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    'Billable Qty: ${MaterialMeasurementEngine.formatQuantity(measurementData.approvedBillableQty, measurementData.unitCode)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF00875A),
                                    ),
                                  ),
                                ),
                                if (measurementData.calculatedCft > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      'Calc CFT: ${MaterialMeasurementEngine.formatCft(measurementData.calculatedCft)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    (_double(rateCtrl.text) ?? 0.0) > 0
                                        ? 'Est: ₹ ${NumberFormat('#,##0.00').format((measurementData.approvedBillableQty > 0 ? measurementData.approvedBillableQty : measurementData.physicalQty) * (_double(rateCtrl.text) ?? 0.0))}'
                                        : 'Est: Rate pending',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: (_double(rateCtrl.text) ?? 0.0) > 0 ? null : const Color(0xFFC06200),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: Icon(
                              direction == 'inbound' ? Icons.south_west_rounded : Icons.north_east_rounded,
                              size: 15,
                            ),
                            label: Text(saving ? 'Saving…' : 'Create Draft Load'),
                            onPressed: saving
                                ? null
                                : () async {
                                    if (locationId == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please select an explicit store. Transactions cannot be posted to Merged / All Stores scope.',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      return;
                                    }
                                    if (productId == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Select a material.'),
                                        ),
                                      );
                                      return;
                                    }
                                    final quantity = measurementData.physicalQty;
                                    if (quantity <= 0) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Enter a positive quantity.'),
                                        ),
                                      );
                                      return;
                                    }

                                    // Vehicle Capacity Validation
                                    if (vehicleId != null) {
                                      final veh = vehicles.cast<Map<String, dynamic>?>().firstWhere(
                                        (v) => v?['vehicle_id']?.toString() == vehicleId || v?['id']?.toString() == vehicleId,
                                        orElse: () => null,
                                      );
                                      final nomCap = veh?['nominal_capacity_cft'] is num
                                          ? (veh!['nominal_capacity_cft'] as num).toDouble()
                                          : double.tryParse(veh?['nominal_capacity_cft']?.toString() ?? '');
                                      if (nomCap != null && nomCap > 0) {
                                        final qtyCft = measurementData.calculatedCft > 0
                                            ? measurementData.calculatedCft
                                            : (measurementData.unitCode == 'CFT' ? measurementData.physicalQty : 0.0);
                                        final capError = MaterialMeasurementEngine.validateTruckCapacity(
                                          loadQtyCft: qtyCft,
                                          nominalCapacityCft: nomCap,
                                          allowOverride: capacityOverride,
                                          overrideReason: overrideReason.text,
                                        );
                                        if (capError != null) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(capError),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                          return;
                                        }
                                      }
                                    }

                                    setLocalState(() => saving = true);
                                    try {
                                        final enteredRate = _double(rateCtrl.text) ?? 0.0;
                                        final effectiveDelivery = Map<String, dynamic>.from(delivery);
                                        if (enteredRate > 0) {
                                          final effectiveQty = measurementData.approvedBillableQty > 0
                                              ? measurementData.approvedBillableQty
                                              : measurementData.physicalQty;
                                          if (direction == 'inbound') {
                                            effectiveDelivery['purchasing_price'] = enteredRate;
                                            effectiveDelivery['purchasing_total'] = enteredRate * effectiveQty;
                                          } else {
                                            effectiveDelivery['selling_price'] = enteredRate;
                                            effectiveDelivery['selling_total'] = enteredRate * effectiveQty;
                                          }
                                        }

                                        await _service.createLoad(
                                          tenantId: widget.session.business.id,
                                          direction: direction,
                                          locationId: locationId,
                                          variantId: productId!,
                                          quantity: quantity,
                                          unitCode: measurementData.unitCode,
                                          measurementMethod: measurementData.method,
                                          bodyLengthFt: measurementData.length,
                                          bodyWidthFt: measurementData.width,
                                          bodyHeightFt: measurementData.height,
                                          rawDimensions: measurementData.toRawDimensionsMap(),
                                          dimensionUnit: measurementData.dimensionUnit,
                                          calculatedCft: measurementData.calculatedCft,
                                          heapAdjustmentCft: measurementData.heapAdjustmentCft,
                                          approvedBillableQty: measurementData.approvedBillableQty,
                                          approvedBy: widget.session.userId.isNotEmpty ? widget.session.userId : null,
                                          measurementNotes: measurementData.varianceReason,
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
                                          delivery: effectiveDelivery,
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
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      if (created == true) await _reload();
    } finally {
      source.dispose();
      destination.dispose();
      reference.dispose();
      freight.dispose();
      overrideReason.dispose();
      notes.dispose();
      rateCtrl.dispose();
    }
  }

  // ==========================================
  // HELPER PERMISSION CHECKS & LABELS
  // ==========================================
  String? _id(dynamic v) {
    if (v == null) return null;
    final text = v.toString().trim();
    return text.isEmpty ? null : text;
  }

  String _simpleStatus(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    if (status == 'completed') return 'confirmed';
    if (status == 'cancelled') return 'cancelled';
    return 'draft';
  }

  bool _hasProtectedLinks(Map<String, dynamic> row) {
    return _id(row['purchase_id']) != null ||
        _id(row['sale_id']) != null ||
        _id(row['trip_id']) != null ||
        row['has_posted_costs'] == true;
  }

  bool _canConfirm(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    return _canManage &&
        !_busyLoads.contains(_id(row['load_id'])) &&
        status != 'completed' &&
        status != 'cancelled';
  }

  bool _canEdit(Map<String, dynamic> row) =>
      _canManage &&
      !_busyLoads.contains(_id(row['load_id'])) &&
      row['status'] != 'cancelled' &&
      !_isBilled(row) &&
      _id(row['purchase_id']) == null &&
      _id(row['sale_id']) == null;

  bool _canReopen(Map<String, dynamic> row) =>
      _canManage &&
      !_busyLoads.contains(_id(row['load_id'])) &&
      row['status'] == 'completed' &&
      !_isBilled(row) &&
      _id(row['purchase_id']) == null &&
      _id(row['sale_id']) == null;

  bool _canDelete(Map<String, dynamic> row) =>
      _canManage &&
      !_busyLoads.contains(_id(row['load_id'])) &&
      !['completed', 'cancelled'].contains(row['status']?.toString()) &&
      !_hasProtectedLinks(row);

  bool _canOpenBilling(Map<String, dynamic> row) {
    if (row['status'] == 'cancelled' ||
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

  Future<void> _reopenLoad(Map<String, dynamic> row) async {
    final loadId = _id(row['load_id']);
    if (loadId == null || !_canReopen(row)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen Confirmed Load?'),
        content: Text(
          'Reopening load ${row['load_number'] ?? ''} will revert its status back to draft, reset unpaid draft accruals, and preserve an audit trail. You can then edit or re-confirm it before final billing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reopen Load'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyLoads.add(loadId));
    try {
      await _service.reopenLoad(
        tenantId: widget.session.business.id,
        loadId: loadId,
      );
      _message('Load reopened for editing and reset to draft.');
      await _reload();
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busyLoads.remove(loadId));
    }
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
      if (load['status'] != 'completed' && load['status'] != 'draft') {
        throw StateError('Only draft or confirmed loads can be billed.');
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
        final del = load['delivery'] is Map ? load['delivery'] as Map : null;
        final delRate = del != null
            ? (outbound ? del['selling_price'] : del['purchasing_price'])
            : null;
        final unitPrice = delRate is num
            ? delRate.toDouble()
            : double.tryParse(delRate?.toString() ?? '');
        final loadUpdatedAt = DateTime.tryParse('${load['updated_at'] ?? load['created_at']}');

        final completed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => outbound
                ? NewSaleScreen(
                    session: widget.session,
                    locationId: locationId,
                    materialLoadId: loadId,
                    loadUpdatedAt: loadUpdatedAt,
                    initialCustomerId: _id(load['customer_id']),
                    initialVariantId: _id(load['variant_id']),
                    initialQuantity: quantity,
                    initialUnitCode: _id(load['unit_code']),
                    initialUnitPrice: unitPrice,
                    initialNotes: notes,
                  )
                : NewPurchaseScreen(
                    session: widget.session,
                    locationId: locationId,
                    materialLoadId: loadId,
                    loadUpdatedAt: loadUpdatedAt,
                    initialSupplierId: _id(load['supplier_id']),
                    initialVariantId: _id(load['variant_id']),
                    initialQuantity: quantity,
                    initialUnitCode: _id(load['unit_code']),
                    initialUnitPrice: unitPrice,
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
      confirmed = true;
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

  // ==========================================
  // EDIT LOAD (4-GROUP COMPACT DIALOG)
  // ==========================================
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
      final suppliers = _list('suppliers');
      final customers = _list('customers');
      final locations = _list('locations');

      String direction = detail['direction']?.toString() == 'outbound'
          ? 'outbound'
          : 'inbound';

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
      String? driverId = _id(detail['driver_id']);
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

      var measurementData = MaterialMeasurementData(
        method: detail['measurement_method']?.toString() ?? 'manual',
        unitCode: detail['unit_code']?.toString() ?? 'CFT',
        dimensionUnit: detail['dimension_unit']?.toString() ?? 'ft',
        length: _double(detail['body_length_ft']?.toString() ?? ''),
        width: _double(detail['body_width_ft']?.toString() ?? ''),
        height: _double(detail['body_height_ft']?.toString() ?? ''),
        calculatedCft: _double(detail['calculated_cft']?.toString() ?? '') ?? 0.0,
        heapAdjustmentCft: _double(detail['heap_adjustment_cft']?.toString() ?? '') ?? 0.0,
        physicalQty: _double(detail['quantity']?.toString() ?? '') ?? 0.0,
        approvedBillableQty: _double(detail['approved_billable_qty']?.toString() ?? '') ??
            (_double(detail['quantity']?.toString() ?? '') ?? 0.0),
        varianceReason: detail['measurement_notes']?.toString(),
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
      final initialDelRate = direction == 'outbound'
          ? delivery['selling_price']
          : delivery['purchasing_price'];
      final rateCtrl = TextEditingController(
        text: initialDelRate != null && initialDelRate.toString().isNotEmpty
            ? initialDelRate.toString()
            : '',
      );
      DateTime loadDate = DateTime.tryParse('${detail['load_date']}') ?? DateTime.now();
      var saving = false;

      try {
        final saved = await showThqDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setLocalState) {
              final scheme = Theme.of(context).colorScheme;

              return Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 820,
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // HEADER
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.edit_note_rounded, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Edit ${detail['load_number']} (${direction.toUpperCase()})',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
                            ),
                          ],
                        ),
                      ),

                      // SCROLLABLE BODY
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FormSectionTitle(
                                number: '1',
                                title: 'Material & Measurement',
                                subtitle: 'Update material variant, location, and dimensions',
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: direction,
                                      decoration: const InputDecoration(
                                        labelText: 'Direction',
                                        isDense: true,
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
                                        labelText: 'Operating Yard / Store',
                                        isDense: true,
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
                                  labelText: 'Material / Grade *',
                                  isDense: true,
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
                              MaterialMeasurementForm(
                                initialData: measurementData,
                                onChanged: (data) {
                                  measurementData = data;
                                  setLocalState(() {});
                                },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final picked = await showDatePicker(
                                                context: context,
                                                initialDate: loadDate,
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2100),
                                              );
                                              if (picked != null) {
                                                setLocalState(() => loadDate = picked);
                                              }
                                            },
                                      icon: const Icon(Icons.calendar_today, size: 16),
                                      label: Text('Loading Date: ${StaffLoadService.date(loadDate)}'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: rateCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: direction == 'outbound'
                                            ? 'Selling Rate / Unit (₹)'
                                            : 'Purchase Rate / Unit (₹)',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),
                              _FormSectionTitle(
                                number: '2',
                                title: 'Party & Transport Logistics',
                                subtitle: 'Vehicle, driver, quarry and destination site',
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: SearchableTruckSelector(
                                      vehicles: vehicles,
                                      initialVehicleId: vehicleId,
                                      session: widget.session,
                                      locationId: locationId,
                                      onVehicleCreated: (veh) {
                                        setLocalState(() {
                                          vehicles.insert(0, veh);
                                        });
                                      },
                                      onVehicleSelected: (veh) {
                                        setLocalState(() {
                                          vehicleId = veh?['vehicle_id']?.toString() ?? veh?['id']?.toString();
                                          if (veh != null &&
                                              veh['default_driver_id'] != null &&
                                              driverId == null) {
                                            driverId = veh['default_driver_id']?.toString();
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SearchableDriverSelector(
                                      session: widget.session,
                                      initialDriverId: driverId,
                                      onDriverSelected: (drv) {
                                        setLocalState(() {
                                          driverId = drv?['driver_id']?.toString() ?? drv?['id']?.toString();
                                        });
                                      },
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
                                    labelText: 'Supplier / Quarry Company *',
                                    isDense: true,
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
                                ),
                              if (direction == 'outbound')
                                DropdownButtonFormField<String>(
                                  initialValue: customerId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Customer *',
                                    isDense: true,
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
                                        labelText: 'Source / Quarry Location',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: destination,
                                      decoration: const InputDecoration(
                                        labelText: 'Destination / Site',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: reference,
                                decoration: const InputDecoration(
                                  labelText: 'Quarry Slip / Source Invoice Reference',
                                  isDense: true,
                                ),
                              ),

                              const SizedBox(height: 16),
                              _FormSectionTitle(
                                number: '3',
                                title: 'Rates, Freight & Overrides',
                                subtitle: 'Per-load expenses and operational parameters',
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  value: capacityOverride,
                                  title: const Text('Allow Truck Capacity Override', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  subtitle: const Text(
                                    'Requires supervisor reason if load volume exceeds vehicle registration tare/capacity.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  onChanged: (value) =>
                                      setLocalState(() => capacityOverride = value),
                                ),
                              ),
                              if (capacityOverride) ...[
                                const SizedBox(height: 8),
                                TextField(
                                  controller: overrideReason,
                                  decoration: const InputDecoration(
                                    labelText: 'Capacity Override Reason *',
                                    isDense: true,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              if (_context['can_manage_costs'] == true && locationId != null)
                                LoadCostEditor(
                                  session: widget.session,
                                  locationId: locationId!,
                                  direction: direction,
                                  driverId: driverId,
                                  contextData: _context,
                                  costs: costs,
                                  onChanged: (v) => setLocalState(() => costs = v),
                                ),
                              const SizedBox(height: 10),
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
                                icon: const Icon(Icons.local_shipping_outlined, size: 16),
                                label: Text(
                                  delivery.isEmpty
                                      ? 'Optional Delivery & Trip Details'
                                      : 'Edit Delivery & Trip Details (Configured)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: notes,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Internal Notes',
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // STICKY FOOTER
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                          border: Border(top: BorderSide(color: scheme.outlineVariant)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      'Physical Qty: ${MaterialMeasurementEngine.formatQuantity(measurementData.physicalQty, measurementData.unitCode)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00875A).withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      'Billable Qty: ${MaterialMeasurementEngine.formatQuantity(measurementData.approvedBillableQty, measurementData.unitCode)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF00875A),
                                      ),
                                    ),
                                  ),
                                  if (measurementData.calculatedCft > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        'Calc CFT: ${MaterialMeasurementEngine.formatCft(measurementData.calculatedCft)}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: saving ? null : () => Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      if (productId == null) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Select a material.')),
                                        );
                                        return;
                                      }
                                      final editedQuantity = measurementData.physicalQty;
                                      if (editedQuantity <= 0) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Enter a positive quantity.')),
                                        );
                                        return;
                                      }

                                      final enteredRate = _double(rateCtrl.text) ?? 0.0;
                                      if (enteredRate > 0) {
                                        if (direction == 'outbound') {
                                          delivery['selling_price'] = enteredRate;
                                          delivery['selling_total'] = enteredRate * measurementData.approvedBillableQty;
                                        } else {
                                          delivery['purchasing_price'] = enteredRate;
                                          delivery['purchasing_total'] = enteredRate * measurementData.approvedBillableQty;
                                        }
                                      }

                                      setLocalState(() => saving = true);
                                      try {
                                        await _service.editLoad(
                                          tenantId: widget.session.business.id,
                                          loadId: row['load_id'].toString(),
                                          direction: direction,
                                          locationId: locationId,
                                          variantId: productId!,
                                          loadDate: loadDate,
                                          quantity: editedQuantity,
                                          unitCode: measurementData.unitCode,
                                          measurementMethod: measurementData.method,
                                          bodyLengthFt: measurementData.length,
                                          bodyWidthFt: measurementData.width,
                                          bodyHeightFt: measurementData.height,
                                          rawDimensions: measurementData.toRawDimensionsMap(),
                                          dimensionUnit: measurementData.dimensionUnit,
                                          calculatedCft: measurementData.calculatedCft,
                                          heapAdjustmentCft: measurementData.heapAdjustmentCft,
                                          approvedBillableQty: measurementData.approvedBillableQty,
                                          approvedBy: widget.session.userId.isNotEmpty ? widget.session.userId : null,
                                          measurementNotes: measurementData.varianceReason,
                                          vehicleId: vehicleId,
                                          driverId: driverId,
                                          supplierId: direction == 'inbound' ? supplierId : null,
                                          customerId: direction == 'outbound' ? customerId : null,
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
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );

        if (saved == true) {
          await _reload();
        }
      } finally {
        source.dispose();
        destination.dispose();
        reference.dispose();
        freight.dispose();
        overrideReason.dispose();
        notes.dispose();
        rateCtrl.dispose();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  // ==========================================
  // ACTION BUTTONS FOR EACH LOAD
  // ==========================================
  Widget _loadActions(Map<String, dynamic> row, {bool isCompact = false}) {
    final scheme = Theme.of(context).colorScheme;
    final derived = _derivedWorkflowStatus(row);
    final canConfirm = _canConfirm(row);
    final canReopen = _canReopen(row);
    final canEdit = _canEdit(row);
    final canDelete = _canDelete(row);
    final canBill = _canOpenBilling(row);

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        // Primary action based on workflow state
        if (derived == 'draft' && canConfirm)
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () => _confirmLoad(row),
            child: const Text('Confirm Load', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        if (derived == 'rate_pending' && canEdit)
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: const Color(0xFFFF8B00).withValues(alpha: 0.15),
              foregroundColor: const Color(0xFFC06200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () => _editLoad(row),
            child: const Text('Set Rate / Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          )
        else if (canBill)
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () => _openBilling(row),
            child: Text(
              _billingLabel(row),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        if (canReopen)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () => _reopenLoad(row),
            child: const Text('Reopen', style: TextStyle(fontSize: 11)),
          ),
        if (_hasTransport)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () => _openTransport(row),
            child: const Text('Trip', style: TextStyle(fontSize: 11)),
          ),
        if (canEdit && derived != 'rate_pending')
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Edit load',
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: () => _editLoad(row),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          tooltip: 'Open detail & evidence',
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          onPressed: () => _showLoad(row),
        ),
        if (canDelete)
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Cancel load',
            icon: Icon(Icons.delete_outline, size: 16, color: scheme.error),
            onPressed: () => _deleteLoad(row),
          ),
      ],
    );
  }

  // ==========================================
  // STATUS & DATE BADGE HELPERS
  // ==========================================
  String _formatLoadDate(Map<String, dynamic> row) {
    final rawDate = row['load_date'] ?? row['created_at'];
    if (rawDate == null) return '';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(rawDate.toString()));
    } catch (_) {
      return rawDate.toString();
    }
  }

  Widget _buildLoadAmount(Map<String, dynamic> row, ColorScheme scheme, {bool isLarge = false}) {
    final isBilled = _isBilled(row);
    final isRatePending = _isRatePending(row);
    final invGrandTotal = row['invoice_grand_total'] is num
        ? (row['invoice_grand_total'] as num).toDouble()
        : double.tryParse(row['invoice_grand_total']?.toString() ?? '');
    final invAmount = row['invoice_amount'] is num
        ? (row['invoice_amount'] as num).toDouble()
        : double.tryParse(row['invoice_amount']?.toString() ?? '');
    final authoritativeTotal = invGrandTotal ?? invAmount;

    if (isBilled && authoritativeTotal != null && authoritativeTotal > 0) {
      return Text(
        '₹ ${NumberFormat('#,##0.00').format(authoritativeTotal)}',
        style: TextStyle(
          fontSize: isLarge ? 13 : 11,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF00875A),
        ),
      );
    }

    if (isRatePending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: const Color(0xFFFF8B00).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFF8B00).withValues(alpha: 0.4), width: 0.8),
        ),
        child: const Text(
          'Amount Pending',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFFC06200),
          ),
        ),
      );
    }

    final qty = row['approved_billable_qty'] is num
        ? (row['approved_billable_qty'] as num).toDouble()
        : (row['quantity'] is num ? (row['quantity'] as num).toDouble() : double.tryParse(row['quantity']?.toString() ?? '') ?? 0.0);
    final invRate = row['invoice_rate'] is num
        ? (row['invoice_rate'] as num).toDouble()
        : double.tryParse(row['invoice_rate']?.toString() ?? '');

    double? effectiveRate = invRate;
    if (effectiveRate == null || effectiveRate <= 0) {
      final isInbound = row['direction'] == 'inbound';
      final del = row['delivery'] is Map ? row['delivery'] as Map : null;
      final delRate = del != null ? (isInbound ? del['purchasing_price'] : del['selling_price']) : null;
      effectiveRate = delRate is num ? delRate.toDouble() : double.tryParse(delRate?.toString() ?? '');
    }

    if (effectiveRate != null && effectiveRate > 0 && qty > 0) {
      final estimated = qty * effectiveRate;
      return Text(
        '₹ ${NumberFormat('#,##0.00').format(estimated)} (Est)',
        style: TextStyle(
          fontSize: isLarge ? 12 : 10.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildWorkflowBadge(Map<String, dynamic> row, ColorScheme scheme, {bool isTable = false}) {
    final derived = _derivedWorkflowStatus(row);
    final invNum = row['invoice_number']?.toString();
    final isInbound = row['direction'] == 'inbound';

    switch (derived) {
      case 'billed':
        final label = invNum != null && invNum.isNotEmpty
            ? '${isInbound ? 'PURCHASE' : 'SALE'}: $invNum'
            : (isInbound ? 'PURCHASE POSTED' : 'SALE POSTED');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFF00875A).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF00875A).withValues(alpha: 0.3), width: 0.8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF00875A),
            ),
          ),
        );

      case 'rate_pending':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFFFF8B00).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFF8B00).withValues(alpha: 0.5), width: 0.8),
          ),
          child: const Text(
            'RATE PENDING',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC06200),
            ),
          ),
        );

      case 'unbilled':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFF0052CC).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF0052CC).withValues(alpha: 0.4), width: 0.8),
          ),
          child: const Text(
            'UNBILLED',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0052CC),
            ),
          ),
        );

      case 'draft':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'DRAFT',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        );

      case 'cancelled':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: scheme.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'CANCELLED',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: scheme.error,
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWorkflowFilterChip(String value, String label, int count, ColorScheme scheme) {
    final isSelected = (_status ?? 'needs_action') == value;
    final isNeedsAction = value == 'needs_action';
    final isRatePending = value == 'rate_pending';
    final isBilled = value == 'billed';

    Color activeColor = scheme.primary;
    if (isNeedsAction && count > 0) {
      activeColor = const Color(0xFF0052CC);
    } else if (isRatePending && count > 0) {
      activeColor = const Color(0xFFC06200);
    } else if (isBilled) {
      activeColor = const Color(0xFF00875A);
    }

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        selected: isSelected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : (count > 0 ? activeColor.withValues(alpha: 0.12) : scheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? scheme.onPrimary : (count > 0 ? activeColor : scheme.outline),
                ),
              ),
            ),
          ],
        ),
        selectedColor: activeColor,
        showCheckmark: false,
        onSelected: (_) {
          setState(() => _status = value);
          _reload();
        },
      ),
    );
  }

  // ==========================================
  // TABLE VIEW BUILDER
  // ==========================================
  Widget _buildLoadsTable(BuildContext context, ColorScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(1.1), // Load Number & Date
            1: FlexColumnWidth(1.6), // Material & Party
            2: FlexColumnWidth(1.1), // Quantity
            3: FlexColumnWidth(1.3), // Total Amount & Rate
            4: FlexColumnWidth(1.6), // Route, Truck & Driver
            5: FlexColumnWidth(1.3), // Status & Workflow
            6: FlexColumnWidth(1.8), // Actions
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text('Load # & Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Material & Party', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Quantity', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Amount / Rate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Truck & Route', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text('Workflow State', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Actions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            ..._rows.map((row) {
              final isInbound = row['direction'] == 'inbound';
              final simpleStat = _simpleStatus(row);
              final statusColor = simpleStat == 'confirmed'
                  ? const Color(0xFF00875A)
                  : simpleStat == 'cancelled'
                      ? scheme.error
                      : scheme.primary;
              final dateText = _formatLoadDate(row);

              // Rate text
              final invRate = row['invoice_rate'] is num
                  ? (row['invoice_rate'] as num).toDouble()
                  : double.tryParse(row['invoice_rate']?.toString() ?? '');

              String? matRateText;
              bool isRatePending = false;
              if (invRate != null && invRate > 0) {
                matRateText = '₹ ${NumberFormat('#,##0.00').format(invRate)} / ${row['unit_code'] ?? 'CFT'}';
              } else {
                final del = row['delivery'] is Map ? row['delivery'] as Map : null;
                final delRate = del != null ? (isInbound ? del['purchasing_price'] : del['selling_price']) : null;
                final numDelRate = delRate is num ? delRate.toDouble() : double.tryParse(delRate?.toString() ?? '');
                if (numDelRate != null && numDelRate > 0) {
                  matRateText = '₹ ${NumberFormat('#,##0.00').format(numDelRate)} (Est)';
                } else {
                  isRatePending = true;
                  matRateText = 'Rate pending';
                }
              }

              final partyName = isInbound
                  ? (row['supplier_name'] ?? row['source_name'] ?? 'Quarry / Supplier')
                  : (row['customer_name'] ?? row['destination_name'] ?? 'Customer / Site');

              return TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))),
                ),
                children: [
                  // 0. Load # & Date
                  InkWell(
                    onTap: () => _showLoad(row),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isInbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                                size: 13,
                                color: isInbound ? const Color(0xFF00875A) : const Color(0xFF635BFF),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${row['load_number'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (dateText.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 17, top: 1),
                              child: Text(
                                dateText,
                                style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 1. Material & Party (Primary)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['product_name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          partyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // 2. Quantity
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          MaterialMeasurementEngine.formatQuantity(row['quantity'], row['unit_code'] ?? 'CFT'),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        if (row['approved_billable_qty'] != null &&
                            row['approved_billable_qty'] != row['quantity'])
                          Text(
                            'Billable: ${MaterialMeasurementEngine.formatQuantity(row['approved_billable_qty'], row['unit_code'] ?? 'CFT')}',
                            style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  // 3. Total Amount & Rate (Primary/Secondary)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLoadAmount(row, scheme),
                        Text(
                          matRateText,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: isRatePending ? FontWeight.w600 : FontWeight.normal,
                            color: isRatePending ? const Color(0xFFC06200) : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 4. Truck & Route (Secondary)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['vehicle_registration'] ?? 'No truck'}${row['driver_name'] != null ? ' • ${row['driver_name']}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${row['source_name'] ?? 'Quarry'} → ${row['destination_name'] ?? 'Site'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // 5. Workflow State (Badge)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            simpleStat.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        _buildWorkflowBadge(row, scheme, isTable: true),
                      ],
                    ),
                  ),
                  // 6. Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: _loadActions(row, isCompact: true),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CARDS VIEW BUILDER (RESPONSIVE GRID)
  // ==========================================
  Widget _buildLoadsCards(BuildContext context, ColorScheme scheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 920;
        final count = _rows.length;

        if (isWide) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 6,
              mainAxisExtent: 84,
            ),
            itemCount: count,
            itemBuilder: (context, index) => _buildLoadCard(_rows[index], scheme),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(height: 5),
          itemBuilder: (context, index) => SizedBox(
            height: 84,
            child: _buildLoadCard(_rows[index], scheme),
          ),
        );
      },
    );
  }

  Widget _buildLoadCard(Map<String, dynamic> row, ColorScheme scheme) {
    final calcCft = row['calculated_cft'];
    final billableQty = row['approved_billable_qty'];
    final slipRef = row['source_reference'];
    final isInbound = row['direction'] == 'inbound';
    final dateText = _formatLoadDate(row);

    final invRate = row['invoice_rate'] is num
        ? (row['invoice_rate'] as num).toDouble()
        : double.tryParse(row['invoice_rate']?.toString() ?? '');

    String matRateText;
    if (invRate != null && invRate > 0) {
      matRateText = '₹ ${NumberFormat('#,##0.00').format(invRate)} / ${row['unit_code'] ?? 'CFT'}';
    } else {
      final del = row['delivery'] is Map ? row['delivery'] as Map : null;
      final delRate = del != null ? (isInbound ? del['purchasing_price'] : del['selling_price']) : null;
      final numDelRate = delRate is num ? delRate.toDouble() : double.tryParse(delRate?.toString() ?? '');
      if (numDelRate != null && numDelRate > 0) {
        matRateText = '₹ ${NumberFormat('#,##0.00').format(numDelRate)} (Est)';
      } else {
        matRateText = 'Rate pending';
      }
    }

    final partyName = isInbound
        ? (row['supplier_name'] ?? row['source_name'] ?? 'Quarry / Supplier')
        : (row['customer_name'] ?? row['destination_name'] ?? 'Customer / Site');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ROW 1 (PRIMARY): Direction, Material, Party, Total Amount, Workflow Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: isInbound
                      ? const Color(0xFF00875A).withValues(alpha: 0.12)
                      : const Color(0xFF635BFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(
                  isInbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                  size: 11,
                  color: isInbound ? const Color(0xFF00875A) : const Color(0xFF635BFF),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${row['product_name'] ?? ''} • $partyName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              _buildLoadAmount(row, scheme),
              const SizedBox(width: 6),
              _buildWorkflowBadge(row, scheme),
            ],
          ),
          const SizedBox(height: 2),
          // ROW 2 (SECONDARY): Qty + Unit, Rate, Truck, Driver, Route, Date
          Row(
            children: [
              Expanded(
                child: Text(
                  '${MaterialMeasurementEngine.formatQuantity(row['quantity'], row['unit_code'] ?? 'CFT')}'
                  '${calcCft != null && calcCft > 0 ? ' (${MaterialMeasurementEngine.formatCft(calcCft)})' : ''}'
                  '${billableQty != null && billableQty != row['quantity'] ? ' • Billable: ${MaterialMeasurementEngine.formatQuantity(billableQty, row['unit_code'] ?? 'CFT')}' : ''}'
                  '  •  $matRateText'
                  '  |  ${row['vehicle_registration'] ?? 'No truck'}'
                  '${row['driver_name'] != null ? ' • ${row['driver_name']}' : ''}'
                  '  •  ${row['source_name'] ?? 'Quarry'} → ${row['destination_name'] ?? 'Site'}'
                  '${dateText.isNotEmpty ? '  •  $dateText' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          // ROW 3 (TERTIARY & ACTIONS): Load Number (click to detail), Slip Ref, Actions
          Row(
            children: [
              InkWell(
                onTap: () => _showLoad(row),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#${row['load_number'] ?? ''}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    if (slipRef != null && slipRef.toString().isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        'Ref: $slipRef',
                        style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              _loadActions(row, isCompact: true),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MAIN SCAFFOLD BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46,
        title: const Text('Load Register', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: _isTableView ? 'Switch to Compact Cards View' : 'Switch to Data Table View',
            icon: Icon(_isTableView ? Icons.grid_view_rounded : Icons.table_rows_rounded),
            onPressed: () => setState(() => _isTableView = !_isTableView),
          ),
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
            tooltip: 'Refresh loads',
            onPressed: _loading ? null : () => _reload(all: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: !_canManage
          ? null
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_direction == null || _direction == 'inbound')
                  FloatingActionButton.extended(
                    heroTag: 'new_inward_btn',
                    elevation: 2,
                    onPressed: _loading
                        ? null
                        : () => _createLoad(initialDirection: 'inbound'),
                    icon: const Icon(Icons.south_west_rounded, size: 16),
                    label: const Text('Inward / Purchase Load', style: TextStyle(fontSize: 12)),
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                  ),
                if (_direction == null || _direction == 'outbound')
                  FloatingActionButton.extended(
                    heroTag: 'new_outward_btn',
                    elevation: 2,
                    onPressed: _loading
                        ? null
                        : () => _createLoad(initialDirection: 'outbound'),
                    icon: const Icon(Icons.north_east_rounded, size: 16),
                    label: const Text('Outward / Sales Load', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
      body: Column(
        children: [
          // 1. DIRECTION SEGMENTED SELECTOR
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: SizedBox(
              width: double.infinity,
              height: 32,
              child: SegmentedButton<String?>(
                segments: [
                  ButtonSegment<String?>(
                    value: null,
                    label: Text(
                      'All Directions (${_counts['all'] ?? _rows.length})',
                      style: const TextStyle(fontSize: 11),
                    ),
                    icon: const Icon(Icons.swap_vert_rounded, size: 14),
                  ),
                  ButtonSegment<String?>(
                    value: 'inbound',
                    label: Text(
                      'Purchase / Inward (${_counts['inbound'] ?? 0})',
                      style: const TextStyle(fontSize: 11),
                    ),
                    icon: const Icon(Icons.south_west_rounded, size: 14),
                  ),
                  ButtonSegment<String?>(
                    value: 'outbound',
                    label: Text(
                      'Sales / Outward (${_counts['outbound'] ?? 0})',
                      style: const TextStyle(fontSize: 11),
                    ),
                    icon: const Icon(Icons.north_east_rounded, size: 14),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (set) {
                  setState(() => _direction = set.first);
                  _reload();
                },
              ),
            ),
          ),

          // 2. DERIVED WORKFLOW FILTER CHIPS (OPERATIONAL QUEUE FIRST)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildWorkflowFilterChip('needs_action', 'Needs Action', _counts['needs_action'] ?? 0, scheme),
                  _buildWorkflowFilterChip('unbilled', 'Unbilled', _counts['unbilled'] ?? 0, scheme),
                  _buildWorkflowFilterChip('rate_pending', 'Rate Pending', _counts['rate_pending'] ?? 0, scheme),
                  _buildWorkflowFilterChip('billed', 'Billed', _counts['billed'] ?? 0, scheme),
                  _buildWorkflowFilterChip('draft', 'Draft', _counts['draft'] ?? 0, scheme),
                  _buildWorkflowFilterChip('cancelled', 'Cancelled', _counts['cancelled'] ?? 0, scheme),
                  _buildWorkflowFilterChip('all', 'All Loads', _counts['all'] ?? 0, scheme),
                ],
              ),
            ),
          ),

          // 3. SEARCH & STATUS DROPDOWN TOOLBAR
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _search,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        prefixIcon: Icon(Icons.search_rounded, size: 16),
                        hintText:
                            'Search load #, material, truck, driver, supplier or customer…',
                        hintStyle: TextStyle(fontSize: 11.5),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _reload(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 175,
                  height: 34,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _status,
                    isDense: true,
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurface),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      labelText: 'Status Queue',
                      labelStyle: TextStyle(fontSize: 11),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: 'needs_action',
                        child: Text('Needs Action (${_counts['needs_action'] ?? 0})'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'unbilled',
                        child: Text('Unbilled (${_counts['unbilled'] ?? 0})'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'rate_pending',
                        child: Text('Rate Pending (${_counts['rate_pending'] ?? 0})'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'billed',
                        child: Text('Billed (${_counts['billed'] ?? 0})'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'draft',
                        child: Text('Draft (${_counts['draft'] ?? 0})'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'cancelled',
                        child: Text('Cancelled (${_counts['cancelled'] ?? 0})'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'all',
                        child: Text('All Loads (${_counts['all'] ?? 0})'),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(fontSize: 11, color: scheme.onErrorContainer)),
            ),

          // 3. MAIN LOADS CONTENT
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 40,
                              color: scheme.outline,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _direction == 'inbound'
                                  ? 'No purchase/inward loads recorded yet.'
                                  : _direction == 'outbound'
                                      ? 'No sales/outward loads recorded yet.'
                                      : 'No load tickets found for selected filters.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: scheme.outline),
                            ),
                          ],
                        ),
                      )
                    : _isTableView
                        ? _buildLoadsTable(context, scheme)
                        : _buildLoadsCards(context, scheme),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// FORM SECTION TITLE HELPER
// ==========================================
class _FormSectionTitle extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _FormSectionTitle({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
