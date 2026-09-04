import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/purchase_detail.dart';
import '../services/purchase_service.dart';
import '../services/return_receipt_service.dart';
import '../services/activity_timeline_service.dart';
import '../widgets/activity_timeline_card.dart';

class PurchaseDetailScreen extends StatefulWidget {
  final ClientSession session;
  final String purchaseId;

  const PurchaseDetailScreen({
    super.key,
    required this.session,
    required this.purchaseId,
  });

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  final PurchaseService _service = PurchaseService();

  bool _loading = true;

  String? _error;

  PurchaseDetail? _purchase;
  String _returnStatus = 'not_returned';

  bool get _canManage => widget.session.hasPermission('purchases.manage');

  bool get _canReturn =>
      widget.session.hasPermission('purchases.return') ||
      _canManage ||
      widget.session.hasRole('owner');

  bool get _canVoid =>
      widget.session.hasPermission('purchases.void') ||
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
        _service.getPurchaseDetail(
          tenantId: widget.session.business.id,
          purchaseId: widget.purchaseId,
        ),
        _service.getReturnStatus(
          tenantId: widget.session.business.id,
          purchaseId: widget.purchaseId,
        ),
      ]);
      final purchase = values[0] as PurchaseDetail;
      final returnStatus = values[1] as Map<String, dynamic>;

      if (!mounted) {
        return;
      }

      setState(() {
        _purchase = purchase;
        _returnStatus = returnStatus['status']?.toString() ?? 'not_returned';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }

    return '${widget.session.currencyCode} '
        '${value.toStringAsFixed(2)}';
  }

  String _date(DateTime? value) {
    if (value == null) {
      return '-';
    }

    final date = value.toLocal();

    return '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.year}';
  }

  String _dateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }

    final date = value.toLocal();

    return '${_date(date)} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _quantity(double value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

  Future<void> _returnItems() async {
    final purchase = _purchase;
    if (purchase == null) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _PurchaseReturnDialog(session: widget.session, purchase: purchase),
    );
    if (changed == true) {
      await _load();
      if (mounted) {
        ThqNotify.success(context, 'Purchase return posted successfully.');
      }
    }
  }

  Future<void> _voidPurchase() async {
    final purchase = _purchase;
    if (purchase == null) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Void ${purchase.purchaseNumber}?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Direct void is only allowed for an unpaid purchase with no returns, and only when the received stock is still available. Otherwise use Purchase Return.',
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
            child: const Text('Void Purchase'),
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
        ThqNotify.showSnackBar(
          context,
          const SnackBar(content: Text('Void reason is required.')),
        );
      }
      return;
    }
    try {
      await _service.voidPurchase(
        tenantId: widget.session.business.id,
        purchaseId: purchase.purchaseId,
        reason: value,
      );
      await _load();
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          const SnackBar(content: Text('Purchase voided.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _recordPayment() async {
    final purchase = _purchase;

    if (purchase == null || purchase.balanceDue <= 0) {
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _PurchasePaymentDialog(session: widget.session, purchase: purchase),
    );

    if (changed == true) {
      await _load();

      if (!mounted) {
        return;
      }

      ThqNotify.success(context, 'Payment recorded');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        title: const Text(
          'Purchase Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorView()
          : _content(),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56),

          const SizedBox(height: 16),

          Text(
            _error ?? 'Could not load purchase.',
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),

          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final purchase = _purchase!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),

      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(purchase),

              const SizedBox(height: 10),

              _supplierCard(purchase),

              const SizedBox(height: 10),

              _itemsCard(purchase),

              const SizedBox(height: 10),

              _totalsCard(purchase),

              const SizedBox(height: 10),

              _paymentsCard(purchase),

              const SizedBox(height: 10),

              ActivityTimelineCard(
                future: ActivityTimelineService().load(
                  tenantId: widget.session.business.id,
                  entityType: 'purchase',
                  entityId: purchase.purchaseId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(PurchaseDetail purchase) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.shopping_cart_outlined, size: 32),
        ),

        const SizedBox(width: 18),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                purchase.purchaseNumber,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                'Purchase Date: '
                '${_date(purchase.purchaseDate)}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),

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
              if (value == 'void') _voidPurchase();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'void', child: Text('Void unpaid purchase')),
            ],
          ),
        const SizedBox(width: 8),
        _StatusBadge(text: purchase.status, type: 'document'),
        const SizedBox(width: 6),
        _StatusBadge(text: _returnStatus.replaceAll('_', ' '), type: 'return'),
      ],
    );
  }

  Widget _supplierCard(PurchaseDetail purchase) {
    return _Card(
      title: 'Supplier',

      child: Wrap(
        spacing: 50,
        runSpacing: 20,
        children: [
          _Info(label: 'Supplier', value: purchase.supplierName),

          _Info(
            label: 'Supplier Invoice',
            value: purchase.supplierInvoiceNumber ?? '-',
          ),

          _Info(
            label: 'GSTIN / Tax ID',
            value: purchase.supplierTaxNumber ?? '-',
          ),

          _Info(label: 'Due Date', value: _date(purchase.dueDate)),
        ],
      ),
    );
  }

  Widget _itemsCard(PurchaseDetail purchase) {
    return _Card(
      title: 'Purchase Items',

      child: Column(
        children: [
          for (final item in purchase.items)
            _PurchaseItemRow(item: item, money: _money, quantity: _quantity),
        ],
      ),
    );
  }

  Widget _totalsCard(PurchaseDetail purchase) {
    return _Card(
      title: 'Totals',

      child: Align(
        alignment: Alignment.centerRight,

        child: SizedBox(
          width: 420,

          child: Column(
            children: [
              _TotalRow(label: 'Subtotal', value: _money(purchase.subtotal)),

              _TotalRow(
                label: 'Discount',
                value: '- ${_money(purchase.discountTotal)}',
              ),

              _TotalRow(label: 'Tax', value: _money(purchase.taxTotal)),

              _TotalRow(
                label: 'Additional Charges',
                value: _money(purchase.additionalCharges),
              ),

              const Divider(),

              _TotalRow(
                label: 'Grand Total',
                value: _money(purchase.grandTotal),
                bold: true,
              ),

              _TotalRow(label: 'Paid', value: _money(purchase.paidAmount)),

              _TotalRow(
                label: 'Balance Due',
                value: _money(purchase.balanceDue),
                bold: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentsCard(PurchaseDetail purchase) {
    final canPay =
        _canManage &&
        purchase.status == 'posted' &&
        purchase.balanceDue > 0.0001;

    return _Card(
      title: 'Payments',

      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(text: purchase.paymentStatus, type: 'payment'),

          if (canPay) ...[
            const SizedBox(width: 12),

            FilledButton.icon(
              onPressed: _recordPayment,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Record Payment'),
            ),
          ],
        ],
      ),

      child: purchase.payments.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'No payments recorded yet.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          : Column(
              children: [
                for (final payment in purchase.payments)
                  _PaymentRow(
                    payment: payment,
                    money: _money,
                    dateTime: _dateTime,
                  ),
              ],
            ),
    );
  }
}

class _PurchaseReturnDialog extends StatefulWidget {
  final ClientSession session;
  final PurchaseDetail purchase;

  const _PurchaseReturnDialog({required this.session, required this.purchase});

  @override
  State<_PurchaseReturnDialog> createState() => _PurchaseReturnDialogState();
}

class _PurchaseReturnDialogState extends State<_PurchaseReturnDialog> {
  final PurchaseService _service = PurchaseService();
  final TextEditingController _reason = TextEditingController();
  late final Map<String, TextEditingController> _qty;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qty = {
      for (final item in widget.purchase.items)
        item.itemId: TextEditingController(text: '0'),
    };
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final controller in _qty.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[];
    for (final item in widget.purchase.items) {
      final q = double.tryParse(_qty[item.itemId]!.text.trim()) ?? 0;
      if (q < 0 || q > item.quantity) {
        setState(
          () => _error = 'Return quantity cannot exceed purchased quantity.',
        );
        return;
      }
      if (q > 0) {
        items.add({'purchase_item_id': item.itemId, 'quantity': q});
      }
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
        purchaseId: widget.purchase.purchaseId,
        items: items,
        reason: _reason.text,
      );
      if (!mounted) return;
      final printReceipt = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Return ${result['return_number'] ?? ''} posted'),
          content: Text(
            'Return total: ${widget.session.currencyCode} ${((result['grand_total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}\n\nPrint an 80mm purchase-return receipt now?',
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
        for (final item in widget.purchase.items) {
          final quantity = double.tryParse(_qty[item.itemId]!.text.trim()) ?? 0;
          if (quantity <= 0) continue;
          final discount = item.quantity <= 0
              ? 0
              : item.discountAmount * (quantity / item.quantity);
          final taxable = (item.unitCost * quantity - discount)
              .clamp(0, double.infinity)
              .toDouble();
          final lineTotal = taxable + taxable * item.taxRate / 100;
          receiptRows.add(
            ReturnReceiptRow(
              name: item.productName,
              reference: item.sku,
              quantity: quantity,
              rate: item.unitCost,
              taxRate: item.taxRate,
              total: lineTotal,
            ),
          );
        }
        try {
          await ReturnReceiptService().printReceipt(
            businessName: widget.session.business.name,
            currencyCode: widget.session.currencyCode,
            returnType: 'purchase',
            returnNumber: result['return_number']?.toString() ?? 'RETURN',
            originalNumber: widget.purchase.purchaseNumber,
            partyName: widget.purchase.supplierName,
            reason: _reason.text,
            rows: receiptRows,
            grandTotal: (result['grand_total'] as num?)?.toDouble() ?? 0,
            storeName: widget.session.device?.locationName,
            terminalName: widget.session.device?.deviceName,
            userName: widget.session.username,
          );
        } catch (error) {
          if (mounted) {
            ThqNotify.showSnackBar(
              context,
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
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Return Items • ${widget.purchase.purchaseNumber}'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 330),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.purchase.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = widget.purchase.items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.productName),
                    subtitle: Text('${item.sku} • Purchased ${item.quantity}'),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
}

class _PurchasePaymentDialog extends StatefulWidget {
  final ClientSession session;
  final PurchaseDetail purchase;

  const _PurchasePaymentDialog({required this.session, required this.purchase});

  @override
  State<_PurchasePaymentDialog> createState() => _PurchasePaymentDialogState();
}

class _PurchasePaymentDialogState extends State<_PurchasePaymentDialog> {
  final PurchaseService _service = PurchaseService();

  late final TextEditingController _amountController;

  final TextEditingController _referenceController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  String _paymentMethod = 'cash';

  bool _saving = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _amountController = TextEditingController(
      text: widget.purchase.balanceDue.toStringAsFixed(2),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());

    if (amount == null || amount <= 0) {
      setState(() {
        _error = 'Enter a payment amount greater than zero.';
      });

      return;
    }

    if (amount > widget.purchase.balanceDue + 0.0001) {
      setState(() {
        _error = 'Payment cannot exceed the remaining balance.';
      });

      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _service.addPayment(
        tenantId: widget.session.business.id,
        purchaseId: widget.purchase.purchaseId,
        amount: amount,
        paymentMethod: _paymentMethod,
        referenceNumber: _referenceController.text,
        notes: _notesController.text,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record Supplier Payment'),

      content: SizedBox(
        width: 520,

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.purchase.purchaseNumber} • '
                '${widget.purchase.supplierName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

            const SizedBox(height: 5),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Balance Due: '
                '₹${widget.purchase.balanceDue.toStringAsFixed(2)}',
              ),
            ),

            const SizedBox(height: 10),

            TextField(
              controller: _amountController,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Payment Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _paymentMethod = value;
                      });
                    },
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _referenceController,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Reference Number',
                hintText: 'UPI / Bank / Cheque reference',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: _notesController,
              enabled: !_saving,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ],
        ),
      ),

      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),

        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.payments_outlined),
          label: Text(_saving ? 'Saving...' : 'Record Payment'),
        ),
      ],
    );
  }
}

