import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import '../../widgets/mobile_workspace_widgets.dart';

class MobilePartyPaymentsPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;

  const MobilePartyPaymentsPage({
    super.key,
    required this.session,
    required this.service,
  });

  @override
  State<MobilePartyPaymentsPage> createState() =>
      _MobilePartyPaymentsPageState();
}

class _MobilePartyPaymentsPageState extends State<MobilePartyPaymentsPage> {
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
    _future = widget.service.partyPaymentSummary(
      widget.session,
      query: _search.text.trim(),
    );
  }

  Future<void> _refresh() async {
    final next = widget.service.partyPaymentSummary(
      widget.session,
      query: _search.text.trim(),
    );
    setState(() => _future = next);
    await next;
  }

  double _n(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  double _supplierTrade(Map<String, dynamic> row) {
    final gross =
        _n(row['purchase_outstanding']) + _n(row['invoice_outstanding']);
    final credit = _n(row['credit_balance']);
    return gross > credit ? gross - credit : 0;
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> data) =>
      (data[_customers ? 'receivables' : 'payables'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  Future<void> _receiveCustomer(Map<String, dynamic> row) async {
    final maximum = _n(row['sales_outstanding']);
    if (_busy || maximum <= .005) {
      return;
    }
    final draft = await showDialog<_PaymentDraft>(
      context: context,
      builder: (_) => _PaymentDialog(
        title: 'Receive from ${row['party_name'] ?? 'customer'}',
        maximum: maximum,
        actionLabel: 'Receive',
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.receiveCustomerPayment(
        widget.session,
        customerId: row['party_id']?.toString() ?? '',
        amount: draft.amount,
        method: draft.method,
        reference: draft.reference,
        notes: draft.notes,
      );
      if (!mounted) {
        return;
      }
      ThqNotify.success(context, 'Customer payment recorded.');
      await _refresh();
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _paySupplier(Map<String, dynamic> row) async {
    final maximum = _supplierTrade(row);
    if (_busy || maximum <= .005) {
      return;
    }
    final draft = await showDialog<_PaymentDraft>(
      context: context,
      builder: (_) => _PaymentDialog(
        title: 'Pay ${row['party_name'] ?? 'supplier'}',
        maximum: maximum,
        actionLabel: 'Pay',
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.paySupplier(
        widget.session,
        supplierId: row['party_id']?.toString() ?? '',
        amount: draft.amount,
        method: draft.method,
        reference: draft.reference,
        notes: draft.notes,
      );
      if (!mounted) {
        return;
      }
      ThqNotify.success(context, 'Supplier payment recorded.');
      await _refresh();
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _closeOutstanding(Map<String, dynamic> row) async {
    final partyType = _customers ? 'customer' : 'supplier';
    final maximum = _customers
        ? _n(row['sales_outstanding'])
        : _supplierTrade(row);
    if (_busy || maximum <= .005) {
      return;
    }
    final draft = await showDialog<_SettlementDraft>(
      context: context,
      builder: (_) => _SettlementDialog(
        partyName: row['party_name']?.toString() ?? partyType,
        maximum: maximum,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.closeOutstanding(
        widget.session,
        partyType: partyType,
        partyId: row['party_id']?.toString() ?? '',
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
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text('$error')));
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
          return const WorkspaceLoadingList();
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              WorkspaceErrorView(error: snapshot.error!, onRetry: _refresh),
            ],
          );
        }
        final data = snapshot.data ?? const <String, dynamic>{};
        final rows = _rows(data);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
            children: [
              ThqMobileInlineMessage(
                message:
                    'Posting store: ${widget.session.locationName}. Discounts and write-offs are financial settlements only; invoice and GST values are not changed.',
                icon: Icons.storefront_outlined,
              ),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Customers'),
                    icon: Icon(Icons.people_outline_rounded),
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
                    : (value) => setState(() {
                        _customers = value.first;
                        _search.clear();
                      }),
              ),
              const SizedBox(height: 10),
              ThqMobileSearchField(
                controller: _search,
                hintText: _customers ? 'Search customer' : 'Search supplier',
                onSubmitted: (_) => _refresh(),
                onClear: () {
                  _search.clear();
                  _refresh();
                },
              ),
              const SizedBox(height: 12),
              ThqMobileSectionHeader(
                title: _customers
                    ? 'Customer receivables'
                    : 'Supplier payables',
                subtitle:
                    '${rows.length} account(s) at ${widget.session.locationName}',
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                ThqMobileEmptyState(
                  title: _customers
                      ? 'No customer receivables'
                      : 'No supplier payables',
                  message: 'Nothing is currently outstanding in this store.',
                  icon: Icons.account_balance_wallet_outlined,
                )
              else
                ...rows.map((row) {
                  final customer = _customers;
                  final balance = _n(row['balance']);
                  final sales = _n(row['sales_outstanding']);
                  final loans = _n(row['loan_outstanding']);
                  final purchase = _n(row['purchase_outstanding']);
                  final invoices = _n(row['invoice_outstanding']);
                  final supplierTrade = _supplierTrade(row);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: WorkspaceRecordCard(
                      title:
                          row['party_name']?.toString() ??
                          (customer ? 'Customer' : 'Supplier'),
                      subtitle: customer
                          ? 'Sales ${workspaceMoney(widget.session, sales)}${loans > .005 ? ' • Loans ${workspaceMoney(widget.session, loans)} (separate)' : ''}'
                          : 'Purchases ${workspaceMoney(widget.session, purchase)} • Invoices ${workspaceMoney(widget.session, invoices)}${loans > .005 ? ' • Loans ${workspaceMoney(widget.session, loans)} (separate)' : ''}',
                      trailing: workspaceMoney(
                        widget.session,
                        customer ? balance : supplierTrade,
                      ),
                      fields: [
                        WorkspaceRecordField(
                          'Open docs',
                          '${row['document_count'] ?? 0}',
                          icon: Icons.receipt_long_outlined,
                        ),
                        WorkspaceRecordField(
                          'Overdue',
                          workspaceMoney(widget.session, row['overdue']),
                          icon: Icons.schedule_rounded,
                        ),
                        if (!customer && _n(row['credit_balance']) > .005)
                          WorkspaceRecordField(
                            'Credit',
                            workspaceMoney(
                              widget.session,
                              row['credit_balance'],
                            ),
                            icon: Icons.savings_outlined,
                          ),
                      ],
                      footer: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _busy ||
                                      (customer ? sales : supplierTrade) <= .005
                                  ? null
                                  : () => _closeOutstanding(row),
                              icon: const Icon(Icons.rule_rounded),
                              label: const Text('Close'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : customer
                                  ? (sales > .005
                                        ? () => _receiveCustomer(row)
                                        : null)
                                  : (supplierTrade > .005
                                        ? () => _paySupplier(row)
                                        : null),
                              icon: const Icon(Icons.payments_outlined),
                              label: Text(
                                customer ? 'Receive' : 'Pay supplier',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
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
  final String actionLabel;
  const _PaymentDialog({
    required this.title,
    required this.maximum,
    required this.actionLabel,
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
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0 || amount > widget.maximum + .005) {
      setState(
        () => _error =
            'Enter an amount up to ${widget.maximum.toStringAsFixed(2)}.',
      );
      return;
    }
    Navigator.pop(
      context,
      _PaymentDraft(
        amount,
        _method,
        _reference.text.trim(),
        _notes.text.trim(),
      ),
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
      FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
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
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final reason = _reason.text.trim();
    if (amount <= 0 || amount > widget.maximum + .005) {
      setState(
        () => _error =
            'Enter an amount up to ${widget.maximum.toStringAsFixed(2)}.',
      );
      return;
    }
    if (reason.isEmpty) {
      setState(
        () => _error = 'Reason is required for an outstanding adjustment.',
      );
      return;
    }
    Navigator.pop(context, _SettlementDraft(_type, amount, reason));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Close ${widget.partyName} outstanding'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ThqMobileInlineMessage(
            message:
                'This is a financial settlement. It does not change the original invoice or GST value.',
            icon: Icons.info_outline_rounded,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Adjustment'),
            items: const [
              DropdownMenuItem(value: 'discount', child: Text('Discount')),
              DropdownMenuItem(value: 'write_off', child: Text('Write-off')),
            ],
            onChanged: (value) => setState(() => _type = value ?? _type),
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
