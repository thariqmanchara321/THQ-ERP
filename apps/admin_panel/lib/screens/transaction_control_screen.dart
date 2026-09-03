import 'package:flutter/material.dart';

import '../models/business.dart';
import '../services/business_service.dart';
import '../services/transaction_control_service.dart';
import '../widgets/admin_home_button.dart';

class TransactionControlScreen extends StatefulWidget {
  const TransactionControlScreen({super.key});

  @override
  State<TransactionControlScreen> createState() =>
      _TransactionControlScreenState();
}

class _TransactionControlScreenState extends State<TransactionControlScreen> {
  final BusinessService _businessService = BusinessService();
  final TransactionControlService _service = TransactionControlService();
  final TextEditingController _search = TextEditingController();
  List<Business> _businesses = const [];
  String? _tenantId;
  DateTime? _from;
  DateTime? _to;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _bootstrap();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      _businesses = await _businessService.getBusinesses();
      _tenantId = _businesses.isEmpty ? null : _businesses.first.id;
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    final tenant = _tenantId;
    if (tenant == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.list(
        tenantId: tenant,
        from: _from,
        to: _to,
        query: _search.text,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(bool from) async {
    final date = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null) return;
    setState(() {
      if (from) {
        _from = date;
      } else {
        _to = date;
      }
    });
    await _load();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransactionEditDialog(
        tenantId: _tenantId!,
        row: row,
        service: _service,
      ),
    );
    if (changed == true) {
      await _load();
      _message(
        'Transaction corrected. Stock/accounting/audit links were reposted where required.',
      );
    }
  }