class _PurchaseItemRow extends StatelessWidget {
  final PurchaseDetailItem item;

  final String Function(double) money;

  final String Function(double) quantity;

  const _PurchaseItemRow({
    required this.item,
    required this.money,
    required this.quantity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),

      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),

      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),

                Text(
                  [item.sku, item.partNumber]
                      .where((value) => value != null && value.isNotEmpty)
                      .join(' • '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          Expanded(
            child: Text(
              '${quantity(item.quantity)} '
              '${item.unitCode ?? ''}',
            ),
          ),

          Expanded(child: Text(money(item.unitCost))),

          Expanded(child: Text(money(item.discountAmount))),

          Expanded(child: Text('${item.taxRate.toStringAsFixed(2)}%')),

          Expanded(
            child: Text(
              money(item.lineTotal),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final PurchasePayment payment;

  final String Function(double) money;

  final String Function(DateTime?) dateTime;

  const _PaymentRow({
    required this.payment,
    required this.money,
    required this.dateTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),

      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),

      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.payments_outlined, color: Colors.green.shade700),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.paymentMethod.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),

                Text(
                  [payment.referenceNumber, payment.notes]
                      .where((value) => value != null && value.isNotEmpty)
                      .join(' • '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(payment.amount),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                dateTime(payment.paidAt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Card({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              ?trailing,
            ],
          ),

          const SizedBox(height: 10),

          child,
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;

  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),

          const SizedBox(height: 5),

          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),

      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),

          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 17 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final String type;

  const _StatusBadge({required this.text, required this.type});

  @override
  Widget build(BuildContext context) {
    final value = text.toLowerCase();

    Color background;
    Color foreground;

    if (type == 'payment') {
      if (value == 'paid') {
        background = Colors.green.shade50;
        foreground = Colors.green.shade700;
      } else if (value == 'partial') {
        background = Colors.orange.shade50;
        foreground = Colors.orange.shade800;
      } else {
        background = Colors.red.shade50;
        foreground = Colors.red.shade700;
      }
    } else {
      background = Colors.indigo.shade50;
      foreground = Colors.indigo.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),

      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),

      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
      ),
    );
  }
}
