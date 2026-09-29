import 'package:flutter/material.dart';

import '../models/pos_session.dart';
import '../services/mobile_party_payment_service.dart';

class MobilePartyPaymentsScreen extends StatefulWidget {
  final PosSession session;

  const MobilePartyPaymentsScreen({super.key, required this.session});

  @override
  State<MobilePartyPaymentsScreen> createState() =>
      _MobilePartyPaymentsScreenState();
}

class _MobilePartyPaymentsScreenState extends State<MobilePartyPaymentsScreen> {
  final _service = MobilePartyPaymentService();
  final _search = TextEditingController();
  late Future<Map<String, dynamic>> _future;
  bool _customers = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = _service.summary(widget.session, query: _search.text.trim());
  }

  Future<void> _refresh() async {
    final next = _service.summary(widget.session, query: _search.text.trim());
    setState(() => _future = next);
    await next;
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> data) {
    final raw = data[_customers ? 'receivables' : 'payables'];
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  double _n(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  double _tradeOutstanding(Map<String, dynamic> row) {
    if (_customers) {
      return _n(row['sales_outstanding']);
    }
    final gross = _n(row['purchase_outstanding']) + _n(row['invoice_outstanding']);
    final credit = _n(row['credit_balance']);
    return gross > credit ? gross - credit : 0;
  }

  String _money(dynamic value) =>
      '${widget.session.currencyCode} ${_n(value).toStringAsFixed(2)}';

  Future<void> _recordPayment(Map<String, dynamic> row) async {
    if (_busy) {
      return;
    }
    final maximum = _tradeOutstanding(row);
    if (maximum <= .005) {
      _message('There is no trade outstanding to settle here. Loan balances remain in Loans.');
      return;
    }
    final name = row['party_name']?.toString() ??
        row[_customers ? 'customer_name' : 'supplier_name']?.toString() ??
        (_customers ? 'Customer' : 'Supplier');
    final draft = await showDialog<_PaymentDraft>(
      context: context,
      builder: (_) => _PaymentDialog(
        title: _customers ? 'Receive from $name' : 'Pay $name',
        actionLabel: _customers ? 'Receive' : 'Pay',
        maximumAmount: maximum,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      if (_customers) {
        await _service.receiveCustomerPayment(
          widget.session,
          customerId: row['party_id']?.toString() ?? '',
          amount: draft.amount,
          paymentMethod: draft.method,
          reference: draft.reference,
          notes: draft.notes,
        );
      } else {
        await _service.paySupplier(
          widget.session,
          supplierId: row['party_id']?.toString() ?? '',
          amount: draft.amount,
          paymentMethod: draft.method,
          reference: draft.reference,
          notes: draft.notes,
        );
      }
      if (!mounted) {
        return;
      }
      _message(_customers ? 'Customer payment recorded.' : 'Supplier payment recorded.');
      await _refresh();
    } catch (error) {
      if (mounted) {
        _message(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _close(Map<String, dynamic> row, String adjustmentType) async {
    if (_busy) {
      return;
    }
    final maximum = _tradeOutstanding(row);
    if (maximum <= .005) {
      _message('There is no trade outstanding eligible for this adjustment.');
      return;
    }
    final name = row['party_name']?.toString() ??
        row[_customers ? 'customer_name' : 'supplier_name']?.toString() ??
        (_customers ? 'Customer' : 'Supplier');
    final draft = await showDialog<_CloseDraft>(
      context: context,
      builder: (_) => _CloseDialog(
        partyName: name,
        adjustmentType: adjustmentType,
        maximumAmount: maximum,
        currencyCode: widget.session.currencyCode,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      await _service.closeOutstanding(
        widget.session,
        partyType: _customers ? 'customer' : 'supplier',
        partyId: row['party_id']?.toString() ?? '',
        adjustmentType: adjustmentType,
        amount: draft.amount,
        reason: draft.reason,
      );
      if (!mounted) {
        return;
      }
      _message(
        adjustmentType == 'discount'
            ? 'Outstanding discount posted.'
            : 'Outstanding write-off posted.',
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        _message(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Party Payments'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorView(error: snapshot.error!, onRetry: _refresh);
            }
            final rows = _rows(snapshot.data ?? const <String, dynamic>{});
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Customers'),
                        icon: Icon(Icons.people_alt_outlined),
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
                        : (value) => setState(() => _customers = value.first),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _search,
                    enabled: !_busy,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: _customers
                          ? 'Search customer, phone or ID'
                          : 'Search supplier, phone or ID',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        onPressed: _busy ? null : _refresh,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                    onSubmitted: (_) => _refresh(),
                  ),
                  const SizedBox(height: 12),
                  if (rows.isEmpty)
                    _EmptyView(customers: _customers)
                  else
                    ...rows.map((row) => Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: _partyCard(row),
                        )),
                ],
              ),
            );
          },
        ),
      );

  Widget _partyCard(Map<String, dynamic> row) {
    final scheme = Theme.of(context).colorScheme;
    final name = row['party_name']?.toString() ??
        row[_customers ? 'customer_name' : 'supplier_name']?.toString() ??
        (_customers ? 'Customer' : 'Supplier');
    final trade = _tradeOutstanding(row);
    final loan = _n(row['loan_outstanding']);
    final total = _n(row['balance'] ?? row['total_outstanding']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        '${row['document_count'] ?? row['open_invoice_count'] ?? 0} open document(s)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  _money(total),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 5,
              children: [
                Text('Trade outstanding ${_money(trade)}'),
                if (loan > .005) Text('Loan ${_money(loan)}'),
                if (!_customers && _n(row['credit_balance']) > .005)
                  Text('Credit ${_money(row['credit_balance'])}'),
              ],
            ),
            if (loan > .005) ...[
              const SizedBox(height: 5),
              Text(
                'Loan balance remains in the Loans workspace.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy || trade <= .005 ? null : () => _recordPayment(row),
                  icon: Icon(_customers ? Icons.call_received_rounded : Icons.call_made_rounded),
                  label: Text(_customers ? 'Receive' : 'Pay'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || trade <= .005 ? null : () => _close(row, 'discount'),
                  icon: const Icon(Icons.percent_rounded),
                  label: const Text('Discount'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || trade <= .005 ? null : () => _close(row, 'write_off'),
                  icon: const Icon(Icons.do_not_disturb_alt_outlined),
                  label: const Text('Write-off'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
  final String actionLabel;
  final double maximumAmount;

  const _PaymentDialog({
    required this.title,
    required this.actionLabel,
    required this.maximumAmount,
  });

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
    _amount = TextEditingController(text: widget.maximumAmount.toStringAsFixed(2));
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
    if (amount <= 0 || amount > widget.maximumAmount + .005) {
      setState(() => _error = 'Enter an amount up to ${widget.maximumAmount.toStringAsFixed(2)}.');
      return;
    }
    Navigator.pop(
      context,
      _PaymentDraft(amount, _method, _reference.text.trim(), _notes.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
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
              ),
              const SizedBox(height: 9),
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
              const SizedBox(height: 9),
              TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Reference')),
              const SizedBox(height: 9),
              TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
        ],
      );
}

class _CloseDraft {
  final double amount;
  final String reason;

  const _CloseDraft(this.amount, this.reason);
}

class _CloseDialog extends StatefulWidget {
  final String partyName;
  final String adjustmentType;
  final double maximumAmount;
  final String currencyCode;

  const _CloseDialog({
    required this.partyName,
    required this.adjustmentType,
    required this.maximumAmount,
    required this.currencyCode,
  });

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  late final TextEditingController _amount;
  final _reason = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.maximumAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0 || amount > widget.maximumAmount + .005) {
      setState(() => _error = 'Enter an amount up to ${widget.maximumAmount.toStringAsFixed(2)}.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Reason is required for audit history.');
      return;
    }
    Navigator.pop(context, _CloseDraft(amount, _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.adjustmentType == 'discount' ? 'Discount' : 'Write-off';
    return AlertDialog(
      title: Text('$label outstanding'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.partyName, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Adjustment amount (${widget.currencyCode})',
                helperText: 'Eligible outstanding ${widget.maximumAmount.toStringAsFixed(2)}',
              ),
            ),
            const SizedBox(height: 9),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reason / approval note'),
            ),
            const SizedBox(height: 10),
            const Text(
              'This is a financial settlement only. The original invoice, GST value and GST snapshot are not changed.',
              style: TextStyle(fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text('Confirm $label')),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  final bool customers;
  const _EmptyView({required this.customers});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 42),
            const SizedBox(height: 9),
            Text(customers ? 'No customer receivables' : 'No supplier payables'),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
