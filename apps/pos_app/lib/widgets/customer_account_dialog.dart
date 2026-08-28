import 'package:flutter/material.dart';
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
    if (outstanding <= 0.005) return;
    final invoices = (_account['open_invoices'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
    final reference = TextEditingController();
    final notes = TextEditingController();
    String? saleId;
    String method = 'cash';

    final form = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Receive Customer Payment'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customerName,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text('Total outstanding: ${_money(outstanding)}'),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    initialValue: saleId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Apply payment to',
                      helperText: 'Account payment automatically settles oldest invoices first.',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Customer account • oldest invoices first'),
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
                        if (value == null) {
                          amount.text = outstanding.toStringAsFixed(2);
                        } else {
                          final selected = invoices.firstWhere(
                            (row) => row['sale_id']?.toString() == value,
                            orElse: () => <String, dynamic>{},
                          );
                          amount.text = _number(selected['balance']).toStringAsFixed(2);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount received',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(labelText: 'Payment method'),
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
                    decoration: const InputDecoration(labelText: 'Reference number (optional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () {
                final value = double.tryParse(amount.text.trim()) ?? 0;
                if (value <= 0) return;
                Navigator.pop(dialogContext, <String, dynamic>{
                  'amount': value,
                  'method': method,
                  'sale_id': saleId,
                  'reference': reference.text.trim(),
                  'notes': notes.text.trim(),
                });
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Receive'),
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
      ScaffoldMessenger.of(context).showSnackBar(
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
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  Card(
                    color: outstanding > 0.005 ? Colors.orange.shade50 : Colors.green.shade50,
                    child: ListTile(
                      leading: Icon(outstanding > 0.005 ? Icons.schedule : Icons.check_circle_outline),
                      title: const Text('Outstanding balance'),
                      trailing: Text(
                        _money(outstanding),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Open invoices', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      if (widget.canReceive && outstanding > 0.005)
                        FilledButton.icon(
                          onPressed: _receiving ? null : _receivePayment,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Receive Payment'),
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
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final row = invoices[index];
                              return ListTile(
                                dense: true,
                                title: Text('${row['sale_number'] ?? '-'} • ${row['location_name'] ?? ''}'),
                                subtitle: Text(
                                  'Sale ${row['sale_date'] ?? '-'} • Total ${_money(row['grand_total'])} • Paid ${_money(row['paid'])}${_number(row['returned']) > 0.005 ? ' • Returned ${_money(row['returned'])}' : ''}',
                                ),
                                trailing: Text(
                                  _money(row['balance']),
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 20),
                  const Text('Payment history', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: receipts.isEmpty
                        ? const Center(child: Text('No account receipts recorded yet.'))
                        : ListView.separated(
                            itemCount: receipts.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final row = receipts[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.receipt_long_outlined),
                                title: Text('${row['receipt_number'] ?? '-'} • ${_money(row['amount'])}'),
                                subtitle: Text(
                                  '${(row['payment_method'] ?? '').toString().toUpperCase()} • ${row['receipt_date'] ?? ''} • ${row['location_name'] ?? ''}'
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
        TextButton(onPressed: _receiving ? null : () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
