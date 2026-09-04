import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/expense.dart';
import '../models/payment_pending.dart';
import '../services/expense_service.dart';
import '../services/location_scope_service.dart';
import '../services/payment_center_service.dart';
import 'party_statement_screen.dart';
import 'purchase_detail_screen.dart';
import 'sale_detail_screen.dart';

class PaymentCenterScreen extends StatefulWidget {
  final ClientSession session;
  const PaymentCenterScreen({super.key, required this.session});

  @override
  State<PaymentCenterScreen> createState() => _PaymentCenterScreenState();
}

class _PaymentCenterScreenState extends State<PaymentCenterScreen> {
  final _service = PaymentCenterService();
  final _expenseService = ExpenseService();
  final _query = TextEditingController();
  late Future<PendingPaymentsData> _future;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _load() {
    _future = _service.load(widget.session, query: _query.text.trim());
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  String _m(double v) => widget.session.currencyCode == 'INR'
      ? 'INR ${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';

  Future<void> _openParty(PartyPendingSummary party) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PartyPaymentDetailScreen(
          session: widget.session,
          summary: party,
          service: _service,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  bool _requireSpecificStore() {
    if (LocationScopeService.selectedLocationId.value != null) return true;
    ThqNotify.showSnackBar(
      context,
      const SnackBar(
        content: Text(
          'Select a specific store before recording payments or expenses. All Stores is view-only.',
        ),
      ),
    );
    return false;
  }

  Future<void> _receiveCustomer(PartyPendingSummary party) async {
    if (_actionBusy || !_requireSpecificStore()) return;
    if (party.salesOutstanding <= .005) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(
          content: Text(
            'This customer has no sales receivable to collect here. Loan settlements remain in the Loans workspace.',
          ),
        ),
      );
      return;
    }

    final draft = await showDialog<_DirectPaymentDraft>(
      context: context,
      builder: (_) => _DirectPaymentDialog(
        title: 'Receive from ${party.partyName}',
        actionLabel: 'Receive',
        maximumAmount: party.salesOutstanding,
      ),
    );
    if (draft == null || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await _service.receiveCustomerPayment(
        widget.session,
        customerId: party.partyId,
        amount: draft.amount,
        paymentMethod: draft.paymentMethod,
        referenceNumber: draft.reference,
        notes: draft.notes,
      );
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ThqNotify.success(context, 'Payment received from ${party.partyName}.');
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _paySupplier(PartyPendingSummary party) async {
    if (_actionBusy || !_requireSpecificStore()) return;
    if (party.balance <= .005) return;

    final draft = await showDialog<_DirectPaymentDraft>(
      context: context,
      builder: (_) => _DirectPaymentDialog(
        title: 'Pay ${party.partyName}',
        actionLabel: 'Pay',
        maximumAmount: party.balance,
      ),
    );
    if (draft == null || !mounted) return;

    setState(() => _actionBusy = true);
    try {
      await _service.paySupplier(
        widget.session,
        supplierId: party.partyId,
        amount: draft.amount,
        paymentMethod: draft.paymentMethod,
        referenceNumber: draft.reference,
        notes: draft.notes,
      );
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ThqNotify.success(
        context,
        'Supplier payment recorded for ${party.partyName}.',
      );
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _addSupplierExpense(PartyPendingSummary party) async {
    if (_actionBusy || !_requireSpecificStore()) return;

    setState(() => _actionBusy = true);
    try {
      final categories = (await _expenseService.getCategories(
        tenantId: widget.session.business.id,
      )).where((category) => category.active).toList(growable: false);

      if (!mounted) return;
      if (categories.isEmpty) {
        throw StateError('Create an active expense category first.');
      }

      setState(() => _actionBusy = false);
      final draft = await showDialog<_SupplierExpenseDraft>(
        context: context,
        builder: (_) => _SupplierExpenseDialog(
          supplierName: party.partyName,
          categories: categories,
        ),
      );
      if (draft == null || !mounted) return;

      setState(() => _actionBusy = true);
      await _expenseService.createExpense(
        tenantId: widget.session.business.id,
        categoryId: draft.categoryId,
        expenseDate: DateTime.now(),
        payee: party.partyName,
        description: draft.description,
        amount: draft.amount,
        taxAmount: draft.taxAmount,
        paymentMethod: draft.paymentMethod,
        referenceNumber: draft.reference,
        notes: draft.notes,
      );

      if (!mounted) return;
      ThqNotify.success(context, 'Expense recorded for ${party.partyName}.');
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 26,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Payments',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Customer receivables and supplier payables by party',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh balances',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => setState(_load),
              decoration: InputDecoration(
                hintText:
                    'Search customer, supplier, phone, email or tracking ID',
                prefixIcon: const Icon(Icons.search, size: 17),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _query.clear();
                          setState(_load);
                        },
                        icon: const Icon(Icons.close, size: 17),
                      ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: FutureBuilder<PendingPaymentsData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: SelectableText(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final data = snapshot.data!;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final receive = _PartyPane(
                      title: 'Customers - To Receive',
                      subtitle:
                          '${data.receivables.length} customer account(s)',
                      icon: Icons.south_west_rounded,
                      amount: data.totalReceivable,
                      money: _m,
                      rows: data.receivables,
                      onOpen: _openParty,
                      onPayment: _actionBusy ? null : _receiveCustomer,
                    );
                    final pay = _PartyPane(
                      title: 'Suppliers - To Pay',
                      subtitle: '${data.payables.length} supplier account(s)',
                      icon: Icons.north_east_rounded,
                      amount: data.totalPayable,
                      money: _m,
                      rows: data.payables,
                      onOpen: _openParty,
                      onPayment: _actionBusy ? null : _paySupplier,
                      onExpense: _actionBusy ? null : _addSupplierExpense,
                    );

                    if (constraints.maxWidth < 900) {
                      return Column(
                        children: [
                          Expanded(child: receive),
                          const SizedBox(height: 6),
                          Expanded(child: pay),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: receive),
                        const SizedBox(width: 6),
                        Expanded(child: pay),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectPaymentDraft {
  const _DirectPaymentDraft({
    required this.amount,
    required this.paymentMethod,
    required this.reference,
    required this.notes,
  });

  final double amount;
  final String paymentMethod;
  final String reference;
  final String notes;
}

class _DirectPaymentDialog extends StatefulWidget {
  const _DirectPaymentDialog({
    required this.title,
    required this.actionLabel,
    required this.maximumAmount,
  });

  final String title;
  final String actionLabel;
  final double maximumAmount;

  @override
  State<_DirectPaymentDialog> createState() => _DirectPaymentDialogState();
}

class _DirectPaymentDialogState extends State<_DirectPaymentDialog> {
  late final TextEditingController _amount;
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  String _method = 'cash';
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.maximumAmount.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }
    if (amount > widget.maximumAmount + .005) {
      setState(
        () => _error =
            'Amount cannot exceed ${widget.maximumAmount.toStringAsFixed(2)}.',
      );
      return;
    }
    Navigator.pop(
      context,
      _DirectPaymentDraft(
        amount: amount,
        paymentMethod: _method,
        reference: _reference.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              helperText: 'Maximum ${widget.maximumAmount.toStringAsFixed(2)}',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'upi', child: Text('UPI')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(value: 'bank', child: Text('Bank')),
              DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (value) => setState(() => _method = value ?? _method),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(labelText: 'Reference'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
    ],
  );
}

class _SupplierExpenseDraft {
  const _SupplierExpenseDraft({
    required this.categoryId,
    required this.description,
    required this.amount,
    required this.taxAmount,
    required this.paymentMethod,
    required this.reference,
    required this.notes,
  });

  final String categoryId;
  final String description;
  final double amount;
  final double taxAmount;
  final String paymentMethod;
  final String reference;
  final String notes;
}

class _SupplierExpenseDialog extends StatefulWidget {
  const _SupplierExpenseDialog({
    required this.supplierName,
    required this.categories,
  });

  final String supplierName;
  final List<ExpenseCategory> categories;

  @override
  State<_SupplierExpenseDialog> createState() => _SupplierExpenseDialogState();
}

class _SupplierExpenseDialogState extends State<_SupplierExpenseDialog> {
  late String _categoryId;
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _tax = TextEditingController(text: '0');
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  String _method = 'cash';
  String? _error;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categories.first.id;
    _description.text = 'Expense - ${widget.supplierName}';
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _tax.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final tax = double.tryParse(_tax.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Amount must be greater than zero.');
      return;
    }
    if (tax < 0) {
      setState(() => _error = 'Tax amount cannot be negative.');
      return;
    }
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Description is required.');
      return;
    }

    Navigator.pop(
      context,
      _SupplierExpenseDraft(
        categoryId: _categoryId,
        description: _description.text.trim(),
        amount: amount,
        taxAmount: tax,
        paymentMethod: _method,
        reference: _reference.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Add expense - ${widget.supplierName}'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.categories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  setState(() => _categoryId = value ?? _categoryId),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tax,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Tax amount'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _method = value ?? _method),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Reference'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Add Expense')),
    ],
  );
}

class _PartyPane extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final double amount;
  final String Function(double) money;
  final List<PartyPendingSummary> rows;
  final void Function(PartyPendingSummary) onOpen;
  final void Function(PartyPendingSummary)? onPayment;
  final void Function(PartyPendingSummary)? onExpense;

  const _PartyPane({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.amount,
    required this.money,
    required this.rows,
    required this.onOpen,
    this.onPayment,
    this.onExpense,
  });

  String _d(DateTime? value) {
    if (value == null) return 'No due date';
    return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: scheme.surfaceContainerHighest.withValues(alpha: .45),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: scheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  money(amount),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            color: scheme.surfaceContainerHighest.withValues(alpha: .20),
            child: const Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'Party',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Open / Due',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Balance',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(
                  width: 174,
                  child: Text(
                    'Actions',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('Nothing pending.'))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final customer = row.partyType == 'customer';
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onOpen(row),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 50),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Row(
                                    children: [
                                      Icon(
                                        customer
                                            ? Icons.person_outline
                                            : Icons.local_shipping_outlined,
                                        size: 16,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              row.partyName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              customer
                                                  ? 'Sales ${money(row.salesOutstanding)} | Loans ${money(row.loanOutstanding)}'
                                                  : 'Purchases ${money(row.purchaseOutstanding)} | Bills ${money(row.invoiceOutstanding)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${row.documentCount} open',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        _d(row.nextDueDate),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: row.overdue > .005
                                              ? scheme.error
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        money(row.balance),
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      if (row.overdue > .005)
                                        Text(
                                          'Overdue ${money(row.overdue)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: scheme.error,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 174,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: onPayment == null
                                            ? null
                                            : () => onPayment!(row),
                                        child: Text(
                                          customer ? 'Receive' : 'Pay',
                                        ),
                                      ),
                                      if (!customer)
                                        IconButton(
                                          tooltip: 'Add expense',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: onExpense == null
                                              ? null
                                              : () => onExpense!(row),
                                          icon: const Icon(
                                            Icons.receipt_long_outlined,
                                            size: 17,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: 'View account',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => onOpen(row),
                                        icon: const Icon(
                                          Icons.chevron_right,
                                          size: 17,
                                        ),
                                      ),
                                    ],
                                  ),
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

class _PartyPaymentDetailScreen extends StatefulWidget {
  final ClientSession session;
  final PartyPendingSummary summary;
  final PaymentCenterService service;

  const _PartyPaymentDetailScreen({
    required this.session,
    required this.summary,
    required this.service,
  });

  @override
  State<_PartyPaymentDetailScreen> createState() =>
      _PartyPaymentDetailScreenState();
}

class _PartyPaymentDetailScreenState extends State<_PartyPaymentDetailScreen> {
  late Future<PartyPaymentDetail> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.service.detail(
      widget.session,
      partyType: widget.summary.partyType,
      partyId: widget.summary.partyId,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  String _m(double v) => widget.session.currencyCode == 'INR'
      ? 'INR ${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';

  String _d(DateTime? value) {
    if (value == null) return '—';
    return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
  }

  String _label(String value) => value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  Future<void> _openDocument(PartyOpenDocument document) async {
    if (document.sourceType == 'sale') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SaleDetailScreen(
            session: widget.session,
            saleId: document.sourceId,
          ),
        ),
      );
    } else if (document.sourceType == 'purchase') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseDetailScreen(
            session: widget.session,
            purchaseId: document.sourceId,
          ),
        ),
      );
    }
    if (mounted) await _refresh();
  }

  void _openStatement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PartyStatementScreen(
          session: widget.session,
          partyId: widget.summary.partyId,
          customer: widget.summary.partyType == 'customer',
          title: '${widget.summary.partyName} Statement',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.summary.partyName),
      actions: [
        TextButton.icon(
          onPressed: _openStatement,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Statement'),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: FutureBuilder<PartyPaymentDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: SelectableText(snapshot.error.toString()));
        }
        final data = snapshot.data!;
        final party = data.party;
        final isCustomer = widget.summary.partyType == 'customer';
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricCard(
                    label: isCustomer ? 'Total To Receive' : 'Net To Pay',
                    value: _m(data.netOutstanding),
                    icon: isCustomer ? Icons.call_received : Icons.call_made,
                  ),
                  _MetricCard(
                    label: 'Gross Outstanding',
                    value: _m(data.grossOutstanding),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  _MetricCard(
                    label: 'Overdue',
                    value: _m(data.overdue),
                    icon: Icons.warning_amber_rounded,
                    danger: data.overdue > .005,
                  ),
                  if (!isCustomer && data.creditBalance > .005)
                    _MetricCard(
                      label: 'Supplier Credit',
                      value: _m(data.creditBalance),
                      icon: Icons.savings_outlined,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      _Info(
                        label: 'ID',
                        value: party['tracking_code']?.toString() ?? '',
                      ),
                      _Info(
                        label: 'Phone',
                        value: party['phone']?.toString() ?? '',
                      ),
                      _Info(
                        label: 'Email',
                        value: party['email']?.toString() ?? '',
                      ),
                      _Info(
                        label: 'Tax / GST',
                        value: party['tax_number']?.toString() ?? '',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Open Documents'),
                          Tab(text: 'Recent Payments'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _documents(data.documents),
                            _payments(data.recentPayments),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _documents(List<PartyOpenDocument> documents) {
    if (documents.isEmpty) {
      return const Center(child: Text('No open documents.'));
    }
    return ListView.separated(
      itemCount: documents.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final document = documents[index];
        final extra = document.extra;
        String detail;
        if (document.sourceType == 'loan') {
          detail =
              'Principal ${_m(_num(extra['principal_outstanding']))} • '
              'Interest ${_m(_num(extra['interest_outstanding']))} • '
              'Penalty ${_m(_num(extra['penalty_outstanding']))} • '
              '${_num(extra['interest_rate']).toStringAsFixed(2)}% ${_label(extra['rate_type']?.toString() ?? '')}';
        } else if (document.sourceType == 'purchase_invoice') {
          final supplierInvoice =
              extra['supplier_invoice_number']?.toString() ?? '';
          detail = supplierInvoice.isEmpty
              ? 'Purchasing V2 invoice'
              : 'Supplier invoice: $supplierInvoice';
        } else {
          detail = 'Total ${_m(document.total)} • Paid ${_m(document.paid)}';
        }
        return Card(
          child: ListTile(
            leading: Icon(switch (document.sourceType) {
              'sale' => Icons.receipt_long_outlined,
              'loan' => Icons.account_balance_outlined,
              'purchase' => Icons.shopping_cart_outlined,
              _ => Icons.description_outlined,
            }),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_label(document.sourceType)} • ${document.reference}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _m(document.balance),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: document.overdue
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detail),
                  Text(
                    '${document.locationName} • Date ${_d(document.date)} • Due ${_d(document.dueDate)} • ${_label(document.status)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            trailing:
                document.sourceType == 'sale' ||
                    document.sourceType == 'purchase'
                ? OutlinedButton.icon(
                    onPressed: () => _openDocument(document),
                    icon: const Icon(Icons.open_in_new, size: 17),
                    label: const Text('View'),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _payments(List<PartyPaymentActivity> payments) {
    if (payments.isEmpty) {
      return const Center(child: Text('No payment history in this scope.'));
    }
    return ListView.separated(
      itemCount: payments.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final payment = payments[index];
        return ListTile(
          leading: const Icon(Icons.payments_outlined),
          title: Text(
            payment.paymentNumber.isEmpty
                ? _label(payment.paymentType)
                : payment.paymentNumber,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${_d(payment.date)} • ${_label(payment.paymentMethod)}'
            '${payment.reference.isEmpty ? '' : ' • ${payment.reference}'}'
            '${payment.locationName.isEmpty ? '' : ' • ${payment.locationName}'}',
          ),
          trailing: Text(
            _m(payment.amount),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );
      },
    );
  }

  double _num(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              icon,
              color: danger ? Theme.of(context).colorScheme.error : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: danger
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value.trim().isEmpty ? '—' : value),
      ],
    ),
  );
}
