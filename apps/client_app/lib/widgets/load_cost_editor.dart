import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/client_session.dart';
import '../models/expense.dart';
import '../services/expense_service.dart';
import '../services/staff_load_service.dart';
import 'operational_form_dialog.dart';
import 'record_preview.dart';

class LoadCostEditor extends StatefulWidget {
  final ClientSession session;
  final String locationId;
  final String direction;
  final String? driverId;
  final Map<String, dynamic> contextData;
  final List<Map<String, dynamic>> costs;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool internalOnly;

  const LoadCostEditor({
    super.key,
    required this.session,
    required this.locationId,
    required this.direction,
    required this.contextData,
    required this.costs,
    required this.onChanged,
    this.driverId,
    this.internalOnly = false,
  });

  @override
  State<LoadCostEditor> createState() => _LoadCostEditorState();
}

class _LoadCostEditorState extends State<LoadCostEditor> {
  List<Map<String, dynamic>>? _services;
  List<ExpenseCategory>? _dynamicCategories;

  static const defaultKinds = {
    'diesel': 'Diesel',
    'driver_wage': 'Driver Wages',
    'vehicle_rent': 'Vehicle Rent',
    'freight': 'Freight',
    'loading': 'Loading Charges',
    'unloading': 'Unloading Charges',
    'repairs': 'Repairs & Maintenance',
    'toll': 'Toll & Transit',
    'other': 'Other Expense',
  };

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  void _loadCategories() {
    final raw = widget.contextData['expense_categories'];
    if (raw is List && raw.isNotEmpty) {
      _dynamicCategories = raw
          .whereType<Map>()
          .map((e) => ExpenseCategory.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      _dynamicCategories = defaultKinds.entries
          .map((e) => ExpenseCategory(
                id: e.key,
                name: e.value,
                active: true,
              ))
          .toList();
    }
  }

  List<Map<String, dynamic>> get _staff =>
      StaffLoadService.rows(widget.contextData['staff'])
          .where(
            (s) =>
                s['location_id'] == null ||
                s['location_id'] == widget.locationId,
          )
          .toList();

  List<Map<String, dynamic>> get _billing =>
      _services ??
      StaffLoadService.rows(widget.contextData['billing_services']);

  String _money(dynamic value) =>
      '${widget.session.currencyCode} ${StaffLoadService.number(value).toStringAsFixed(2)}';

  Future<void> _newService() async {
    final saved = await showOperationalForm(
      context,
      title: 'Create customer charge service',
      initial: {'new_id': const Uuid().v4(), 'gst_rate': 0},
      fields: [
        const OperationalField('name', 'Service name', required: true),
        const OperationalField('description', 'Description', lines: 2),
        if (widget.contextData['tax_mode'] == 'gst_registered') ...const [
          OperationalField(
            'hsn_sac',
            'Correct SAC for this service',
            required: true,
            help:
                'Use the classification applicable to the service being supplied.',
          ),
          OperationalField(
            'taxability',
            'Tax treatment',
            options: {
              'taxable': 'Taxable',
              'nil_rated': 'Nil rated',
              'exempt': 'Exempt',
              'non_gst': 'Outside GST',
            },
          ),
          OperationalField(
            'gst_rate',
            'GST rate (%)',
            number: true,
            required: true,
          ),
        ],
      ],
      onSave: (data) async {
        await StaffLoadService().load(
          tenantId: widget.session.business.id,
          locationId: widget.locationId,
          action: 'billing_service',
          data: data,
        );
      },
    );
    if (saved != true) return;
    final data = await StaffLoadService().load(
      tenantId: widget.session.business.id,
      locationId: widget.locationId,
      action: 'context',
    );
    if (mounted) {
      setState(
        () => _services = StaffLoadService.rows(data['billing_services']),
      );
    }
  }

  Future<void> _addNewExpenseType(StateSetter setDialogState, Function(ExpenseCategory) onCreated) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var saving = false;
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.category_outlined, size: 20),
              SizedBox(width: 8),
              Text('Add New Expense Type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Expense Type Name *',
                    hintText: 'e.g. Weighbridge Fee, Poclain Rent',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Brief note on when this expense is used',
                    isDense: true,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12),
                  ),
                ],
              ],
            ),
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
                        setModal(() => error = 'Enter an expense type name.');
                        return;
                      }
                      setModal(() {
                        saving = true;
                        error = null;
                      });

                      try {
                        final created = await ExpenseService().createCategory(
                          tenantId: widget.session.business.id,
                          name: name,
                          description: descCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        onCreated(created);
                      } catch (e) {
                        if (ctx.mounted) {
                          setModal(() {
                            saving = false;
                            error = e.toString().replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save Type'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit([int? index]) async {
    Map<String, dynamic>? driver;
    for (final s in _staff) {
      if (s['driver_id'] == widget.driverId && widget.driverId != null) {
        driver = s;
        break;
      }
    }
    final old = index == null ? null : widget.costs[index];
    final salary = driver?['wage_basis'] == 'monthly';

    // Initial values
    final initialId = old?['id'] ?? const Uuid().v4();
    var selectedCatId = old?['category_id']?.toString() ??
        (old?['cost_kind'] != null && old!['cost_kind'] != 'other' ? old['cost_kind'] : (driver != null ? 'driver_wage' : 'diesel'));
    var costKind = old?['cost_kind']?.toString() ?? (driver != null ? 'driver_wage' : 'diesel');
    var staffId = old?['staff_id']?.toString() ?? driver?['staff_id']?.toString() ?? '';
    var staffMode = old?['staff_mode']?.toString() ?? (salary ? 'salary_allocation' : 'extra_wage');
    var paymentMethod = old?['payment_method']?.toString() ?? 'cash';
    var billingVariantId = old?['billing_variant_id']?.toString() ?? '';

    // Calculation mode: units * rate
    final initialQty = StaffLoadService.number(old?['quantity'] ?? 1);
    final initialRate = salary ? 0.0 : StaffLoadService.number(old?['rate'] ?? driver?['base_rate'] ?? 0);
    final initialAmt = StaffLoadService.number(old?['amount'] ?? (initialQty * initialRate));
    final initialBill = StaffLoadService.number(old?['bill_amount'] ?? 0);
    final initialPay = StaffLoadService.number(old?['initial_payment'] ?? 0);

    var calcByTrips = initialQty > 1;
    var chargeCustomer = initialBill > 0;
    var paymentStatus = initialPay >= initialAmt && initialAmt > 0
        ? 'paid'
        : (initialPay > 0 ? 'partially_paid' : 'not_paid');

    final descCtrl = TextEditingController(text: old?['description']?.toString() ?? (driver != null ? 'Driver wage' : ''));
    final payeeCtrl = TextEditingController(text: old?['payee']?.toString() ?? driver?['name']?.toString() ?? '');
    final qtyCtrl = TextEditingController(text: initialQty > 0 ? (initialQty == initialQty.roundToDouble() ? initialQty.toInt().toString() : initialQty.toString()) : '1');
    final rateCtrl = TextEditingController(text: initialRate > 0 ? (initialRate == initialRate.roundToDouble() ? initialRate.toInt().toString() : initialRate.toString()) : (initialAmt > 0 ? initialAmt.toString() : ''));
    final billCtrl = TextEditingController(text: initialBill > 0 ? (initialBill == initialBill.roundToDouble() ? initialBill.toInt().toString() : initialBill.toString()) : '0');
    final payCtrl = TextEditingController(text: initialPay > 0 ? (initialPay == initialPay.roundToDouble() ? initialPay.toInt().toString() : initialPay.toString()) : '0');
    final payRefCtrl = TextEditingController(text: old?['payment_reference']?.toString() ?? '');
    final receiptRefCtrl = TextEditingController(text: old?['receipt_reference']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: old?['notes']?.toString() ?? '');

    var showMoreDetails = (old?['receipt_reference'] != null && old!['receipt_reference'].toString().isNotEmpty) ||
        (old?['notes'] != null && old!['notes'].toString().isNotEmpty);

    String? dialogError;

    final categories = [...?_dynamicCategories];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dlgContext) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final theme = Theme.of(ctx);
          final scheme = theme.colorScheme;

          // Compute current financial numbers
          final double currentQty = calcByTrips ? (double.tryParse(qtyCtrl.text.trim()) ?? 1.0) : 1.0;
          final double currentRate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
          final double totalCost = currentQty * currentRate;
          final double customerChargeAmt = double.tryParse(billCtrl.text.trim()) ?? 0.0;
          final double enteredPayment = double.tryParse(payCtrl.text.trim()) ?? 0.0;
          final double paymentMade = paymentStatus == 'paid'
              ? (enteredPayment > 0 ? enteredPayment : totalCost)
              : enteredPayment;
          final double remainingPay = (totalCost - paymentMade).clamp(0.0, double.infinity);

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HEADER
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            old == null ? 'Add Load Expense' : 'Edit Load Expense',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // SCROLLABLE FORM BODY
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (dialogError != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, size: 16, color: scheme.onErrorContainer),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      dialogError!,
                                      style: TextStyle(color: scheme.onErrorContainer, fontSize: 12, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // A. WHAT IS THE EXPENSE?
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: categories.any((c) => c.id == selectedCatId || c.name == selectedCatId)
                                      ? selectedCatId
                                      : (categories.isNotEmpty ? categories.first.id : null),
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Expense Type *',
                                    isDense: true,
                                  ),
                                  items: categories.map((cat) {
                                    return DropdownMenuItem<String>(
                                      value: cat.id,
                                      child: Text(cat.name, overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setDlg(() {
                                      selectedCatId = val ?? 'other';
                                      final match = categories.firstWhere(
                                        (c) => c.id == val,
                                        orElse: () => ExpenseCategory(id: 'other', name: 'Other', active: true),
                                      );
                                      costKind = match.id;
                                      if (descCtrl.text.trim().isEmpty) {
                                        descCtrl.text = match.name;
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                  onPressed: () => _addNewExpenseType(setDlg, (newCat) {
                                    setDlg(() {
                                      categories.insert(0, newCat);
                                      selectedCatId = newCat.id;
                                      costKind = newCat.id;
                                      if (descCtrl.text.trim().isEmpty) {
                                        descCtrl.text = newCat.name;
                                      }
                                    });
                                  }),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          TextFormField(
                            controller: descCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Expense / invoice description',
                              hintText: 'e.g. Diesel fuel for transit or driver wage',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // B. HOW MUCH?
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: rateCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'Cost per unit (editable)',
                                    prefixText: '${widget.session.currencyCode} ',
                                    isDense: true,
                                    helperText: calcByTrips ? 'Rate per unit/trip' : 'Total expense cost amount',
                                  ),
                                  onChanged: (_) => setDlg(() {}),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilterChip(
                                label: const Text('Calculate by Trips', style: TextStyle(fontSize: 11)),
                                selected: calcByTrips,
                                onSelected: (val) => setDlg(() => calcByTrips = val),
                              ),
                            ],
                          ),

                          if (calcByTrips) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: qtyCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Units / Trips *',
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setDlg(() {}),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Computed Total', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                                        const SizedBox(height: 2),
                                        Text(_money(totalCost), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),

                          // C. WHO SHOULD RECEIVE THE MONEY? (PAID TO)
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: staffId,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Paid To / Payee Type',
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: '', child: Text('External Payee / Supplier')),
                                    for (final s in _staff)
                                      DropdownMenuItem(
                                        value: '${s['staff_id']}',
                                        child: Text(
                                          '${s['name']} • ${s['wage_basis']} ${_money(s['base_rate'])}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (val) => setDlg(() {
                                    staffId = val ?? '';
                                    if (staffId.isNotEmpty) {
                                      final selected = _staff.firstWhere((s) => '${s['staff_id']}' == staffId, orElse: () => const {});
                                      payeeCtrl.text = selected['name']?.toString() ?? '';
                                      if (selected['wage_basis'] == 'monthly') {
                                        staffMode = 'salary_allocation';
                                      } else {
                                        staffMode = 'extra_wage';
                                        if (rateCtrl.text.isEmpty || rateCtrl.text == '0') {
                                          rateCtrl.text = (selected['base_rate'] ?? '').toString();
                                        }
                                      }
                                      if (costKind != 'driver_wage' && costKind != 'staff_wage') {
                                        costKind = 'driver_wage';
                                      }
                                    }
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          if (staffId.isEmpty)
                            TextFormField(
                              controller: payeeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'External Payee / Supplier Name *',
                                hintText: 'e.g. Bharat Petroleum, City Crane Services',
                                isDense: true,
                              ),
                            )
                          else if (_staff.any((s) => '${s['staff_id']}' == staffId && s['wage_basis'] == 'monthly')) ...[
                            Material(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Monthly Staff Wage Treatment', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    RadioListTile<String>(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      value: 'salary_allocation',
                                      groupValue: staffMode,
                                      title: const Text('Already covered by salary', style: TextStyle(fontSize: 12)),
                                      subtitle: const Text('Track load cost without duplicate wage payment/liability', style: TextStyle(fontSize: 10)),
                                      onChanged: (val) => setDlg(() {
                                        staffMode = val!;
                                        paymentStatus = 'not_paid';
                                      }),
                                    ),
                                    RadioListTile<String>(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      value: 'extra_wage',
                                      groupValue: staffMode,
                                      title: const Text('Extra payment owed to staff', style: TextStyle(fontSize: 12)),
                                      subtitle: const Text('Record separate trip incentive or overtime payable', style: TextStyle(fontSize: 10)),
                                      onChanged: (val) => setDlg(() => staffMode = val!),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),

                          // D. HAS IT BEEN PAID? (PAYMENT STATUS)
                          Text('Payment Status & Settlement', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'not_paid', label: Text('Not Paid Yet', style: TextStyle(fontSize: 11.5))),
                              ButtonSegment(value: 'paid', label: Text('Paid', style: TextStyle(fontSize: 11.5))),
                              ButtonSegment(value: 'partially_paid', label: Text('Partially Paid', style: TextStyle(fontSize: 11.5))),
                            ],
                            selected: {paymentStatus},
                            onSelectionChanged: (set) => setDlg(() {
                              paymentStatus = set.first;
                              if (paymentStatus == 'paid') {
                                final liveQty = calcByTrips ? (double.tryParse(qtyCtrl.text.trim()) ?? 1.0) : 1.0;
                                final liveRate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                                final liveCost = liveQty * liveRate;
                                payCtrl.text = liveCost > 0 ? (liveCost == liveCost.roundToDouble() ? liveCost.toInt().toString() : liveCost.toStringAsFixed(2)) : '0';
                              } else if (paymentStatus == 'not_paid') {
                                payCtrl.text = '0';
                              }
                            }),
                          ),
                          const SizedBox(height: 8),

                          // Payment fields
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: payCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'Pay on load confirmation',
                                    prefixText: '${widget.session.currencyCode} ',
                                    isDense: true,
                                    helperText: paymentStatus == 'not_paid'
                                        ? 'Unpaid (0 leaves this as a payable)'
                                        : 'Paid: ${_money(paymentMade)} • Due: ${_money(remainingPay)}',
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
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: paymentMethod,
                                    decoration: const InputDecoration(labelText: 'Payment Method', isDense: true),
                                    items: const [
                                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                      DropdownMenuItem(value: 'bank', child: Text('Bank')),
                                      DropdownMenuItem(value: 'upi', child: Text('UPI')),
                                      DropdownMenuItem(value: 'card', child: Text('Card')),
                                      DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                                    ],
                                    onChanged: (val) => setDlg(() => paymentMethod = val ?? 'cash'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if ((paymentStatus != 'not_paid' || (double.tryParse(payCtrl.text.trim()) ?? 0.0) > 0) && paymentMethod != 'cash') ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: payRefCtrl,
                              decoration: const InputDecoration(labelText: 'Payment Ref *', isDense: true),
                            ),
                          ],
                          const SizedBox(height: 12),

                          // E. CHARGE THIS TO THE CUSTOMER?
                          if (widget.direction == 'outbound' && !widget.internalOnly) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.person_outline, size: 16, color: scheme.primary),
                                      const SizedBox(width: 6),
                                      const Text('Customer Invoice Charge', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(
                                        customerChargeAmt > 0 ? 'Billing Customer' : 'Internal Only',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: customerChargeAmt > 0 ? const Color(0xFF00875A) : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: billCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                            labelText: 'Amount charged to customer before GST',
                                            prefixText: '${widget.session.currencyCode} ',
                                            isDense: true,
                                            helperText: customerChargeAmt > totalCost
                                                ? '+ ${_money(customerChargeAmt - totalCost)} margin'
                                                : (customerChargeAmt > 0 && customerChargeAmt < totalCost ? '- ${_money(totalCost - customerChargeAmt)} discount' : 'Zero keeps this as internal cost'),
                                          ),
                                          onChanged: (val) {
                                            final b = double.tryParse(val.trim()) ?? 0.0;
                                            setDlg(() => chargeCustomer = b > 0);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: billingVariantId.isEmpty ? '' : billingVariantId,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Invoice service / tax classification',
                                            isDense: true,
                                          ),
                                          items: [
                                            const DropdownMenuItem(value: '', child: Text('Select charge service')),
                                            for (final s in _billing)
                                              DropdownMenuItem(
                                                value: '${s['variant_id']}',
                                                child: Text(
                                                  '${s['name']} • GST ${s['gst_rate'] ?? s['tax_rate'] ?? 0}%',
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                          onChanged: (val) => setDlg(() => billingVariantId = val ?? ''),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          // F. MORE DETAILS (COLLAPSIBLE)
                          InkWell(
                            onTap: () => setDlg(() => showMoreDetails = !showMoreDetails),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(showMoreDetails ? Icons.expand_less : Icons.expand_more, size: 18, color: scheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    showMoreDetails ? 'Less Details' : 'More Details (Receipt, References, Notes)',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (showMoreDetails) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: receiptRefCtrl,
                                    decoration: const InputDecoration(labelText: 'Bill / receipt reference', isDense: true),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: payRefCtrl,
                                    decoration: const InputDecoration(labelText: 'Payment reference', isDense: true),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: notesCtrl,
                              maxLines: 2,
                              decoration: const InputDecoration(labelText: 'Internal Notes', isDense: true),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // STICKY BOTTOM SUMMARY BAR
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Expense Cost: ${_money(totalCost)}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                            if (chargeCustomer)
                              Text(
                                'Customer Charge: ${_money(customerChargeAmt)}',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF635BFF)),
                              ),
                            Text(
                              'Payment Made: ${_money(paymentMade)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: paymentMade > 0 ? const Color(0xFF00875A) : scheme.onSurfaceVariant,
                              ),
                            ),
                            if (remainingPay > 0 && staffMode != 'salary_allocation')
                              Text(
                                'Remaining to Pay: ${_money(remainingPay)}',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFC06200)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () {
                                final costQty = calcByTrips ? (double.tryParse(qtyCtrl.text.trim()) ?? 1.0) : 1.0;
                                final costRate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                                final costAmount = costQty * costRate;
                                final custCharge = double.tryParse(billCtrl.text.trim()) ?? 0.0;
                                final enteredPay = double.tryParse(payCtrl.text.trim()) ?? 0.0;
                                final payMade = paymentStatus == 'paid'
                                    ? (enteredPay > 0 ? enteredPay : costAmount)
                                    : enteredPay;

                                if (costAmount <= 0) {
                                  setDlg(() => dialogError = 'Enter a positive expense quantity and rate.');
                                  return;
                                }
                                if (staffId.isEmpty && payeeCtrl.text.trim().isEmpty) {
                                  setDlg(() => dialogError = 'Enter the external payee name.');
                                  return;
                                }
                                if (staffId.isNotEmpty && !['driver_wage', 'staff_wage'].contains(costKind) && !costKind.contains('wage')) {
                                  setDlg(() => dialogError = 'Linked staff require a driver or staff wage expense type.');
                                  return;
                                }
                                if (staffMode == 'salary_allocation' && (staffId.isEmpty || payMade > 0 || enteredPay > 0)) {
                                  setDlg(() => dialogError = 'Salary allocation requires monthly staff and no separate payment on this load.');
                                  return;
                                }
                                if (widget.direction == 'outbound' && !widget.internalOnly && custCharge > 0 && billingVariantId.isEmpty) {
                                  setDlg(() => dialogError = 'Select or create the service used to invoice this charge.');
                                  return;
                                }
                                if (payMade > costAmount) {
                                  setDlg(() => dialogError = 'Payment cannot exceed this expense.');
                                  return;
                                }
                                if (payMade > 0 && paymentMethod != 'cash' && payRefCtrl.text.trim().isEmpty) {
                                  setDlg(() => dialogError = 'Enter the payment reference.');
                                  return;
                                }

                                final savedMap = <String, dynamic>{
                                  'id': initialId,
                                  'cost_kind': costKind,
                                  'category_id': selectedCatId,
                                  'category_name': categories.firstWhere((c) => c.id == selectedCatId, orElse: () => ExpenseCategory(id: 'other', name: 'Other', active: true)).name,
                                  'description': descCtrl.text.trim(),
                                  'staff_id': staffId,
                                  'payee': payeeCtrl.text.trim(),
                                  'staff_mode': staffMode,
                                  'quantity': costQty,
                                  'rate': costRate,
                                  'amount': costAmount,
                                  'bill_amount': (widget.internalOnly || widget.direction != 'outbound') ? 0.0 : custCharge,
                                  'billing_variant_id': custCharge > 0 ? billingVariantId : '',
                                  'initial_payment': payMade,
                                  'payment_method': paymentMethod,
                                  'payment_reference': payRefCtrl.text.trim(),
                                  'receipt_reference': receiptRefCtrl.text.trim(),
                                  'notes': notesCtrl.text.trim(),
                                };

                                Navigator.pop(ctx, savedMap);
                              },
                              child: const Text('Save'),
                            ),
                          ],
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

    if (result != null) {
      final next = [...widget.costs];
      if (index == null) {
        next.add(result);
      } else {
        next[index] = result;
      }
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Load expenses & customer charges',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text(
            'Record driver wages, rent, fuel and other costs here. Costs and any payments post together when you confirm the load. Customer charges are added to its invoice using the selected service tax classification.',
          ),
          for (var i = 0; i < widget.costs.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${widget.costs[i]['description']} • ${_money(widget.costs[i]['amount'])}',
              ),
              subtitle: Text(
                '${widget.costs[i]['payee'] ?? ''} • ${widget.costs[i]['staff_mode'] == 'salary_allocation' ? 'Monthly salary allocation' : 'Additional cost'} • Bill customer ${_money(widget.costs[i]['bill_amount'])}',
              ),
              onTap: () => _edit(i),
              trailing: IconButton(
                tooltip: 'Remove draft expense',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  final next = [...widget.costs]..removeAt(i);
                  widget.onChanged(next);
                },
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add expense'),
              ),
              if (widget.direction == 'outbound' &&
                  !widget.internalOnly &&
                  widget.contextData['can_create_billing_service'] == true)
                TextButton(
                  onPressed: _newService,
                  child: const Text('Create invoice charge service'),
                ),
            ],
          ),
          Text(
            'Total cost ${_money(widget.costs.fold<double>(0, (sum, c) => sum + StaffLoadService.number(c['amount'])))} • Customer charges ${_money(widget.costs.fold<double>(0, (sum, c) => sum + StaffLoadService.number(c['bill_amount'])))} before tax',
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> editLoadDelivery(
  BuildContext context, {
  Map<String, dynamic> initial = const {},
}) async {
  Map<String, dynamic>? saved;
  await showOperationalForm(
    context,
    title: 'Driver & delivery details',
    initial: initial,
    fields: const [
      OperationalField('driver_contact_name', 'Driver / contact name'),
      OperationalField('driver_contact_phone', 'Driver phone'),
      OperationalField('driver_license_snapshot', 'Driver licence number'),
      OperationalField('pickup_address', 'Pickup address', lines: 2),
      OperationalField('delivery_address', 'Delivery address', lines: 2),
      OperationalField('pickup_contact', 'Pickup contact'),
      OperationalField('delivery_contact', 'Delivery contact'),
      OperationalField(
        'dispatch_at',
        'Departure date and time',
        help: 'Example: 2026-10-04T09:30:00+05:30',
      ),
      OperationalField('delivered_at', 'Delivered date and time'),
      OperationalField('odometer_start', 'Start odometer (km)', number: true),
      OperationalField('odometer_end', 'End odometer (km)', number: true),
      OperationalField('delivery_latitude', 'Delivery latitude'),
      OperationalField('delivery_longitude', 'Delivery longitude'),
      OperationalField('received_by', 'Received by'),
      OperationalField('proof_reference', 'Delivery proof / reference'),
      OperationalField(
        'delivery_notes',
        'Delivery instructions / notes',
        lines: 3,
      ),
    ],
    onSave: (d) async {
      saved = d;
    },
  );
  return saved;
}

class LoadEvidenceCard extends StatelessWidget {
  final Map<String, dynamic> record;
  const LoadEvidenceCard({super.key, required this.record});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final calcCft = record['calculated_cft'];
    final heapAdj = record['heap_adjustment_cft'];
    final billableQty = record['approved_billable_qty'];
    final varianceNotes = record['measurement_notes'];

    final isInbound = record['direction'] == 'inbound';
    final invNum = record['invoice_number']?.toString() ??
        (record['purchase'] is Map ? record['purchase']['purchase_number']?.toString() : null) ??
        (record['sale'] is Map ? record['sale']['sale_number']?.toString() : null);
    final invRate = record['invoice_rate'] is num
        ? (record['invoice_rate'] as num).toDouble()
        : double.tryParse(record['invoice_rate']?.toString() ?? '');
    final invAmount = record['invoice_amount'] is num
        ? (record['invoice_amount'] as num).toDouble()
        : double.tryParse(record['invoice_amount']?.toString() ?? '');
    final invGrandTotal = record['invoice_grand_total'] is num
        ? (record['invoice_grand_total'] as num).toDouble()
        : double.tryParse(record['invoice_grand_total']?.toString() ?? '');
    final isConfirmed = record['status'] == 'completed';
    final isBilled = invNum != null && invNum.isNotEmpty;
    final isRatePending = invRate == null || invRate <= 0;

    String amountDisplay;
    Color amountColor;
    if (isBilled) {
      final total = invGrandTotal ?? invAmount ?? 0.0;
      amountDisplay = '₹ ${NumberFormat('#,##0.00').format(total)}';
      amountColor = const Color(0xFF00875A);
    } else if (isRatePending) {
      amountDisplay = 'Amount Pending';
      amountColor = const Color(0xFFC06200);
    } else if (invAmount != null && invAmount > 0) {
      amountDisplay = '₹ ${NumberFormat('#,##0.00').format(invAmount)} (Est)';
      amountColor = scheme.onSurfaceVariant;
    } else {
      amountDisplay = 'Amount Pending';
      amountColor = const Color(0xFFC06200);
    }

    final partyName = (record['source_name'] ?? record['supplier_name'] ?? record['destination_name'] ?? record['customer_name'] ?? '').toString();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. PRIMARY: Direction + Material / Quality + Party + Total Amount
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    color: isInbound
                        ? const Color(0xFF00875A).withValues(alpha: 0.12)
                        : const Color(0xFF635BFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    isInbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                    size: 13,
                    color: isInbound ? const Color(0xFF00875A) : const Color(0xFF635BFF),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${record['product_name'] ?? 'Aggregate Material'}'
                          '${record['variant_name'] != null && record['variant_name'].toString().isNotEmpty ? ' (${record['variant_name']})' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      if (partyName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '•  $partyName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  amountDisplay,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),

            // 2. SECONDARY: Quantity + Rate + Vehicle & Driver + Route
            Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${record['quantity'] ?? ''} ${record['unit_code'] ?? 'CFT'}'
                  '${calcCft != null && calcCft > 0 ? ' (Calc: $calcCft CFT)' : ''}'
                  '${heapAdj != null && heapAdj != 0 ? ' [H: $heapAdj CFT]' : ''}'
                  '${billableQty != null && billableQty != record['quantity'] ? ' • Billable: $billableQty ${record['unit_code'] ?? ''}' : ''}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                if (invRate != null && invRate > 0)
                  Text(
                    '•  Rate: ₹${NumberFormat('#,##0.00').format(invRate)} / ${record['unit_code'] ?? 'CFT'}',
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                  )
                else
                  Text(
                    '•  Rate pending',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFC06200)),
                  ),
                Text(
                  '|  ${record['vehicle_registration'] ?? record['vehicle_registration_snapshot'] ?? 'No vehicle'}'
                  '${record['driver_name'] != null ? ' • ${record['driver_name']}' : ''}',
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
                Text(
                  '•  ${record['source_name'] ?? ''} → ${record['destination_name'] ?? ''}',
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),

            if (varianceNotes != null && varianceNotes.toString().trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Audit: $varianceNotes',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, fontStyle: FontStyle.italic),
                ),
              ),
            ],

            const SizedBox(height: 4),

            // 3. TERTIARY: Load # • Invoice Status Badge • Actions
            Row(
              children: [
                Text(
                  '#${record['load_number'] ?? ''}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                    color: scheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                if (isBilled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00875A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF00875A).withValues(alpha: 0.3), width: 0.8),
                    ),
                    child: Text(
                      'INVOICE: $invNum',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF00875A)),
                    ),
                  )
                else if (isConfirmed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8B00).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFFF8B00).withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: Text(
                      isRatePending ? 'UNBILLED (RATE PENDING)' : 'CONFIRMED UNBILLED',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFC06200)),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  onPressed: () => RecordPreview.show(
                    context,
                    title: 'All saved load, cost, driver and delivery details',
                    record: record,
                  ),
                  child: const Text('Preview saved details', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
