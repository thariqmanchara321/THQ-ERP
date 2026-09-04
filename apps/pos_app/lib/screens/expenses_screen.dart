import 'package:flutter/material.dart';
import '../models/client_session.dart';
import '../models/expense.dart';
import '../services/expense_service.dart';

class ExpensesScreen extends StatefulWidget {
  final ClientSession session;
  const ExpensesScreen({super.key, required this.session});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _service = ExpenseService();
  late Future<List<Expense>> _future;
  bool get _canManage => widget.session.hasPermission('expenses.manage');
  bool get _canEdit =>
      widget.session.hasPermission('expenses.edit') ||
      _canManage ||
      widget.session.hasRole('owner');
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final today = DateTime.now();
    _future = _service.getExpenses(
      tenantId: widget.session.business.id,
      from: today,
      to: today,
    );
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  String _m(double v) => widget.session.currencyCode == 'INR'
      ? '₹${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';
  String _d(DateTime v) =>
      '${v.day.toString().padLeft(2, '0')}-${v.month.toString().padLeft(2, '0')}-${v.year}';
  Future<void> _newExpense() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExpenseDialog(session: widget.session),
    );
    if (ok == true && mounted) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense recorded successfully.')),
        );
      }
    }
  }

  Future<void> _editExpense(Expense expense) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExpenseDialog(session: widget.session, expense: expense),
    );
    if (ok == true && mounted) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense updated successfully.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Expenses',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Today | Operating expenses and cash payments',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
                if (_canManage) ...[
                  const SizedBox(width: 3),
                  FilledButton.icon(
                    onPressed: _newExpense,
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('New Expense'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: FutureBuilder<List<Expense>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final rows = snapshot.data ?? [];
                if (rows.isEmpty) {
                  return const Center(
                    child: Text('No expenses recorded today.'),
                  );
                }

                final total = rows.fold<double>(
                  0,
                  (sum, row) => sum + row.totalAmount,
                );
                final tax = rows.fold<double>(
                  0,
                  (sum, row) => sum + row.taxAmount,
                );
                final beforeTax = rows.fold<double>(
                  0,
                  (sum, row) => sum + row.amount,
                );

                return Column(
                  children: [
                    SizedBox(
                      height: 54,
                      child: Row(
                        children: [
                          Expanded(
                            child: _expenseMetric(
                              'Expenses',
                              '${rows.length}',
                              Icons.receipt_long_outlined,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _expenseMetric(
                              'Before Tax',
                              _m(beforeTax),
                              Icons.payments_outlined,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _expenseMetric(
                              'Tax',
                              _m(tax),
                              Icons.percent_outlined,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _expenseMetric(
                              'Total',
                              _m(total),
                              Icons.account_balance_wallet_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              color: scheme.surfaceContainerHighest.withValues(
                                alpha: .45,
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Expense',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Category / Payee',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Payment',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Amount',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 76,
                                    child: Text(
                                      'Status',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 32),
                                ],
                              ),
                            ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: _refresh,
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) {
                                    final expense = rows[index];

                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: _canEdit
                                            ? () => _editExpense(expense)
                                            : null,
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minHeight: 46,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 4,
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
                                                flex: 2,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      expense.number,
                                                      maxLines: 1,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    Text(
                                                      _d(expense.expenseDate),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      expense.categoryName,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    Text(
                                                      expense.payee.isEmpty
                                                          ? expense.description
                                                          : expense.payee,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  expense.paymentMethod
                                                      .replaceAll('_', ' ')
                                                      .toUpperCase(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _m(expense.totalAmount),
                                                  textAlign: TextAlign.right,
                                                  maxLines: 1,
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 76,
                                                child: Text(
                                                  expense.status.toUpperCase(),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 32,
                                                child: _canEdit
                                                    ? const Icon(
                                                        Icons.edit_outlined,
                                                        size: 14,
                                                      )
                                                    : null,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _expenseMetric(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
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
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  final ClientSession session;
  final Expense? expense;
  const _ExpenseDialog({required this.session, this.expense});
  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _service = ExpenseService();
  final _form = GlobalKey<FormState>();
  final _payee = TextEditingController(),
      _desc = TextEditingController(),
      _amount = TextEditingController(),
      _tax = TextEditingController(text: '0'),
      _round = TextEditingController(text: '0'),
      _ref = TextEditingController(),
      _notes = TextEditingController();
  late Future<List<ExpenseCategory>> _cats;
  String? _cat;
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    if (e != null) {
      _payee.text = e.payee;
      _desc.text = e.description;
      _amount.text = e.amount.toStringAsFixed(2);
      _tax.text = e.taxAmount.toStringAsFixed(2);
      _round.text = (e.totalAmount - e.amount - e.taxAmount).toStringAsFixed(2);
      _ref.text = e.referenceNumber ?? '';
      _notes.text = e.notes ?? '';
      _cat = e.categoryId;
      _method = e.paymentMethod;
      _date = e.expenseDate;
    }
    _cats = _service.getCategories(tenantId: widget.session.business.id);
  }

  double _n(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _cat == null) return;
    if (_n(_round).abs() > 1.000001) {
      setState(() => _error = 'Round off must be between -1.00 and 1.00.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.expense == null) {
        await _service.createExpense(
          tenantId: widget.session.business.id,
          categoryId: _cat!,
          expenseDate: _date,
          payee: _payee.text,
          description: _desc.text,
          amount: _n(_amount),
          taxAmount: _n(_tax),
          roundOff: _n(_round),
          paymentMethod: _method,
          referenceNumber: _ref.text,
          notes: _notes.text,
        );
      } else {
        await _service.updateExpense(
          tenantId: widget.session.business.id,
          expenseId: widget.expense!.id,
          categoryId: _cat!,
          expenseDate: _date,
          payee: _payee.text,
          description: _desc.text,
          amount: _n(_amount),
          taxAmount: _n(_tax),
          roundOff: _n(_round),
          paymentMethod: _method,
          referenceNumber: _ref.text,
          notes: _notes.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_payee, _desc, _amount, _tax, _round, _ref, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.expense == null ? 'New Expense' : 'Edit ${widget.expense!.number}',
    ),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<List<ExpenseCategory>>(
                future: _cats,
                builder: (context, s) {
                  final rows = s.data ?? [];
                  if (_cat == null && rows.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _cat == null) {
                        setState(() => _cat = rows.first.id);
                      }
                    });
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: _cat,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: rows
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _cat = v),
                    validator: (v) => v == null ? 'Select category' : null,
                  );
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expense Date'),
                subtitle: Text('${_date.day}-${_date.month}-${_date.year}'),
                trailing: IconButton(
                  onPressed: _pick,
                  icon: const Icon(Icons.date_range),
                ),
              ),
              TextFormField(
                controller: _payee,
                decoration: const InputDecoration(
                  labelText: 'Payee',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Description required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (double.tryParse((v ?? '').trim()) ?? 0) <= 0
                          ? 'Enter amount'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _tax,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tax amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _round,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Round Off',
                        helperText: 'Post-tax adjustment (-1.00 to 1.00)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      final before = _n(_amount) + _n(_tax);
                      final delta = before.roundToDouble() - before;
                      setState(
                        () => _round.text = delta.abs() < 0.000001
                            ? '0.00'
                            : delta.toStringAsFixed(2),
                      );
                    },
                    icon: const Icon(Icons.exposure_zero),
                    label: const Text('Round Total'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  border: OutlineInputBorder(),
                ),
                items: const ['cash', 'card', 'bank_transfer', 'upi', 'other']
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v.replaceAll('_', ' ').toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _method = v ?? 'cash'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ref,
                decoration: const InputDecoration(
                  labelText: 'Reference',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save Expense'),
      ),
    ],
  );
}