  Future<void> _void(Map<String, dynamic> row) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Void ${row['entity_type']} ${row['reference']}?'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This is a controlled accounting correction. Paid documents and documents with returns are blocked from direct voiding.',
              ),
              const SizedBox(height: 4),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Required reason'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Void safely'),
          ),
        ],
      ),
    );
    if (ok == true && reason.text.trim().isNotEmpty) {
      try {
        await _service.safeVoid(
          tenantId: _tenantId!,
          entityType: row['entity_type'].toString(),
          entityId: row['entity_id'].toString(),
          reason: reason.text,
        );
        await _load();
        _message(
          'Transaction voided and stock/accounting correction recorded.',
        );
      } catch (error) {
        _message(error.toString());
      }
    }
    reason.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _money(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return '₹${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _businesses.where((b) => b.id == _tenantId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 42,
        title: const Text('Transaction Control'),
        actions: const [AdminHomeButton()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cross-business Transaction Control',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              const Text(
                'Inspect store/terminal transactions and apply audited safe corrections without bypassing stock or accounting rules.',
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 300,
                    child: DropdownButtonFormField<String>(
                      initialValue: _tenantId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Business'),
                      items: _businesses
                          .map(
                            (b) => DropdownMenuItem(
                              value: b.id,
                              child: Text(
                                b.divisionName == null
                                    ? b.name
                                    : '${b.name} • ${b.divisionName}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) async {
                        setState(() => _tenantId = value);
                        await _load();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _search,
                      onSubmitted: (_) => _load(),
                      decoration: const InputDecoration(
                        labelText: 'Invoice / return / party / supplier bill',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(true),
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _from == null
                          ? 'From'
                          : '${_from!.day}/${_from!.month}/${_from!.year}',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pick(false),
                    icon: const Icon(Icons.event),
                    label: Text(
                      _to == null
                          ? 'To'
                          : '${_to!.day}/${_to!.month}/${_to!.year}',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Load'),
                  ),
                ],
              ),
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${selected.name} • ${selected.status.toUpperCase()} • ${selected.divisionRole ?? 'standalone'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(child: Text(_error!, textAlign: TextAlign.center))
                    : _rows.isEmpty
                    ? const Center(
                        child: Text('No transactions in this range.'),
                      )
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final row = _rows[index];
                          final status = row['status']?.toString() ?? '';
                          final type = row['entity_type']?.toString() ?? '';
                          final canVoid =
                              const {
                                'sale',
                                'purchase',
                                'expense',
                              }.contains(type) &&
                              status != 'void' &&
                              status != 'cancelled';
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 200,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            _TypeBadge(
                                              row['entity_type']?.toString() ??
                                                  '',
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                row['reference']?.toString() ??
                                                    '',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${row['entry_date'] ?? ''} • ${row['party'] ?? ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _Cell('Total', _money(row['total'])),
                                  _Cell('Paid', _money(row['paid'])),
                                  _Cell('Balance', _money(row['balance'])),
                                  _Cell(
                                    'Store',
                                    row['location_name']?.toString() ?? '—',
                                  ),
                                  _Cell(
                                    'Terminal',
                                    row['device_name']?.toString() ?? '—',
                                  ),
                                  Chip(
                                    label: Text(status.toUpperCase()),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () => _edit(row),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 17,
                                    ),
                                    label: const Text('Edit'),
                                  ),
                                  if (canVoid)
                                    OutlinedButton.icon(
                                      onPressed: () => _void(row),
                                      icon: const Icon(Icons.block, size: 17),
                                      label: const Text('Safe Void'),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  const _Cell(this.label, this.value);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge(this.type);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      type.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _TransactionEditDialog extends StatefulWidget {
  final String tenantId;
  final Map<String, dynamic> row;
  final TransactionControlService service;

  const _TransactionEditDialog({
    required this.tenantId,
    required this.row,
    required this.service,
  });

  @override
  State<_TransactionEditDialog> createState() => _TransactionEditDialogState();
}

class _TransactionEditDialogState extends State<_TransactionEditDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _detail = {};
  List<Map<String, dynamic>> _parties = const [];

  final _reason = TextEditingController();
  final _notes = TextEditingController();
  final _due = TextEditingController();
  final _supplierInvoice = TextEditingController();
  final _payee = TextEditingController();
  final _description = TextEditingController();
  final _expenseTotal = TextEditingController();
  final _expenseTax = TextEditingController();

  String? _partyId;
  String _expensePayment = 'cash';
  final List<_AdminItemEdit> _items = [];
  final List<_AdminPaymentEdit> _payments = [];

  String get _type => widget.row['entity_type']?.toString() ?? '';
  bool get _isReturn => _type == 'sales_return' || _type == 'purchase_return';
  bool get _isSaleLike => _type == 'sale' || _type == 'sales_return';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    _due.dispose();
    _supplierInvoice.dispose();
    _payee.dispose();
    _description.dispose();
    _expenseTotal.dispose();
    _expenseTax.dispose();
    for (final item in _items) {
      item.dispose();
    }
    for (final payment in _payments) {
      payment.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await widget.service.detail(
        tenantId: widget.tenantId,
        entityType: _type,
        entityId: widget.row['entity_id'].toString(),
      );
      final entity = detail['entity'] is Map
          ? Map<String, dynamic>.from(detail['entity'] as Map)
          : <String, dynamic>{};
      _detail = detail;

      if (_type == 'sale') _partyId = entity['customer_id']?.toString();
      if (_type == 'purchase') _partyId = entity['supplier_id']?.toString();
      _notes.text = _isReturn
          ? '${entity['reason'] ?? ''}'
          : '${entity['notes'] ?? ''}';
      _due.text = '${entity['due_date'] ?? ''}';
      _supplierInvoice.text = '${entity['supplier_invoice_number'] ?? ''}';
      _payee.text = '${entity['payee'] ?? ''}';
      _description.text = '${entity['description'] ?? ''}';
      _expenseTotal.text = '${entity['total_amount'] ?? ''}';
      _expenseTax.text = '${entity['tax_amount'] ?? ''}';
      _expensePayment = _normalizePayment(
        '${entity['payment_method'] ?? 'cash'}',
      );

      if (_type == 'sale' || _type == 'purchase') {
        _parties = await widget.service.parties(
          tenantId: widget.tenantId,
          partyType: _type == 'sale' ? 'customer' : 'supplier',
        );
      }
      if (_type == 'sale' || _type == 'purchase' || _isReturn) {
        for (final raw
            in (detail['items'] as List? ?? const []).whereType<Map>()) {
          _items.add(_AdminItemEdit(Map<String, dynamic>.from(raw), _type));
        }
      }
      if (_type == 'sale' || _type == 'purchase') {
        for (final raw
            in (detail['payments'] as List? ?? const []).whereType<Map>()) {
          _payments.add(_AdminPaymentEdit(Map<String, dynamic>.from(raw)));
        }
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _normalizePayment(String value) {
    final normalized = value.toLowerCase();
    if (normalized == 'bank_transfer') return 'bank';
    if (normalized == 'credit_card' || normalized == 'debit_card') {
      return 'card';
    }
    return const {'cash', 'upi', 'card', 'bank'}.contains(normalized)
        ? normalized
        : 'cash';
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'A correction reason is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final patch = <String, dynamic>{};
      if (_type == 'sale') {
        patch.addAll({
          'customer_id': _partyId,
          'due_date': _due.text.trim(),
          'notes': _notes.text.trim(),
          'items': _items.map((item) => item.toJson()).toList(),
        });
      } else if (_type == 'purchase') {
        patch.addAll({
          'supplier_id': _partyId,
          'supplier_invoice_number': _supplierInvoice.text.trim(),
          'due_date': _due.text.trim(),
          'notes': _notes.text.trim(),
          'items': _items.map((item) => item.toJson()).toList(),
        });
      } else if (_isReturn) {
        patch.addAll({
          'reason': _notes.text.trim(),
          'items': _items.map((item) => item.toJson()).toList(),
        });
      } else {
        patch.addAll({
          'payee': _payee.text.trim(),
          'description': _description.text.trim(),
          'total_amount': double.tryParse(_expenseTotal.text) ?? 0,
          'tax_amount': double.tryParse(_expenseTax.text) ?? 0,
          'payment_method': _expensePayment,
        });
      }

      if (_isReturn) {
        await widget.service.correctReturn(
          tenantId: widget.tenantId,
          entityType: _type,
          entityId: widget.row['entity_id'].toString(),
          patch: patch,
          reason: _reason.text,
        );
      } else {
        await widget.service.correct(
          tenantId: widget.tenantId,
          entityType: _type,
          entityId: widget.row['entity_id'].toString(),
          patch: patch,
          reason: _reason.text,
        );
      }

      for (final payment in _payments) {
        if (payment.changed) {
          await widget.service.correctPayment(
            tenantId: widget.tenantId,
            entityType: _type,
            paymentId: payment.id,
            paymentMethod: payment.method,
            referenceNumber: payment.reference.text,
            reason: _reason.text,
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final party = _detail['party'] is Map
        ? Map<String, dynamic>.from(_detail['party'] as Map)
        : <String, dynamic>{};
    final origin = _detail['origin'] is Map
        ? Map<String, dynamic>.from(_detail['origin'] as Map)
        : <String, dynamic>{};

    return AlertDialog(
      title: Text(
        'Correct ${_type.replaceAll('_', ' ').toUpperCase()} ${widget.row['reference'] ?? ''}',
      ),
      content: SizedBox(
        width: 900,
        height: 650,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _detail.isEmpty
            ? Center(child: Text(_error!))
            : Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isReturn
                          ? 'Protected return correction: quantity changes reverse/repost the return journal and adjust only the original store stock. THQ keeps before/after audit history.'
                          : 'Protected correction: THQ records before/after values and recalculates stock/accounting when quantities or values change. Returned documents block unsafe original-item edits.',
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          if (_type == 'sale' || _type == 'purchase') ...[
                            _partyField(),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _due,
                                    decoration: const InputDecoration(
                                      labelText: 'Due date YYYY-MM-DD',
                                    ),
                                  ),
                                ),
                                if (_type == 'purchase') ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _supplierInvoice,
                                      decoration: const InputDecoration(
                                        labelText: 'Supplier invoice',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _notes,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Notes',
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Items',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            ..._items.map(_itemRow),
                            if (_payments.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Payments',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              ..._payments.map(_paymentRow),
                            ],
                          ] else if (_isReturn) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Wrap(
                                spacing: 22,
                                runSpacing: 6,
                                children: [
                                  Text(
                                    '${_isSaleLike ? 'Customer' : 'Supplier'}: ${party['name'] ?? '—'}',
                                  ),
                                  Text(
                                    'Original: ${origin['source_number'] ?? '—'}',
                                  ),
                                  Text(
                                    'Store ID: ${origin['location_id'] ?? '—'}',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _notes,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Return reason / note',
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Returned Items • quantity correction only',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            ..._items.map(_itemRow),
                          ] else ...[
                            TextField(
                              controller: _payee,
                              decoration: const InputDecoration(
                                labelText: 'Payee',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _description,
                              decoration: const InputDecoration(
                                labelText: 'Description',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _expenseTotal,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Total',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _expenseTax,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Tax',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _expensePayment,
                              decoration: const InputDecoration(
                                labelText: 'Payment method',
                              ),
                              items: const ['cash', 'upi', 'card', 'bank']
                                  .map(
                                    (method) => DropdownMenuItem(
                                      value: method,
                                      child: Text(method.toUpperCase()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _expensePayment = value);
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: 5),
                          TextField(
                            controller: _reason,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Required audit reason *',
                            ),
                          ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(_saving ? 'Applying…' : 'Apply Audited Correction'),
        ),
      ],
    );
  }

  Widget _partyField() => DropdownButtonFormField<String>(
    initialValue: _parties.any((party) => party['id']?.toString() == _partyId)
        ? _partyId
        : null,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: _type == 'sale' ? 'Customer' : 'Supplier',
    ),
    items: _parties
        .map(
          (party) => DropdownMenuItem(
            value: party['id'].toString(),
            child: Text(
              '${party['name']} ${party['phone'] == null ? '' : '• ${party['phone']}'}',
            ),
          ),
        )
        .toList(),
    onChanged: (value) => setState(() => _partyId = value),
  );

  Widget _itemRow(_AdminItemEdit item) {
    if (_isReturn) {
      return Card(
        margin: const EdgeInsets.only(top: 5),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.raw['product_name'] ?? item.raw['variant_id'] ?? item.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${item.raw['sku'] ?? ''} • ${_isSaleLike ? 'Rate' : 'Cost'} ${item.price.text} • Tax ${item.tax.text}%',
                      style: const TextStyle(fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: item.qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Correct return qty',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(top: 5),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                '${item.raw['product_name'] ?? item.raw['variant_id'] ?? item.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: item.qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Qty',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: item.price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _type == 'sale' ? 'Rate' : 'Cost',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: item.discount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Disc',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: item.tax,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tax %',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentRow(_AdminPaymentEdit payment) => Card(
    margin: const EdgeInsets.only(top: 5),
    child: Padding(
      padding: const EdgeInsets.all(7),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '₹${payment.raw['amount'] ?? 0}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: payment.method,
              decoration: const InputDecoration(
                labelText: 'Method',
                isDense: true,
              ),
              items: const ['cash', 'upi', 'card', 'bank']
                  .map(
                    (method) => DropdownMenuItem(
                      value: method,
                      child: Text(method.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => payment.method = value);
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: payment.reference,
              decoration: const InputDecoration(
                labelText: 'Reference',
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AdminItemEdit {
  final Map<String, dynamic> raw;
  final String type;
  late final TextEditingController qty;
  late final TextEditingController price;
  late final TextEditingController discount;
  late final TextEditingController tax;

  _AdminItemEdit(this.raw, this.type) {
    final saleLike = type == 'sale' || type == 'sales_return';
    qty = TextEditingController(text: '${raw['quantity'] ?? ''}');
    price = TextEditingController(
      text: '${raw[saleLike ? 'unit_price' : 'unit_cost'] ?? ''}',
    );
    discount = TextEditingController(text: '${raw['discount_amount'] ?? 0}');
    tax = TextEditingController(text: '${raw['tax_rate'] ?? 0}');
  }

  String get id => raw['id'].toString();
  bool get isReturn => type == 'sales_return' || type == 'purchase_return';

  Map<String, dynamic> toJson() {
    if (isReturn) return {'item_id': id, 'quantity': qty.text};
    final saleLike = type == 'sale';
    return {
      'item_id': id,
      'quantity': qty.text,
      saleLike ? 'unit_price' : 'unit_cost': price.text,
      'discount_amount': discount.text,
      'tax_rate': tax.text,
    };
  }

  void dispose() {
    qty.dispose();
    price.dispose();
    discount.dispose();
    tax.dispose();
  }
}

class _AdminPaymentEdit {
  final Map<String, dynamic> raw;
  late String method;
  late final String originalMethod;
  late final String originalReference;
  late final TextEditingController reference;

  _AdminPaymentEdit(this.raw) {
    final source = '${raw['payment_method'] ?? 'cash'}'.toLowerCase();
    method = source == 'bank_transfer'
        ? 'bank'
        : (source == 'credit_card' || source == 'debit_card'
              ? 'card'
              : (const {'cash', 'upi', 'card', 'bank'}.contains(source)
                    ? source
                    : 'cash'));
    originalMethod = method;
    originalReference = '${raw['reference_number'] ?? ''}';
    reference = TextEditingController(text: originalReference);
  }

  String get id => raw['id'].toString();
  bool get changed =>
      method != originalMethod ||
      reference.text.trim() != originalReference.trim();
  void dispose() => reference.dispose();
}
