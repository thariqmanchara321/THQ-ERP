import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/mobile_session.dart';
import '../../../services/mobile_client_service.dart';
import 'material_yard_types.dart';

class MobileMaterialBillingSheet extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final Map<String, dynamic> load;
  final VoidCallback onInvoiced;

  const MobileMaterialBillingSheet({
    super.key,
    required this.session,
    required this.service,
    required this.load,
    required this.onInvoiced,
  });

  @override
  State<MobileMaterialBillingSheet> createState() =>
      _MobileMaterialBillingSheetState();
}

class _MobileMaterialBillingSheetState extends State<MobileMaterialBillingSheet> {
  final _invoiceRefCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _initialPaymentCtrl = TextEditingController(text: '0');
  final _paymentRefCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  String _paymentMethod = 'cash';
  bool _submitting = false;

  bool get isInward =>
      widget.load['direction']?.toString().toLowerCase() == 'inbound';
  String get loadId =>
      widget.load['load_id']?.toString() ??
      widget.load['id']?.toString() ??
      '';

  @override
  void initState() {
    super.initState();
    final rawRate = widget.load['rate'] ??
        widget.load['unit_price'] ??
        widget.load['delivery']?['purchasing_price'] ??
        widget.load['delivery']?['selling_price'];
    if (rawRate != null) {
      final numRate = double.tryParse(rawRate.toString()) ?? 0.0;
      if (numRate > 0) {
        _rateCtrl.text = numRate.toStringAsFixed(2);
      }
    }
    _invoiceRefCtrl.text = widget.load['source_reference']?.toString() ?? '';
    final initQty = _loadQuantity;
    if (initQty > 0) {
      _quantityCtrl.text = initQty.truncateToDouble() == initQty
          ? initQty.toStringAsFixed(0)
          : initQty.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _invoiceRefCtrl.dispose();
    _quantityCtrl.dispose();
    _rateCtrl.dispose();
    _initialPaymentCtrl.dispose();
    _paymentRefCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _loadQuantity {
    final billable = double.tryParse(widget.load['approved_billable_qty']?.toString() ?? '') ?? 0.0;
    if (billable > 0) return billable;
    final qty = double.tryParse(widget.load['quantity']?.toString() ?? '') ?? 0.0;
    if (qty > 0) return qty;
    return double.tryParse(widget.load['calculated_cft']?.toString() ?? '') ?? 0.0;
  }

  double get _quantity {
    final parsed = double.tryParse(_quantityCtrl.text.trim());
    if (parsed != null && parsed > 0) return parsed;
    return _loadQuantity;
  }

  String get _unitCode => widget.load['unit_code']?.toString() ?? 'CFT';

  double get _rate => double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
  double get _totalAmount => _rate * _quantity;
  double get _initialPayment => double.tryParse(_initialPaymentCtrl.text.trim()) ?? 0.0;

  Future<void> _postBilling() async {
    if (_quantity <= 0) {
      ThqNotify.error(context, 'Quantity Required', message: 'Enter a valid invoiced quantity.');
      return;
    }
    if (_rate <= 0) {
      ThqNotify.error(context, 'Rate Required', message: 'Enter a valid unit price / rate.');
      return;
    }

    final variantId = widget.load['variant_id']?.toString() ?? widget.load['product_id']?.toString();
    if (variantId == null || variantId.isEmpty) {
      ThqNotify.error(context, 'Invalid Load', message: 'Load does not have a valid product variant.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final loadUpdatedAt = DateTime.tryParse('${widget.load['updated_at'] ?? widget.load['created_at']}');
      if (isInward) {
        // Link to Purchase
        final supplierId = widget.load['supplier_id']?.toString();
        if (supplierId == null || supplierId.isEmpty) {
          throw StateError('This inward load has no linked supplier/quarry. Edit the load first.');
        }

        final items = [
          {
            'variant_id': variantId,
            'quantity': _quantity,
            'unit_price': _rate,
            'unit_code': _unitCode,
          }
        ];

        final result = await widget.service.linkMaterialLoadPurchase(
          widget.session,
          loadId: loadId,
          supplierId: supplierId,
          supplierInvoiceNumber: _invoiceRefCtrl.text.trim(),
          purchaseDate: _invoiceDate,
          dueDate: _dueDate,
          items: items,
          initialPayment: _initialPayment,
          paymentMethod: _paymentMethod,
          paymentReference: _paymentRefCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
          locationId: widget.load['location_id']?.toString(),
          loadUpdatedAt: loadUpdatedAt,
        );

        if (!mounted) return;
        setState(() => _submitting = false);
        final invNum = result['invoice_number'] ?? result['purchase_number'] ?? 'Saved';
        ThqNotify.success(
          context,
          'Purchase Created',
          message: 'Authoritative purchase bill #$invNum created and posted.',
        );
        widget.onInvoiced();
        Navigator.pop(context, true);
      } else {
        // Link to Sale
        final customerId = widget.load['customer_id']?.toString();
        if (customerId == null || customerId.isEmpty) {
          throw StateError('This outward load has no linked customer. Edit the load first.');
        }

        final items = [
          {
            'variant_id': variantId,
            'quantity': _quantity,
            'unit_price': _rate,
            'unit_code': _unitCode,
          }
        ];

        final paymentAllocations = <Map<String, dynamic>>[];
        if (_initialPayment > 0) {
          paymentAllocations.add({
            'payment_method': _paymentMethod,
            'amount': _initialPayment,
            'reference': _paymentRefCtrl.text.trim(),
          });
        }

        final result = await widget.service.linkMaterialLoadSale(
          widget.session,
          loadId: loadId,
          customerId: customerId,
          saleDate: _invoiceDate,
          dueDate: _dueDate,
          items: items,
          paymentAllocations: paymentAllocations,
          notes: _notesCtrl.text.trim(),
          locationId: widget.load['location_id']?.toString(),
          loadUpdatedAt: loadUpdatedAt,
        );

        if (!mounted) return;
        setState(() => _submitting = false);
        final invNum = result['invoice_number'] ?? result['sale_number'] ?? 'Saved';
        ThqNotify.success(
          context,
          'Sales Invoice Created',
          message: 'Authoritative sales invoice #$invNum generated and posted.',
        );
        widget.onInvoiced();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ThqNotify.error(context, 'Billing Failed', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = widget.session.currency;

    final partyName = isInward
        ? (widget.load['supplier_name'] ?? 'Supplier')
        : (widget.load['customer_name'] ?? 'Customer');
    final materialName = widget.load['product_name'] ?? 'Material';
    final loadNumber = widget.load['load_number'] ?? 'Load';

    return Scaffold(
      appBar: AppBar(
        title: Text(isInward ? 'Create Purchase Invoice' : 'Create Sales Invoice'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // Load Context Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(loadNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isInward ? Colors.teal : Colors.indigo).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isInward ? 'QUARRY PURCHASE' : 'CUSTOMER SALE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isInward ? Colors.teal : Colors.indigo,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('$materialName • ${MaterialYardFormat.quantity(_quantity, _unitCode)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${isInward ? "Supplier" : "Customer"}: $partyName', style: theme.textTheme.bodySmall),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Inward-only: Supplier Invoice Ref
            if (isInward) ...[
              TextField(
                controller: _invoiceRefCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier Quarry Bill / Slip Number',
                  prefixIcon: Icon(Icons.receipt_outlined),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Quantity & Rate Inputs
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Invoiced Qty ($_unitCode) *',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Final Rate per $_unitCode *',
                      prefixText: '$currency ',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if ((_quantity - _loadQuantity).abs() > 0.001) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Text(
                  '⚠️ Invoiced quantity ($_quantity $_unitCode) differs from load quantity ($_loadQuantity $_unitCode). Final invoice will post with the edited quantity; physical measurements remain historically traceable.',
                  style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Grand Invoiced Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.primary)),
                  Text(
                    MaterialYardFormat.money(_totalAmount, currency: currency),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: scheme.primary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Payment Section
            const Text('Payment Settlement', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _initialPaymentCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: isInward ? 'Amount Paid Now' : 'Amount Received Now',
                      prefixText: '$currency ',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment Mode',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank Transfer')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI / QR')),
                      DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                    ],
                    onChanged: (val) => setState(() => _paymentMethod = val ?? 'cash'),
                  ),
                ),
              ],
            ),

            if (_initialPayment > 0) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _paymentRefCtrl,
                decoration: const InputDecoration(
                  labelText: 'Payment Reference (UPI ID / Cheque / Bank Ref)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Balance note
            if (_totalAmount > _initialPayment)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Remaining balance of ${MaterialYardFormat.money(_totalAmount - _initialPayment, currency: currency)} will be added to $partyName\'s ledger.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 14),

            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Invoice / Ledger Notes',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -3)),
            ],
          ),
          child: FilledButton.icon(
            onPressed: _submitting ? null : _postBilling,
            icon: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_rounded),
            label: Text(
              _submitting
                  ? 'Posting Invoice...'
                  : isInward
                      ? 'Confirm & Post Purchase Bill'
                      : 'Confirm & Post Sales Invoice',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: isInward ? Colors.teal.shade700 : scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
