import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/payment_pending.dart';
import '../services/payment_center_service.dart';

class PartySettlementScreen extends StatefulWidget {
  final ClientSession session;
  final PaymentCenterService service;

  const PartySettlementScreen({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  State<PartySettlementScreen> createState() => _PartySettlementScreenState();
}

class _PartySettlementScreenState extends State<PartySettlementScreen> {
  final _query = TextEditingController();
  late Future<PendingPaymentsData> _future;
  bool _customers = true;
  bool _busy = false;

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
    _future = widget.service.load(widget.session, query: _query.text.trim());
  }

  Future<void> _refresh() async {
    setState(_load);
    await _future;
  }

  String _m(double v) => widget.session.currencyCode == 'INR'
      ? 'INR ${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';

  Future<void> _receiveCustomer(PartyPendingSummary row) async {
    if (_busy || row.salesOutstanding <= .005) {
      return;
    }
    final draft = await showThqDialog<_PaymentDraft>(
      context: context,
      builder: (_) => _PaymentDialog(
        title: 'Receive from ${row.partyName}',
        maximum: row.salesOutstanding,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.receiveCustomerPayment(
        widget.session,
        customerId: row.partyId,
        amount: draft.amount,
        paymentMethod: draft.method,
        referenceNumber: draft.reference,
        notes: draft.notes,
      );
      if (!mounted) {
        return;
      }
      ThqNotify.success(context, 'Customer payment recorded.');
      await _refresh();
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  double _supplierTrade(PartyPendingSummary row) {
    final gross = row.purchaseOutstanding + row.invoiceOutstanding;
    return gross > row.creditBalance ? gross - row.creditBalance : 0;
  }

  Future<void> _paySupplier(PartyPendingSummary row) async {
    final trade = _supplierTrade(row);
    if (_busy || trade <= .005) {
      return;
    }
    final draft = await showThqDialog<_PaymentDraft>(
      context: context,
      builder: (_) =>
          _PaymentDialog(title: 'Pay ${row.partyName}', maximum: trade),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.paySupplier(
        widget.session,
        supplierId: row.partyId,
        amount: draft.amount,
        paymentMethod: draft.method,
        referenceNumber: draft.reference,
        notes: draft.notes,
      );
      if (!mounted) {
        return;
      }
      ThqNotify.success(context, 'Supplier payment recorded.');
      await _refresh();
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _close(PartyPendingSummary row) async {
    final maximum = row.partyType == 'customer'
        ? row.salesOutstanding
        : _supplierTrade(row);
    if (_busy || maximum <= .005) {
      return;
    }
    final draft = await showThqDialog<_SettlementDraft>(
      context: context,
      builder: (_) =>
          _SettlementDialog(partyName: row.partyName, maximum: maximum),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.closeOutstanding(
        widget.session,
        partyType: row.partyType,
        partyId: row.partyId,
        adjustmentType: draft.type,
        amount: draft.amount,
        reason: draft.reason,
      );
      if (!mounted) {
        return;
      }
      ThqNotify.success(
        context,
        draft.type == 'discount'
            ? 'Outstanding discount posted.'
            : 'Outstanding write-off posted.',
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Outstanding Settlement'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<PendingPaymentsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: SelectableText(snapshot.error.toString()));
        }
        final data = snapshot.data!;
        final rows = _customers ? data.receivables : data.payables;
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Discount and Write-off are financial settlement adjustments only. Original invoice and GST values remain unchanged. Customer and supplier loan balances are excluded from this action.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          label: Text('Customers'),
                          icon: Icon(Icons.people_outline),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text('Suppliers'),
                          icon: Icon(Icons.local_shipping_outlined),
                        ),
                      ],
                      selected: {_customers},
                      onSelectionChanged: _busy
                          ? null
                          : (v) => setState(() => _customers = v.first),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _query,
                      onSubmitted: (_) => _refresh(),
                      decoration: InputDecoration(
                        hintText: 'Search party',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          onPressed: () {
                            _query.clear();
                            _refresh();
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('Nothing outstanding.'))
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final customer = row.partyType == 'customer';
                          final closable = customer
                              ? row.salesOutstanding
                              : _supplierTrade(row);
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      customer
                                          ? Icons.person_outline
                                          : Icons.local_shipping_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          row.partyName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          customer
                                              ? 'Sales ${_m(row.salesOutstanding)}${row.loanOutstanding > .005 ? ' • Loans ${_m(row.loanOutstanding)} (separate)' : ''}'
                                              : 'Purchases ${_m(row.purchaseOutstanding)} • Invoices ${_m(row.invoiceOutstanding)}${row.creditBalance > .005 ? ' • Credit ${_m(row.creditBalance)}' : ''}${row.loanOutstanding > .005 ? ' • Loans ${_m(row.loanOutstanding)} (separate)' : ''}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _m(row.balance),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (customer)
                                    FilledButton.icon(
                                      onPressed:
                                          _busy || row.salesOutstanding <= .005
                                          ? null
                                          : () => _receiveCustomer(row),
                                      icon: const Icon(Icons.call_received),
                                      label: const Text('Receive'),
                                    )
                                  else
                                    FilledButton.icon(
                                      onPressed:
                                          _busy || _supplierTrade(row) <= .005
                                          ? null
                                          : () => _paySupplier(row),
                                      icon: const Icon(Icons.payments_outlined),
                                      label: const Text('Pay'),
                                    ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: _busy || closable <= .005
                                        ? null
                                        : () => _close(row),
                                    icon: const Icon(Icons.rule),
                                    label: const Text('Close'),
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
        );
      },
    ),
  );
}

class _PaymentDraft {
  final double amount;
  final String method;
  final String reference;
  final String notes;
  const _PaymentDraft(this.amount, this.method, this.reference, this.notes);
}

class _PaymentDialog extends StatefulWidget {
  final String title;
  final double maximum;
  const _PaymentDialog({required this.title, required this.maximum});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amount;
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'cash';
  String? _error;
  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.maximum.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final a = double.tryParse(_amount.text.trim()) ?? 0;
    if (a <= 0 || a > widget.maximum + .005) {
      setState(
        () => _error =
            'Enter an amount up to ${widget.maximum.toStringAsFixed(2)}.',
      );
      return;
    }
    Navigator.pop(
      context,
      _PaymentDraft(a, _method, _reference.text.trim(), _notes.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              helperText: 'Maximum ${widget.maximum.toStringAsFixed(2)}',
            ),
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
            onChanged: (v) => setState(() => _method = v ?? _method),
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
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      FilledButton(onPressed: _submit, child: const Text('Pay')),
    ],
  );
}

class _SettlementDraft {
  final String type;
  final double amount;
  final String reason;
  const _SettlementDraft(this.type, this.amount, this.reason);
}

class _SettlementDialog extends StatefulWidget {
  final String partyName;
  final double maximum;
  const _SettlementDialog({required this.partyName, required this.maximum});
  @override
  State<_SettlementDialog> createState() => _SettlementDialogState();
}

class _SettlementDialogState extends State<_SettlementDialog> {
  late final TextEditingController _amount;
  final _reason = TextEditingController();
  String _type = 'discount';
  String? _error;
  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.maximum.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final a = double.tryParse(_amount.text.trim()) ?? 0;
    final r = _reason.text.trim();
    if (a <= 0 || a > widget.maximum + .005) {
      setState(
        () => _error =
            'Enter an amount up to ${widget.maximum.toStringAsFixed(2)}.',
      );
      return;
    }
    if (r.isEmpty) {
      setState(() => _error = 'Reason is required.');
      return;
    }
    Navigator.pop(context, _SettlementDraft(_type, a, r));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Close ${widget.partyName} outstanding'),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Adjustment'),
            items: const [
              DropdownMenuItem(value: 'discount', child: Text('Discount')),
              DropdownMenuItem(value: 'write_off', child: Text('Write-off')),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              helperText: 'Maximum ${widget.maximum.toStringAsFixed(2)}',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason *'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      FilledButton(onPressed: _submit, child: const Text('Post adjustment')),
    ],
  );
}
