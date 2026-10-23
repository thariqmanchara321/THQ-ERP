// ignore_for_file: deprecated_member_use
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
    final old = index == null ? null : widget.costs[index];
    final result = await showAddLoadExpenseDialog(
      context: context,
      session: widget.session,
      locationId: widget.locationId,
      direction: widget.direction,
      driverId: widget.driverId,
      contextData: widget.contextData,
      staff: _staff,
      billingServices: _billing,
      internalOnly: widget.internalOnly,
      initialCost: old,
      existingCosts: widget.costs,
      categories: _dynamicCategories,
      onAddNewCategory: () async {
        ExpenseCategory? created;
        await _addNewExpenseType((fn) => setState(fn), (newCat) {
          created = newCat;
        });
        return created;
      },
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalCost = widget.costs.fold<double>(
      0,
      (sum, c) => sum + StaffLoadService.number(c['amount']),
    );
    final totalCustomerCharges = widget.costs.fold<double>(
      0,
      (sum, c) => sum + StaffLoadService.number(c['bill_amount']),
    );
    final totalPaid = widget.costs.fold<double>(
      0,
      (sum, c) => sum + StaffLoadService.number(c['initial_payment']),
    );
    final totalDue = (totalCost - totalPaid).clamp(0.0, double.infinity);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Load expenses & customer charges',
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add expense', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Record driver wages, rent, fuel and other costs. Costs and payments post together upon load confirmation.',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (widget.costs.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'No expenses added yet. Tap "Add expense" to record load costs.',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (var i = 0; i < widget.costs.length; i++) ...[
                InkWell(
                  onTap: () => _edit(i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          widget.costs[i]['cost_kind'] == 'diesel'
                              ? Icons.local_gas_station_outlined
                              : (widget.costs[i]['cost_kind']?.toString().contains('wage') == true
                                  ? Icons.badge_outlined
                                  : Icons.receipt_outlined),
                          size: 16,
                          color: scheme.primary,
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
                                    '${widget.costs[i]['description'] ?? 'Expense'}',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  _money(widget.costs[i]['amount']),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Payee: ${widget.costs[i]['payee'] ?? '—'}',
                                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                ),
                                if (widget.costs[i]['staff_mode'] == 'salary_allocation')
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Salaried', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600)),
                                  ),
                                if (StaffLoadService.number(widget.costs[i]['initial_payment']) > 0)
                                  Text(
                                    'Paid: ${_money(widget.costs[i]['initial_payment'])}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF00875A)),
                                  )
                                else if (widget.costs[i]['staff_mode'] != 'salary_allocation')
                                  Text(
                                    'Due: ${_money(widget.costs[i]['amount'])}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFC06200)),
                                  ),
                                if (StaffLoadService.number(widget.costs[i]['bill_amount']) > 0)
                                  Text(
                                    'Bill: ${_money(widget.costs[i]['bill_amount'])}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF635BFF)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        tooltip: 'Edit expense',
                        onPressed: () => _edit(i),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, size: 16),
                        tooltip: 'Remove expense',
                        onPressed: () {
                          final next = [...widget.costs]..removeAt(i);
                          widget.onChanged(next);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    'Total Cost: ${_money(totalCost)}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  if (totalPaid > 0)
                    Text(
                      'Paid: ${_money(totalPaid)}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF00875A)),
                    ),
                  if (totalDue > 0)
                    Text(
                      'Outstanding: ${_money(totalDue)}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFC06200)),
                    ),
                  if (totalCustomerCharges > 0)
                    Text(
                      'Customer Charges: ${_money(totalCustomerCharges)}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF635BFF)),
                    ),
                ],
              ),
            ),
            if (widget.direction == 'outbound' &&
                !widget.internalOnly &&
                widget.contextData['can_create_billing_service'] == true) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _newService,
                  icon: const Icon(Icons.add_circle_outline, size: 14),
                  label: const Text('Create invoice charge service', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standalone, compact, operator-friendly dialog for Adding/Editing Load Expenses.
/// Conforms to THQ ERP Phase 2-9 specifications:
/// - Single External Payee field with autocomplete history and direct typing
/// - Total Amount vs Per Trip calculation toggle
/// - Unpaid / Paid / Partially Paid settlement tracking
/// - Optional Customer Invoice Charges
/// - Strict accounting integration with zero duplicate journals or broken overlays
Future<Map<String, dynamic>?> showAddLoadExpenseDialog({
  required BuildContext context,
  required ClientSession session,
  required String locationId,
  required String direction,
  String? driverId,
  required Map<String, dynamic> contextData,
  List<Map<String, dynamic>>? staff,
  List<Map<String, dynamic>>? billingServices,
  bool internalOnly = false,
  Map<String, dynamic>? initialCost,
  List<Map<String, dynamic>> existingCosts = const [],
  List<ExpenseCategory>? categories,
  Future<ExpenseCategory?> Function()? onAddNewCategory,
}) async {
  final staffRows = staff ??
      StaffLoadService.rows(contextData['staff'])
          .where((s) => s['location_id'] == null || s['location_id'] == locationId)
          .toList();

  Map<String, dynamic>? driver;
  for (final s in staffRows) {
    if (s['driver_id'] == driverId && driverId != null) {
      driver = s;
      break;
    }
  }
  final salary = driver?['wage_basis'] == 'monthly';

  final List<ExpenseCategory> availableCategories = categories != null && categories.isNotEmpty
      ? [...categories]
      : () {
          final raw = contextData['expense_categories'];
          if (raw is List && raw.isNotEmpty) {
            return raw
                .whereType<Map>()
                .map((e) => ExpenseCategory.fromMap(Map<String, dynamic>.from(e)))
                .toList();
          }
          return _LoadCostEditorState.defaultKinds.entries
              .map((e) => ExpenseCategory(id: e.key, name: e.value, active: true))
              .toList();
        }();

  final activeBillingServices = billingServices ??
      StaffLoadService.rows(contextData['billing_services']);

  final old = initialCost;
  final initialId = old?['id'] ?? const Uuid().v4();
  var selectedCatId = old?['category_id']?.toString() ??
      (old?['cost_kind'] != null && old!['cost_kind'] != 'other'
          ? old['cost_kind']
          : (driver != null ? 'driver_wage' : 'diesel'));
  var costKind = old?['cost_kind']?.toString() ?? (driver != null ? 'driver_wage' : 'diesel');
  var staffId = old?['staff_id']?.toString() ?? driver?['staff_id']?.toString() ?? '';
  var staffMode = old?['staff_mode']?.toString() ?? (salary ? 'salary_allocation' : 'extra_wage');
  var paymentMethod = old?['payment_method']?.toString() ?? 'cash';
  var billingVariantId = old?['billing_variant_id']?.toString() ?? '';

  final initialQty = StaffLoadService.number(old?['quantity'] ?? 1);
  final initialRate = salary ? 0.0 : StaffLoadService.number(old?['rate'] ?? driver?['base_rate'] ?? 0);
  final initialAmt = StaffLoadService.number(old?['amount'] ?? (initialQty * initialRate));
  final initialBill = StaffLoadService.number(old?['bill_amount'] ?? 0);
  final initialPay = StaffLoadService.number(old?['initial_payment'] ?? 0);

  var calcByTrips = (old != null && initialQty > 1) || (old == null && driver != null && driver['wage_basis'] == 'per_trip');
  var chargeCustomer = initialBill > 0;
  var paymentStatus = initialPay >= initialAmt && initialAmt > 0
      ? 'paid'
      : (initialPay > 0 ? 'partially_paid' : 'unpaid');

  final descCtrl = TextEditingController(
    text: old?['description']?.toString() ?? (driver != null ? 'Driver wage' : ''),
  );
  final payeeCtrl = TextEditingController(
    text: old?['payee']?.toString() ?? driver?['name']?.toString() ?? '',
  );
  final qtyCtrl = TextEditingController(
    text: initialQty > 0
        ? (initialQty == initialQty.roundToDouble() ? initialQty.toInt().toString() : initialQty.toString())
        : '1',
  );
  final rateCtrl = TextEditingController(
    text: calcByTrips
        ? (initialRate > 0 ? (initialRate == initialRate.roundToDouble() ? initialRate.toInt().toString() : initialRate.toString()) : '')
        : (initialAmt > 0 ? (initialAmt == initialAmt.roundToDouble() ? initialAmt.toInt().toString() : initialAmt.toString()) : (initialRate > 0 ? initialRate.toString() : '')),
  );
  final billCtrl = TextEditingController(
    text: initialBill > 0
        ? (initialBill == initialBill.roundToDouble() ? initialBill.toInt().toString() : initialBill.toString())
        : '0',
  );
  final payCtrl = TextEditingController(
    text: initialPay > 0
        ? (initialPay == initialPay.roundToDouble() ? initialPay.toInt().toString() : initialPay.toString())
        : '0',
  );
  final payRefCtrl = TextEditingController(text: old?['payment_reference']?.toString() ?? '');
  final receiptRefCtrl = TextEditingController(text: old?['receipt_reference']?.toString() ?? '');
  final notesCtrl = TextEditingController(text: old?['notes']?.toString() ?? '');

  var showMoreDetails = (old?['receipt_reference'] != null && old!['receipt_reference'].toString().isNotEmpty) ||
      (old?['notes'] != null && old!['notes'].toString().isNotEmpty);

  String? dialogError;

  // Build autocomplete suggestions for External Payee
  final Set<String> knownPayees = {};
  for (final c in existingCosts) {
    final p = c['payee']?.toString().trim();
    if (p != null && p.isNotEmpty) knownPayees.add(p);
  }
  for (final s in staffRows) {
    final n = s['name']?.toString().trim();
    if (n != null && n.isNotEmpty) knownPayees.add(n);
  }
  final rawSuppliers = contextData['suppliers'];
  if (rawSuppliers is List) {
    for (final sup in rawSuppliers) {
      if (sup is Map && sup['name'] != null) {
        final n = sup['name'].toString().trim();
        if (n.isNotEmpty) knownPayees.add(n);
      }
    }
  }
  final rawPayees = contextData['payees'] ?? contextData['recent_payees'];
  if (rawPayees is List) {
    for (final rp in rawPayees) {
      if (rp is String && rp.trim().isNotEmpty) {
        knownPayees.add(rp.trim());
      } else if (rp is Map && rp['name'] != null) {
        final n = rp['name'].toString().trim();
        if (n.isNotEmpty) knownPayees.add(n);
      }
    }
  }

  String money(dynamic val) =>
      '${session.currencyCode} ${StaffLoadService.number(val).toStringAsFixed(2)}';

  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (dlgContext) => StatefulBuilder(
      builder: (ctx, setDlg) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;

        final double currentQty = calcByTrips ? (double.tryParse(qtyCtrl.text.trim()) ?? 1.0) : 1.0;
        final double currentRate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
        final double totalCost = currentQty * currentRate;
        final double customerChargeAmt = double.tryParse(billCtrl.text.trim()) ?? 0.0;
        final double enteredPayment = double.tryParse(payCtrl.text.trim()) ?? 0.0;
        final double paymentMade = paymentStatus == 'paid'
            ? (enteredPayment > 0 ? enteredPayment : totalCost)
            : (paymentStatus == 'unpaid' ? 0.0 : enteredPayment);
        final double remainingPay = (totalCost - paymentMade).clamp(0.0, double.infinity);

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // HEADER
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
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
                        tooltip: 'Close',
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
                          const SizedBox(height: 10),
                        ],

                        // 1. EXPENSE TYPE
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: availableCategories.any((c) => c.id == selectedCatId || c.name == selectedCatId)
                                    ? selectedCatId
                                    : (availableCategories.isNotEmpty ? availableCategories.first.id : null),
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Expense Type *',
                                  isDense: true,
                                ),
                                items: availableCategories.map((cat) {
                                  return DropdownMenuItem<String>(
                                    value: cat.id,
                                    child: Text(cat.name, overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setDlg(() {
                                    selectedCatId = val ?? 'other';
                                    final match = availableCategories.firstWhere(
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
                            if (onAddNewCategory != null) ...[
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                  onPressed: () async {
                                    final newCat = await onAddNewCategory();
                                    if (newCat != null) {
                                      setDlg(() {
                                        availableCategories.insert(0, newCat);
                                        selectedCatId = newCat.id;
                                        costKind = newCat.id;
                                        if (descCtrl.text.trim().isEmpty) {
                                          descCtrl.text = newCat.name;
                                        }
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),

                        TextFormField(
                          controller: descCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Expense / invoice description',
                            hintText: 'e.g. Diesel fuel, Driver wage, Quarry freight',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 2. EXTERNAL PAYEE ONLY (Phase 3)
                        RawAutocomplete<String>(
                          initialValue: TextEditingValue(text: payeeCtrl.text),
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.trim().isEmpty) {
                              return knownPayees.take(6);
                            }
                            final q = textEditingValue.text.trim().toLowerCase();
                            return knownPayees.where((name) => name.toLowerCase().contains(q)).take(8);
                          },
                          onSelected: (String selection) {
                            payeeCtrl.text = selection;
                            final matchedStaff = staffRows.where(
                              (s) => s['name']?.toString().toLowerCase() == selection.toLowerCase(),
                            ).firstOrNull;
                            setDlg(() {
                              if (matchedStaff != null) {
                                staffId = '${matchedStaff['staff_id']}';
                                if (matchedStaff['wage_basis'] == 'monthly') {
                                  staffMode = 'salary_allocation';
                                } else {
                                  staffMode = 'extra_wage';
                                  if (rateCtrl.text.isEmpty || rateCtrl.text == '0') {
                                    rateCtrl.text = (matchedStaff['base_rate'] ?? '').toString();
                                  }
                                }
                                if (!costKind.contains('wage')) {
                                  costKind = 'driver_wage';
                                }
                              } else {
                                staffId = '';
                                staffMode = 'extra_wage';
                              }
                            });
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(8),
                                color: scheme.surfaceContainerHighest,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 360, maxHeight: 180),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    itemCount: options.length,
                                    separatorBuilder: (context, index) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        leading: Icon(Icons.history, size: 16, color: scheme.primary),
                                        title: Text(option, style: const TextStyle(fontSize: 12.5)),
                                        onTap: () => onSelected(option),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            if (controller.text != payeeCtrl.text && focusNode.hasFocus) {
                              payeeCtrl.text = controller.text;
                            }
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'External Payee *',
                                hintText: 'Search or enter external payee',
                                isDense: true,
                                prefixIcon: Icon(Icons.person_outline, size: 18),
                              ),
                              onChanged: (val) {
                                payeeCtrl.text = val;
                                final matchedStaff = staffRows.where(
                                  (s) => s['name']?.toString().toLowerCase() == val.trim().toLowerCase(),
                                ).firstOrNull;
                                setDlg(() {
                                  if (matchedStaff != null) {
                                    staffId = '${matchedStaff['staff_id']}';
                                    if (matchedStaff['wage_basis'] == 'monthly') {
                                      staffMode = 'salary_allocation';
                                    } else {
                                      staffMode = 'extra_wage';
                                    }
                                  } else {
                                    staffId = '';
                                    staffMode = 'extra_wage';
                                  }
                                });
                              },
                              onFieldSubmitted: (val) {
                                payeeCtrl.text = val;
                                onFieldSubmitted();
                              },
                            );
                          },
                        ),

                        if (staffId.isNotEmpty && staffRows.any((s) => '${s['staff_id']}' == staffId && s['wage_basis'] == 'monthly')) ...[
                          const SizedBox(height: 6),
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
                                      paymentStatus = 'unpaid';
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

                        // 3. CALCULATION METHOD & AMOUNT (Phase 5)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Calculation Method',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                              ),
                            ),
                            SegmentedButton<String>(
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: 'total',
                                  label: Text('Total Amount', style: TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: 'per_trip',
                                  label: Text('Per Trip', style: TextStyle(fontSize: 11)),
                                ),
                              ],
                              selected: {calcByTrips ? 'per_trip' : 'total'},
                              onSelectionChanged: (set) => setDlg(() {
                                calcByTrips = set.first == 'per_trip';
                                if (!calcByTrips) {
                                  qtyCtrl.text = '1';
                                } else {
                                  if (qtyCtrl.text.isEmpty || qtyCtrl.text == '0') {
                                    qtyCtrl.text = '1';
                                  }
                                }
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (!calcByTrips)
                          TextFormField(
                            controller: rateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Expense Amount *',
                              prefixText: '${session.currencyCode} ',
                              isDense: true,
                              helperText: 'Total expense cost amount',
                            ),
                            onChanged: (_) => setDlg(() {}),
                          )
                        else ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: rateCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'Rate per trip *',
                                    prefixText: '${session.currencyCode} ',
                                    isDense: true,
                                    helperText: 'Rate per trip',
                                  ),
                                  onChanged: (_) => setDlg(() {}),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: qtyCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Trips *',
                                    isDense: true,
                                    helperText: 'Number of trips',
                                  ),
                                  onChanged: (_) => setDlg(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Computed Total: ${money(totalCost)}',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.primary),
                          ),
                        ],
                        const SizedBox(height: 12),

                        // 4. PAYMENT STATUS & SETTLEMENT (Phase 6)
                        Text(
                          'Payment Status & Settlement',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: 'unpaid',
                              label: Text('Unpaid', style: TextStyle(fontSize: 11.5)),
                            ),
                            ButtonSegment(
                              value: 'paid',
                              label: Text('Paid', style: TextStyle(fontSize: 11.5)),
                            ),
                            ButtonSegment(
                              value: 'partially_paid',
                              label: Text('Partially Paid', style: TextStyle(fontSize: 11.5)),
                            ),
                          ],
                          selected: {
                            paymentStatus == 'unpaid' || paymentStatus == 'not_paid'
                                ? 'unpaid'
                                : (paymentStatus == 'paid' ? 'paid' : 'partially_paid')
                          },
                          onSelectionChanged: (set) => setDlg(() {
                            paymentStatus = set.first;
                            if (paymentStatus == 'paid') {
                              payCtrl.text = totalCost > 0
                                  ? (totalCost == totalCost.roundToDouble()
                                      ? totalCost.toInt().toString()
                                      : totalCost.toStringAsFixed(2))
                                  : '0';
                            } else if (paymentStatus == 'unpaid') {
                              payCtrl.text = '0';
                            } else {
                              if (payCtrl.text == '0' || (double.tryParse(payCtrl.text.trim()) ?? 0.0) >= totalCost) {
                                payCtrl.text = '';
                              }
                            }
                          }),
                        ),
                        const SizedBox(height: 8),

                        if (paymentStatus == 'unpaid' || paymentStatus == 'not_paid')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, size: 15, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Unpaid: Full ${money(totalCost)} will be recorded as payable owed to payee on confirmation.',
                                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (paymentStatus == 'paid') ...[
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00875A).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF00875A).withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF00875A)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Full Payment: ${money(totalCost)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF00875A),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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
                          ),
                          if (paymentMethod != 'cash') ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: payRefCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Payment Reference *',
                                hintText: 'UTR / Cheque # / Txn ID',
                                isDense: true,
                              ),
                            ),
                          ],
                        ] else ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: payCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'Amount Paid *',
                                    prefixText: '${session.currencyCode} ',
                                    isDense: true,
                                    helperText: 'Paid: ${money(paymentMade)} • Due: ${money(remainingPay)}',
                                  ),
                                  onChanged: (val) {
                                    final amt = double.tryParse(val.trim()) ?? 0.0;
                                    setDlg(() {
                                      if (amt <= 0) {
                                        paymentStatus = 'unpaid';
                                      } else if (amt >= totalCost && totalCost > 0) {
                                        paymentStatus = 'paid';
                                      } else {
                                        paymentStatus = 'partially_paid';
                                      }
                                    });
                                  },
                                ),
                              ),
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
                          ),
                          if (paymentMethod != 'cash') ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: payRefCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Payment Reference *',
                                hintText: 'UTR / Cheque # / Txn ID',
                                isDense: true,
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),

                        // 5. OPTIONAL CUSTOMER INVOICE CHARGE (Phase 7)
                        if (direction == 'outbound' && !internalOnly) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => setDlg(() {
                                    chargeCustomer = !chargeCustomer;
                                    if (!chargeCustomer) {
                                      billCtrl.text = '0';
                                      billingVariantId = '';
                                    } else {
                                      if (billCtrl.text.isEmpty || billCtrl.text == '0') {
                                        billCtrl.text = totalCost > 0
                                            ? (totalCost == totalCost.roundToDouble()
                                                ? totalCost.toInt().toString()
                                                : totalCost.toStringAsFixed(2))
                                            : '';
                                      }
                                    }
                                  }),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: chargeCustomer,
                                        visualDensity: VisualDensity.compact,
                                        onChanged: (val) => setDlg(() {
                                          chargeCustomer = val ?? false;
                                          if (!chargeCustomer) {
                                            billCtrl.text = '0';
                                            billingVariantId = '';
                                          } else {
                                            if (billCtrl.text.isEmpty || billCtrl.text == '0') {
                                              billCtrl.text = totalCost > 0
                                                  ? (totalCost == totalCost.roundToDouble()
                                                      ? totalCost.toInt().toString()
                                                      : totalCost.toStringAsFixed(2))
                                                  : '';
                                            }
                                          }
                                        }),
                                      ),
                                      const Text(
                                        'Charge Customer',
                                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                      ),
                                      const Spacer(),
                                      Text(
                                        chargeCustomer ? 'Billing Customer' : 'Internal Only',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: chargeCustomer ? const Color(0xFF635BFF) : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (chargeCustomer) ...[
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
                                            prefixText: '${session.currencyCode} ',
                                            isDense: true,
                                            helperText: customerChargeAmt > totalCost
                                                ? '+ ${money(customerChargeAmt - totalCost)} margin'
                                                : (customerChargeAmt > 0 && customerChargeAmt < totalCost
                                                    ? '- ${money(totalCost - customerChargeAmt)} discount'
                                                    : 'Amount billed to customer before tax'),
                                          ),
                                          onChanged: (val) => setDlg(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: billingVariantId.isEmpty ? null : billingVariantId,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Invoice service / tax classification',
                                            isDense: true,
                                          ),
                                          items: [
                                            for (final s in activeBillingServices)
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // 6. MORE DETAILS (COLLAPSIBLE)
                        InkWell(
                          onTap: () => setDlg(() => showMoreDetails = !showMoreDetails),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(showMoreDetails ? Icons.expand_less : Icons.expand_more, size: 18, color: scheme.primary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    showMoreDetails ? 'Less Details' : 'More Details (Receipt, References, Notes)',
                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: scheme.primary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                    border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Expense: ${money(totalCost)}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                          if (chargeCustomer && customerChargeAmt > 0)
                            Text(
                              'Customer Charge: ${money(customerChargeAmt)}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF635BFF)),
                            ),
                          Text(
                            'Paid: ${money(paymentMade)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: paymentMade > 0 ? const Color(0xFF00875A) : scheme.onSurfaceVariant,
                            ),
                          ),
                          if (remainingPay > 0 && staffMode != 'salary_allocation')
                            Text(
                              'Due: ${money(remainingPay)}',
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
                            key: const ValueKey('save_expense_button'),
                            onPressed: () {
                              final costQty = calcByTrips ? (double.tryParse(qtyCtrl.text.trim()) ?? 1.0) : 1.0;
                              final costRate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                              final costAmount = costQty * costRate;
                              final custCharge = chargeCustomer ? (double.tryParse(billCtrl.text.trim()) ?? 0.0) : 0.0;
                              final enteredPay = double.tryParse(payCtrl.text.trim()) ?? 0.0;
                              final payMade = paymentStatus == 'paid'
                                  ? (enteredPay > 0 ? enteredPay : costAmount)
                                  : (paymentStatus == 'unpaid' ? 0.0 : enteredPay);

                              if (costAmount <= 0) {
                                setDlg(() => dialogError = 'Enter a positive expense amount.');
                                return;
                              }
                              if (payeeCtrl.text.trim().isEmpty) {
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
                              if (direction == 'outbound' && !internalOnly && chargeCustomer && custCharge > 0 && billingVariantId.isEmpty) {
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
                                'category_name': availableCategories.firstWhere((c) => c.id == selectedCatId, orElse: () => ExpenseCategory(id: 'other', name: 'Other', active: true)).name,
                                'description': descCtrl.text.trim().isNotEmpty
                                    ? descCtrl.text.trim()
                                    : availableCategories.firstWhere((c) => c.id == selectedCatId, orElse: () => ExpenseCategory(id: 'other', name: 'Other', active: true)).name,
                                'staff_id': staffId,
                                'payee': payeeCtrl.text.trim(),
                                'staff_mode': staffMode,
                                'quantity': costQty,
                                'rate': costRate,
                                'amount': costAmount,
                                'bill_amount': (internalOnly || direction != 'outbound' || !chargeCustomer) ? 0.0 : custCharge,
                                'billing_variant_id': (chargeCustomer && custCharge > 0) ? billingVariantId : '',
                                'initial_payment': payMade,
                                'payment_method': paymentMethod,
                                'payment_reference': payRefCtrl.text.trim(),
                                'receipt_reference': receiptRefCtrl.text.trim(),
                                'notes': notesCtrl.text.trim(),
                              };

                              Navigator.pop(ctx, savedMap);
                            },
                            child: const Text('Save Expense'),
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
