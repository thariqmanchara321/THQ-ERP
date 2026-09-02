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
  late Future<Map<String, dynamic>> _summary;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
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
    _future = _service.getExpenses(
      tenantId: widget.session.business.id,
      from: _from,
      to: _to,
    );
    _summary = _service.getExpenseSummary(
      tenantId: widget.session.business.id,
      from: _from,
      to: _to,
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

  Future<void> _showTracking(Expense expense) async {
    try {
      final detail = await _service.getExpenseDetail(
        tenantId: widget.session.business.id,
        expenseId: expense.id,
      );
      if (!mounted) return;
      final origin = detail['origin'] is Map
          ? Map<String, dynamic>.from(detail['origin'] as Map)
          : <String, dynamic>{};
      final history = detail['history'] is List
          ? detail['history'] as List
          : const [];
      final journals = detail['journals'] is List
          ? detail['journals'] as List
          : const [];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Expense Tracking • ${expense.number}'),
          content: SizedBox(
            width: 760,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  '${expense.categoryName} • ${_d(expense.expenseDate)} • ${_m(expense.totalAmount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Store: ${origin['location_name'] ?? '—'} • '
                  'Device: ${origin['device_name'] ?? origin['device_code'] ?? '—'}',
                ),
                const Divider(height: 24),
                const Text(
                  'Accounting journals',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                if (journals.isEmpty)
                  const Text('No journal evidence found.')
                else
                  ...journals.map((row) {
                    final m = Map<String, dynamic>.from(row as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(
                        '${m['entry_number'] ?? 'Journal'} • ${m['status'] ?? ''}',
                      ),
                      subtitle: Text(
                        '${m['entry_date'] ?? ''} • ${m['description'] ?? ''}',
                      ),
                    );
                  }),
                const Divider(height: 24),
                const Text(
                  'Change history',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                if (history.isEmpty)
                  const Text('No tracked edits after the tracking upgrade.')
                else
                  ...history.map((row) {
                    final m = Map<String, dynamic>.from(row as Map);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history),
                      title: Text(
                        '${m['action'] ?? 'change'} • ${m['changed_at'] ?? ''}',
                      ),
                      subtitle: Text('${m['reason'] ?? 'No reason recorded'}'),
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _pickExpensePeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
      _load();
    });
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expenses',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 5),
                  Text('Operating expenses and cash payments'),
                ],
              ),
            ),
            if (_canManage)
              FilledButton.icon(
                onPressed: _newExpense,
                icon: const Icon(Icons.add),
                label: const Text('New Expense'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        FutureBuilder<Map<String, dynamic>>(
          future: _summary,
          builder: (context, snapshot) {
            final s = snapshot.data ?? const <String, dynamic>{};
            double n(dynamic v) =>
                v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text('${_d(_from)} — ${_d(_to)}'),
                  onPressed: _pickExpensePeriod,
                ),
                Chip(label: Text('Expenses ${s['expense_count'] ?? 0}')),
                Chip(label: Text('Total ${_m(n(s['total']))}')),
                Chip(label: Text('Tax ${_m(n(s['tax']))}')),
                Chip(label: Text('Before tax ${_m(n(s['net_before_tax']))}')),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: FutureBuilder<List<Expense>>(
            future: _future,
            builder: (context, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) {
                return Center(
                  child: Text(s.error.toString(), textAlign: TextAlign.center),
                );
              }
              final rows = s.data ?? [];
              if (rows.isEmpty) {
                return const Center(child: Text('No expenses recorded yet.'));
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final e = rows[i];
                    return InkWell(
                      onTap: () => _showTracking(e),
                      onLongPress: _canEdit ? () => _editExpense(e) : null,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.number,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _d(e.expenseDate),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.categoryName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    e.payee.isEmpty ? e.description : e.payee,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(e.paymentMethod.toUpperCase()),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _m(e.totalAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Chip(label: Text(e.status.toUpperCase())),
                            IconButton(
                              tooltip: 'Tracking & journal',
                              onPressed: () => _showTracking(e),
                              icon: const Icon(Icons.history, size: 18),
                            ),
                            if (_canEdit)
                              IconButton(
                                tooltip: 'Edit expense',
                                onPressed: () => _editExpense(e),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
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
      _notes = TextEditingController(),
      _reason = TextEditingController();
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
          reason: _reason.text,
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
    for (final c in [
      _payee,
      _desc,
      _amount,
      _tax,
      _round,
      _ref,
      _notes,
      _reason,
    ]) {
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
              if (widget.expense != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason for edit *',
                    hintText: 'Required for the audit trail',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Edit reason required'
                      : null,
                ),
              ],
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
