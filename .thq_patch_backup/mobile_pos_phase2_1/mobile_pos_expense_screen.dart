import 'package:flutter/material.dart';

import '../models/pos_session.dart';
import '../services/mobile_pos_expense_service.dart';

class MobilePosExpenseScreen extends StatefulWidget {
  final PosSession session;
  final bool offlineMode;

  const MobilePosExpenseScreen({
    super.key,
    required this.session,
    required this.offlineMode,
  });

  @override
  State<MobilePosExpenseScreen> createState() => _MobilePosExpenseScreenState();
}

class _MobilePosExpenseScreenState extends State<MobilePosExpenseScreen> {
  final MobilePosExpenseService _service = MobilePosExpenseService();
  final TextEditingController _payee = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _tax = TextEditingController(text: '0');
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<MobileExpenseCategory> _categories = const [];
  String? _categoryId;
  String _paymentMethod = 'cash';
  DateTime _expenseDate = DateTime.now();

  bool get _moduleBlocked =>
      widget.session.allowedModules.isNotEmpty &&
      !widget.session.hasDeviceModule('expenses');

  double get _base => (double.tryParse(_amount.text.trim()) ?? 0) +
      (double.tryParse(_tax.text.trim()) ?? 0);
  double get _roundOff {
    if (_base <= 0) return 0;
    final delta = _base.roundToDouble() - _base;
    return delta.abs() < 0.000001 ? 0 : delta;
  }
  double get _total => _base + _roundOff;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _payee.dispose();
    _description.dispose();
    _amount.dispose();
    _tax.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!widget.offlineMode && !_moduleBlocked) {
        _categories = await _service.categories(widget.session);
        if (_categoryId == null && _categories.isNotEmpty) {
          _categoryId = _categories.first.id;
        }
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(double value) => widget.session.currencyCode == 'INR'
      ? '₹${value.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _expenseDate = picked);
  }

  Future<void> _post() async {
    if (widget.offlineMode) {
      setState(() => _error =
          'Expense posting is online-only because accounting and tax-mode checks must complete atomically.');
      return;
    }
    if (_moduleBlocked) {
      setState(() => _error =
          'This POS terminal is not enabled for Expenses. Enable Expenses for this terminal in Admin.');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = 'Select an expense category.');
      return;
    }
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Description is required.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an expense description.')),
      );
      return;
    }
    final amount = double.tryParse(_amount.text.trim());
    final tax = double.tryParse(_tax.text.trim()) ?? 0;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Expense amount must be greater than zero.');
      return;
    }
    if (tax < 0) {
      setState(() => _error = 'Tax cannot be negative.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _service.create(
        session: widget.session,
        categoryId: _categoryId!,
        expenseDate: _expenseDate,
        payee: _payee.text,
        description: _description.text,
        amount: amount,
        taxAmount: tax,
        roundOff: _roundOff,
        paymentMethod: _paymentMethod,
        referenceNumber: _reference.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      final number = result['invoice_number']?.toString() ??
          result['expense_number']?.toString() ??
          'Expense';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$number posted with verified accounting.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        final message = error.toString();
        setState(() => _error = message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Expense not posted: $message')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final blocked = widget.offlineMode || _moduleBlocked;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense'),
        actions: [
          IconButton(
            tooltip: 'Refresh categories',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (blocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: scheme.errorContainer,
                child: Text(
                  widget.offlineMode
                      ? 'Expenses require an online accounting/tax-mode commit. They are not placed in the offline sales queue.'
                      : 'Expenses are disabled for this POS terminal. Enable the Expenses module for the device in Admin.',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                color: scheme.errorContainer.withValues(alpha: .65),
                child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'New Expense',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category *',
                          prefixIcon: Icon(Icons.category_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: _categories
                            .map(
                              (row) => DropdownMenuItem<String>(
                                value: row.id,
                                child: Text(row.name),
                              ),
                            )
                            .toList(),
                        onChanged: blocked || _saving
                            ? null
                            : (value) => setState(() => _categoryId = value),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: blocked || _saving ? null : _pickDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text('Expense Date  ${_date(_expenseDate)}'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _payee,
                        enabled: !blocked && !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Payee',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _description,
                        enabled: !blocked && !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Description *',
                          prefixIcon: Icon(Icons.notes_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _amount,
                              enabled: !blocked && !_saving,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Amount *',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _tax,
                              enabled: !blocked && !_saving,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Tax Amount',
                                helperText: 'Use 0 for non-GST',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Payment Method',
                          prefixIcon: Icon(Icons.payments_outlined),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Cash')),
                          DropdownMenuItem(value: 'card', child: Text('Card')),
                          DropdownMenuItem(value: 'upi', child: Text('UPI')),
                          DropdownMenuItem(value: 'bank', child: Text('Bank')),
                          DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                          DropdownMenuItem(value: 'other', child: Text('Other')),
                        ],
                        onChanged: blocked || _saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _paymentMethod = value);
                                }
                              },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _reference,
                        enabled: !blocked && !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Reference Number',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notes,
                        enabled: !blocked && !_saving,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            _row('Amount + Tax', _money(_base)),
                            _row('Automatic Round Off', _money(_roundOff)),
                            const Divider(),
                            _row('Total', _money(_total), strong: true),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: blocked || _saving ? null : _post,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_saving ? 'Posting...' : 'Post Expense'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}
