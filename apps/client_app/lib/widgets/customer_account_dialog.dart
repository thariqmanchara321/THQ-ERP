import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:uuid/uuid.dart';

import '../services/customer_account_service.dart';

class CustomerAccountDialog extends StatefulWidget {
  final String tenantId;
  final String customerId;
  final String customerName;
  final String currencyCode;
  final String? locationId;
  final String? deviceId;
  final bool canReceive;

  const CustomerAccountDialog({
    super.key,
    required this.tenantId,
    required this.customerId,
    required this.customerName,
    required this.currencyCode,
    this.locationId,
    this.deviceId,
    this.canReceive = true,
  });

  @override
  State<CustomerAccountDialog> createState() => _CustomerAccountDialogState();
}

class _CustomerAccountDialogState extends State<CustomerAccountDialog> {
  final CustomerAccountService _service = CustomerAccountService();
  bool _loading = true;
  bool _receiving = false;
  String? _error;
  Map<String, dynamic> _account = const {};

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

  String _money(dynamic value) {
    final amount = _number(value);
    return widget.currencyCode == 'INR'
        ? '₹${amount.toStringAsFixed(2)}'
        : '${widget.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final account = await _service.account(
        tenantId: widget.tenantId,
        customerId: widget.customerId,
      );
      if (mounted) setState(() => _account = account);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _receivePayment() async {
    final outstanding = _number(_account['outstanding']);
    final invoices = (_account['open_invoices'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final amount = TextEditingController();
    final reference = TextEditingController();
    final notes = TextEditingController();
    String? saleId;
    String method = 'cash';
    String? formError;
    double selectedOutstanding = outstanding;

    final form = await showThqDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            outstanding > 0.005
                ? 'Receive Customer Payment'
                : 'Receive Customer Advance / Deposit',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customerName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Total outstanding: ${_money(outstanding)}'),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    initialValue: saleId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Apply payment to',
                      helperText: invoices.isEmpty
                          ? 'Payment will be credited to customer account as an advance deposit.'
                          : 'Account payment automatically settles oldest invoices first.',
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          invoices.isEmpty
                              ? 'Customer account • on-account deposit / advance'
                              : 'Customer account • oldest invoices first',
                        ),
                      ),
                      ...invoices.map(
                        (invoice) => DropdownMenuItem<String?>(
                          value: invoice['sale_id']?.toString(),
                          child: Text(
                            '${invoice['sale_number'] ?? '-'} • ${_money(invoice['balance'])} due • ${invoice['location_name'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setLocalState(() {
                        saleId = value;
                        formError = null;
                        if (value == null) {
                          selectedOutstanding = outstanding;
                        } else {
                          final selected = invoices.firstWhere(
                            (row) => row['sale_id']?.toString() == value,
                            orElse: () => <String, dynamic>{},
                          );
                          selectedOutstanding = _number(selected['balance']);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setLocalState(() => formError = null),
                    decoration: const InputDecoration(
                      labelText: 'Amount actually received',
                      hintText: 'Enter the amount received from the customer',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedOutstanding > 0.005
                        ? 'Selected outstanding: ${_money(selectedOutstanding)}'
                        : 'No open balance in scope • full amount will be credited as advance',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank')),
                      DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) {
                      if (value != null) setLocalState(() => method = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Reference number (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                  if (formError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      formError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final value = double.tryParse(amount.text.trim()) ?? 0;
                if (value <= 0) {
                  setLocalState(
                    () => formError = 'Enter the amount actually received.',
                  );
                  return;
                }
                final isAdvance = selectedOutstanding <= 0.005;
                final isOverpayment = value > selectedOutstanding + 0.005;
                final remaining = (selectedOutstanding - value).clamp(
                  0.0,
                  selectedOutstanding,
                );
                final advancePortion = isAdvance
                    ? value
                    : (isOverpayment ? value - selectedOutstanding : 0.0);

                final String confirmationText;
                if (isAdvance) {
                  confirmationText =
                      'Receive ${_money(value)} from ${widget.customerName} as an on-account deposit / advance?';
                } else if (isOverpayment) {
                  confirmationText =
                      'Receive ${_money(value)} from ${widget.customerName}?\n\n'
                      '• Invoice settlement: ${_money(selectedOutstanding)}\n'
                      '• On-account advance / credit: ${_money(advancePortion)}\n'
                      '• Remaining invoice balance: ${_money(0)}';
                } else {
                  confirmationText =
                      'Receive ${_money(value)} from ${widget.customerName}?\n\n'
                      'Selected balance after this receipt: ${_money(remaining)}';
                }

                final confirmed = await showThqDialog<bool>(
                  context: dialogContext,
                  builder: (confirmContext) => AlertDialog(
                    title: const Text('Confirm receipt amount'),
                    content: Text(confirmationText),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmContext, false),
                        child: const Text('Back'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(confirmContext, true),
                        child: Text('Receive ${_money(value)}'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !dialogContext.mounted) return;
                Navigator.pop(dialogContext, <String, dynamic>{
                  'amount': value,
                  'method': method,
                  'sale_id': saleId,
                  'reference': reference.text.trim(),
                  'notes': notes.text.trim(),
                });
              },
              icon: const Icon(Icons.check),
              label: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reference.dispose();
    notes.dispose();
    if (form == null || !mounted) return;

    setState(() {
      _receiving = true;
      _error = null;
    });
    try {
      final result = await _service.receivePayment(
        tenantId: widget.tenantId,
        customerId: widget.customerId,
        amount: _number(form['amount']),
        paymentMethod: form['method'].toString(),
        referenceNumber: form['reference']?.toString() ?? '',
        notes: form['notes']?.toString() ?? '',
        saleId: form['sale_id']?.toString(),
        locationId: widget.locationId,
        deviceId: widget.deviceId,
        requestId: const Uuid().v4(),
      );
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text(
            '${result['receipt_number'] ?? 'Payment'} received • Remaining ${_money(result['outstanding_after'])}',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  Future<void> _voidReceipt(Map<String, dynamic> receipt) async {
    if (receipt['status']?.toString() == 'void') return;
    final receiptId = receipt['receipt_id']?.toString();
    if (receiptId == null || receiptId.isEmpty) return;

    final reason = TextEditingController();
    final value = await showThqDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Void ${receipt['receipt_number'] ?? 'receipt'}'),
        content: SizedBox(
          width: 440,
          child: TextField(
            controller: reason,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              hintText: 'Explain why this receipt is being reversed',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () {
              final text = reason.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(dialogContext, text);
            },
            child: const Text('Void Receipt'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (value == null || value.trim().isEmpty || !mounted) return;

    setState(() {
      _receiving = true;
      _error = null;
    });
    try {
      final result = await _service.voidReceipt(
        tenantId: widget.tenantId,
        receiptId: receiptId,
        reason: value,
      );
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text(
            '${result['receipt_number'] ?? 'Receipt'} voided • Outstanding ${_money(result['outstanding_after'])}',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _receiving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoices = (_account['open_invoices'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final receipts = (_account['receipts'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final outstanding = _number(_account['outstanding']);
    final unallocatedAdvance = _number(_account['unallocated_advance']);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text('${widget.customerName} • Account')),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 610,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Card(
                    color: outstanding > 0.005
                        ? context.thqSemanticColors.warning
                        : Theme.of(context).colorScheme.primary,
                    child: ListTile(
                      leading: Icon(
                        outstanding > 0.005
                            ? Icons.schedule
                            : Icons.check_circle_outline,
                      ),
                      title: Text(
                        unallocatedAdvance > 0.005 && outstanding <= 0.005
                            ? 'On-account advance deposit / credit'
                            : (unallocatedAdvance > 0.005
                                ? 'Net outstanding (${_money(unallocatedAdvance)} advance credited)'
                                : 'Outstanding balance'),
                      ),
                      trailing: Text(
                        unallocatedAdvance > 0.005 && outstanding <= 0.005
                            ? '-${_money(unallocatedAdvance)}'
                            : _money(outstanding),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Open invoices',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (widget.canReceive)
                        FilledButton.icon(
                          onPressed: _receiving ? null : _receivePayment,
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(
                            outstanding > 0.005
                                ? 'Receive Payment'
                                : 'Receive Advance',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 210,
                    child: invoices.isEmpty
                        ? const Center(child: Text('No outstanding invoices.'))
                        : ListView.separated(
                            itemCount: invoices.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final row = invoices[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  '${row['sale_number'] ?? '-'} • ${row['location_name'] ?? ''}',
                                ),
                                subtitle: Text(
                                  'Sale ${row['sale_date'] ?? '-'} • Total ${_money(row['grand_total'])} • Paid ${_money(row['paid'])}${_number(row['returned']) > 0.005 ? ' • Returned ${_money(row['returned'])}' : ''}',
                                ),
                                trailing: Text(
                                  _money(row['balance']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 20),
                  const Text(
                    'Payment history',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: receipts.isEmpty
                        ? const Center(
                            child: Text('No account receipts recorded yet.'),
                          )
                        : ListView.separated(
                            itemCount: receipts.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final row = receipts[index];
                              final status =
                                  row['status']?.toString() ?? 'posted';
                              return ListTile(
                                dense: true,
                                trailing: widget.canReceive && status != 'void'
                                    ? IconButton(
                                        tooltip: 'Void receipt',
                                        onPressed: _receiving
                                            ? null
                                            : () => _voidReceipt(row),
                                        icon: const Icon(Icons.undo_rounded),
                                      )
                                    : status == 'void'
                                    ? const Chip(label: Text('VOID'))
                                    : null,
                                leading: const Icon(
                                  Icons.receipt_long_outlined,
                                ),
                                title: Text(
                                  '${row['receipt_number'] ?? '-'} • ${_money(row['amount'])}',
                                ),
                                subtitle: Text(
                                  '${(row['payment_method'] ?? '').toString().toUpperCase()} • ${status.toUpperCase()} • ${row['receipt_date'] ?? ''} • ${row['location_name'] ?? ''}'
                                  '${(row['reference_number'] ?? '').toString().isEmpty ? '' : ' • ${row['reference_number']}'}',
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _receiving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
