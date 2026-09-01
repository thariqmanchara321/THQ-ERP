import 'package:flutter/material.dart';
import '../models/client_session.dart';
import '../models/sale_detail.dart';
import '../services/sales_service.dart';
import '../services/return_receipt_service.dart';
import '../services/customer_service.dart';
import '../services/activity_timeline_service.dart';
import '../widgets/activity_timeline_card.dart';
import '../widgets/searchable_select.dart';
import '../models/customer.dart';
import 'invoice_preview_screen.dart';

class SaleDetailScreen extends StatefulWidget {
  final ClientSession session;
  final String saleId;
  const SaleDetailScreen({
    super.key,
    required this.session,
    required this.saleId,
  });
  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  final _service = SalesService();
  bool _loading = true;
  String? _error;
  SaleDetail? _sale;
  String _returnStatus = 'not_returned';
  bool get _canManage => widget.session.hasPermission('sales.manage');
  bool get _canEdit =>
      widget.session.hasPermission('sales.edit') ||
      _canManage ||
      widget.session.hasRole('owner');
  bool get _canReturn =>
      widget.session.hasPermission('sales.return') ||
      _canManage ||
      widget.session.hasRole('owner');
  bool get _canVoid =>
      widget.session.hasPermission('sales.void') ||
      widget.session.hasRole('owner');
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _service.getSaleDetail(
          tenantId: widget.session.business.id,
          saleId: widget.saleId,
        ),
        _service.getReturnStatus(
          tenantId: widget.session.business.id,
          saleId: widget.saleId,
        ),
      ]);
      final sale = values[0] as SaleDetail;
      final status = values[1] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _sale = sale;
          _returnStatus = status['status']?.toString() ?? 'not_returned';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _m(double v) => widget.session.currencyCode == 'INR'
      ? '₹${v.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${v.toStringAsFixed(2)}';
  String _d(DateTime? v) {
    if (v == null) return '-';
    final x = v.toLocal();
    return '${x.day.toString().padLeft(2, '0')}-${x.month.toString().padLeft(2, '0')}-${x.year}';
  }

  String _dt(DateTime? v) {
    if (v == null) return '-';
    final x = v.toLocal();
    return '${_d(x)} ${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _editMetadata() async {
    final s = _sale;
    if (s == null) return;
    final customers = await CustomerService().getCustomers(
      tenantId: widget.session.business.id,
    );
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _EditSaleDialog(
        session: widget.session,
        sale: s,
        customers: customers,
      ),
    );
    if (ok == true) await _load();
  }

  void _preview(String paper) {
    final s = _sale;
    if (s == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePreviewScreen(
          session: widget.session,
          sale: s,
          paperType: paper,
        ),
      ),
    );
  }

  Future<void> _returnItems() async {
    final s = _sale;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SaleReturnDialog(session: widget.session, sale: s),
    );
    if (ok == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sales return posted successfully.')),
        );
      }
    }
  }

  Future<void> _voidSale() async {
    final s = _sale;
    if (s == null) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Void ${s.saleNumber}?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voiding is only allowed for an unpaid sale with no previous returns. Stock will be restored and the action will be audited.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reason,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason (required)',
                ),
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
            child: const Text('Void Sale'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    final value = reason.text.trim();
    reason.dispose();
    if (value.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Void reason is required.')),
        );
      }
      return;
    }
    try {
      await _service.voidSale(
        tenantId: widget.session.business.id,
        saleId: s.saleId,
        reason: value,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sale voided.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _recordPayment() async {
    final s = _sale;
    if (s == null || s.balanceDue <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SalePaymentDialog(session: widget.session, sale: s),
    );
    if (ok == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded successfully.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    appBar: AppBar(title: const Text('Sale Details')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        : _content(),
  );
  Widget _content() {
    final s = _sale!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.saleNumber,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text('Sale Date: ${_d(s.saleDate)} • ID ${s.saleId}'),
                      ],
                    ),
                  ),
                  if (_canEdit)
                    OutlinedButton.icon(
                      onPressed: _editMetadata,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  const SizedBox(width: 8),
                  if (_canReturn)
                    OutlinedButton.icon(
                      onPressed: _returnItems,
                      icon: const Icon(Icons.keyboard_return),
                      label: const Text('Return'),
                    ),
                  if (_canReturn) const SizedBox(width: 8),
                  if (_canVoid)
                    PopupMenuButton<String>(
                      tooltip: 'Corrections',
                      onSelected: (value) {
                        if (value == 'void') _voidSale();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'void',
                          child: Text('Void unpaid sale'),
                        ),
                      ],
                      icon: const Icon(Icons.more_vert),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _preview('a4'),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Preview'),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    tooltip: 'Invoice / receipt format',
                    onSelected: _preview,
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'a4',
                        child: Text('A4 Invoice Preview'),
                      ),
                      PopupMenuItem(
                        value: '80mm',
                        child: Text('80mm Receipt Preview'),
                      ),
                    ],
                    icon: const Icon(Icons.print_outlined),
                  ),
                  const SizedBox(width: 8),
                  Chip(label: Text(s.paymentStatus.toUpperCase())),
                  const SizedBox(width: 6),
                  Chip(
                    avatar: Icon(
                      _returnStatus == 'fully_returned'
                          ? Icons.assignment_returned
                          : _returnStatus == 'partially_returned'
                          ? Icons.assignment_return_outlined
                          : Icons.check_circle_outline,
                      size: 14,
                    ),
                    label: Text(
                      _returnStatus.replaceAll('_', ' ').toUpperCase(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _Card(
                title: 'Customer',
                child: Wrap(
                  spacing: 40,
                  runSpacing: 14,
                  children: [
                    _Info('Customer', s.customerName),
                    _Info('GSTIN / Tax ID', s.customerTaxNumber ?? '-'),
                    _Info('Due Date', _d(s.dueDate)),
                    _Info('Status', s.status.toUpperCase()),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _Card(
                title: 'Items',
                child: Column(
                  children: s.items
                      .map(
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      i.productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      [i.sku, i.partNumber]
                                          .whereType<String>()
                                          .where((e) => e.isNotEmpty)
                                          .join(' • '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${i.quantity} ${i.unitCode ?? ''}',
                                ),
                              ),
                              Expanded(child: Text(_m(i.unitPrice))),
                              Expanded(
                                child: Text('${i.taxRate.toStringAsFixed(2)}%'),
                              ),
                              Expanded(
                                child: Text(
                                  _m(i.lineTotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 18),
              _Card(
                title: 'Totals & Profit',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 450,
                    child: Column(
                      children: [
                        _Total('Subtotal', _m(s.subtotal)),
                        _Total('Discount', '- ${_m(s.discountTotal)}'),
                        if (s.gst?.authoritative == true) ...[
                          if (s.gst!.cgstTotal.abs() > 0.0001)
                            _Total('CGST', _m(s.gst!.cgstTotal)),
                          if (s.gst!.sgstTotal.abs() > 0.0001)
                            _Total('SGST', _m(s.gst!.sgstTotal)),
                          if (s.gst!.utgstTotal.abs() > 0.0001)
                            _Total('UTGST', _m(s.gst!.utgstTotal)),
                          if (s.gst!.igstTotal.abs() > 0.0001)
                            _Total('IGST', _m(s.gst!.igstTotal)),
                          if (s.gst!.cessTotal.abs() > 0.0001)
                            _Total('Cess', _m(s.gst!.cessTotal)),
                          if (!s.gst!.hasComponentTax && s.taxTotal > 0.0001)
                            _Total('GST / Tax', _m(s.taxTotal)),
                        ] else
                          _Total('Tax', _m(s.taxTotal)),
                        _Total('Additional Charges', _m(s.additionalCharges)),
                        const Divider(),
                        _Total('Grand Total', _m(s.grandTotal), bold: true),
                        _Total('Paid', _m(s.paidAmount)),
                        _Total('Balance Due', _m(s.balanceDue), bold: true),
                        const Divider(),
                        _Total('Inventory Cost', _m(s.costTotal)),
                        _Total('Gross Profit', _m(s.grossProfit), bold: true),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _Card(
                title: 'Payments',
                trailing: (_canManage && s.balanceDue > 0)
                    ? FilledButton.icon(
                        onPressed: _recordPayment,
                        icon: const Icon(Icons.add),
                        label: const Text('Record Payment'),
                      )
                    : null,
                child: s.payments.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('No payments recorded.')),
                      )
                    : Column(
                        children: s.payments
                            .map(
                              (p) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.payments_outlined),
                                title: Text(
                                  '${p.paymentMethod.toUpperCase()}  •  ${_m(p.amount)}',
                                ),
                                subtitle: Text(
                                  [p.referenceNumber, p.notes]
                                      .whereType<String>()
                                      .where((e) => e.isNotEmpty)
                                      .join(' • '),
                                ),
                                trailing: Text(_dt(p.paidAt)),
                              ),
                            )
                            .toList(),
                      ),
              ),
              if ((s.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                _Card(title: 'Notes', child: Text(s.notes!)),
              ],
              const SizedBox(height: 18),
              ActivityTimelineCard(
                future: ActivityTimelineService().load(
                  tenantId: widget.session.business.id,
                  entityType: 'sale',
                  entityId: s.saleId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleReturnDialog extends StatefulWidget {
  final ClientSession session;
  final SaleDetail sale;
  const _SaleReturnDialog({required this.session, required this.sale});

  @override
  State<_SaleReturnDialog> createState() => _SaleReturnDialogState();
}

class _SaleReturnDialogState extends State<_SaleReturnDialog> {
  final SalesService _service = SalesService();
  final TextEditingController _reason = TextEditingController();
  late final Map<String, TextEditingController> _qty;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qty = {
      for (final item in widget.sale.items)
        item.itemId: TextEditingController(text: '0'),
    };
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[];
    for (final item in widget.sale.items) {
      final q = double.tryParse(_qty[item.itemId]!.text.trim()) ?? 0;
      if (q < 0 || q > item.quantity) {
        setState(
          () => _error = 'Return quantity cannot exceed the sold quantity.',
        );
        return;
      }
      if (q > 0) items.add({'sale_item_id': item.itemId, 'quantity': q});
    }
    if (items.isEmpty) {
      setState(() => _error = 'Enter a return quantity for at least one item.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Return reason is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _service.createReturn(
        tenantId: widget.session.business.id,
        saleId: widget.sale.saleId,
        items: items,
        reason: _reason.text,
      );
      if (!mounted) return;
      final printReceipt = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Return ${result['return_number'] ?? ''} posted'),
          content: Text(
            'Return total: ${widget.session.currencyCode} ${((result['grand_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}\n\nPrint an 80mm return receipt now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Done'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print Return Receipt'),
            ),
          ],
        ),
      );
      if (printReceipt == true && mounted) {
        final receiptRows = <ReturnReceiptRow>[];
        for (final item in widget.sale.items) {
          final quantity = double.tryParse(_qty[item.itemId]!.text.trim()) ?? 0;
          if (quantity <= 0) continue;
          final discount = item.quantity <= 0
              ? 0
              : item.discountAmount * (quantity / item.quantity);
          final taxable = (item.unitPrice * quantity - discount)
              .clamp(0, double.infinity)
              .toDouble();
          final lineTotal = taxable + taxable * item.taxRate / 100;
          receiptRows.add(
            ReturnReceiptRow(
              name: item.productName,
              reference: item.sku,
              quantity: quantity,
              rate: item.unitPrice,
              taxRate: item.taxRate,
              total: lineTotal,
            ),
          );
        }
        try {
          await ReturnReceiptService().printReceipt(
            businessName: widget.session.business.name,
            currencyCode: widget.session.currencyCode,
            returnType: 'sale',
            returnNumber: result['return_number']?.toString() ?? 'RETURN',
            originalNumber: widget.sale.saleNumber,
            partyName: widget.sale.customerName,
            reason: _reason.text,
            rows: receiptRows,
            grandTotal: (result['grand_total'] as num?)?.toDouble() ?? 0,
            storeName: widget.session.device?.locationName,
            terminalName: widget.session.device?.deviceName,
            userName: widget.session.username,
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Return was saved, but receipt printing failed: $error',
                ),
              ),
            );
          }
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Return Items • ${widget.sale.saleNumber}'),
    content: SizedBox(
      width: 620,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 330),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.sale.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = widget.sale.items[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.productName),
                  subtitle: Text('${item.sku} • Sold ${item.quantity}'),
                  trailing: SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _qty[item.itemId],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(
                        labelText: 'Return qty',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason (required)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Posting…' : 'Post Return'),
      ),
    ],
  );
}

class _SalePaymentDialog extends StatefulWidget {
  final ClientSession session;
  final SaleDetail sale;
  const _SalePaymentDialog({required this.session, required this.sale});
  @override
  State<_SalePaymentDialog> createState() => _SalePaymentDialogState();
}

class _SalePaymentDialogState extends State<_SalePaymentDialog> {
  final _service = SalesService();
  late final TextEditingController _amount;
  final _ref = TextEditingController(), _notes = TextEditingController();
  String _method = 'cash';
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.sale.balanceDue.toStringAsFixed(2),
    );
  }

  Future<void> _save() async {
    final n = double.tryParse(_amount.text.trim()) ?? 0;
    if (n <= 0 || n > widget.sale.balanceDue + 0.0001) {
      setState(() => _error = 'Enter an amount up to the balance due.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.addPayment(
        tenantId: widget.session.business.id,
        saleId: widget.sale.saleId,
        amount: n,
        paymentMethod: _method,
        referenceNumber: _ref.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record Customer Payment'),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Balance due: ${widget.sale.balanceDue.toStringAsFixed(2)}'),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(
              labelText: 'Payment Method',
              border: OutlineInputBorder(),
            ),
            items:
                const [
                      'cash',
                      'card',
                      'bank_transfer',
                      'upi',
                      'cheque',
                      'other',
                    ]
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.replaceAll('_', ' ').toUpperCase()),
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
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
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
            : const Text('Save Payment'),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Card({required this.title, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  final String l, v;
  const _Info(this.l, this.v);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _Total extends StatelessWidget {
  final String l, v;
  final bool bold;
  const _Total(this.l, this.v, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            l,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontSize: bold ? 16 : 14,
          ),
        ),
      ],
    ),
  );
}

class _EditSaleDialog extends StatefulWidget {
  final ClientSession session;
  final SaleDetail sale;
  final List<Customer> customers;
  const _EditSaleDialog({
    required this.session,
    required this.sale,
    required this.customers,
  });
  @override
  State<_EditSaleDialog> createState() => _EditSaleDialogState();
}

class _EditSaleDialogState extends State<_EditSaleDialog> {
  final _service = SalesService();
  late String _customerId;
  late DateTime? _due;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _customerId = widget.sale.customerId;
    _due = widget.sale.dueDate;
    _notes = TextEditingController(text: widget.sale.notes ?? '');
  }

  Future<void> _pick() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _due ?? DateTime.now(),
    );
    if (d != null) setState(() => _due = d);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.updateMetadata(
        tenantId: widget.session.business.id,
        saleId: widget.sale.saleId,
        customerId: _customerId,
        dueDate: _due,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.sale.saleNumber}'),
    content: SizedBox(
      width: 470,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Financial lines are protected after posting. You can safely change customer, due date and notes; corrections to quantities/prices should use a controlled void/recreate workflow.',
          ),
          const SizedBox(height: 14),
          SearchableSelect<String>(
            value: _customerId,
            labelText: 'Customer',
            isRequired: true,
            hintText: 'Search customer name, ID, phone or GSTIN',
            prefixIcon: Icons.person_search_outlined,
            options: widget.customers
                .where((c) => c.isActive)
                .map(
                  (customer) => SearchableSelectOption<String>(
                    value: customer.id,
                    label: customer.name,
                    subtitle:
                        [customer.publicId, customer.phone, customer.taxNumber]
                            .whereType<String>()
                            .where((v) => v.trim().isNotEmpty)
                            .join(' • '),
                    searchText:
                        '${customer.name} ${customer.publicId} ${customer.phone ?? ''} ${customer.email ?? ''} ${customer.taxNumber ?? ''}',
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _customerId = v);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _due == null
                  ? 'No due date'
                  : 'Due ${_due!.toLocal().toString().split(' ').first}',
            ),
            trailing: TextButton(onPressed: _pick, child: const Text('Change')),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving...' : 'Save'),
      ),
    ],
  );
}
