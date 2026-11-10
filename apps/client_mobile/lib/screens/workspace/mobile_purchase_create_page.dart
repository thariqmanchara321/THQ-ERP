import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';

class MobilePurchaseCreatePage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;

  const MobilePurchaseCreatePage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobilePurchaseCreatePage> createState() =>
      _MobilePurchaseCreatePageState();
}

class _MobilePurchaseCreatePageState extends State<MobilePurchaseCreatePage> {
  final _invoiceNumberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _paymentRefCtrl = TextEditingController();

  DateTime _purchaseDate = DateTime.now();
  DateTime? _dueDate;
  String? _selectedSupplierId;
  String? _selectedSupplierName;
  String _paymentMethod = 'cash';
  double _initialPayment = 0.0;
  bool _submitting = false;

  late String _effectiveLocationId;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _inventoryItems = [];
  bool _loadingDependencies = true;

  final List<_PurchaseItemEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _effectiveLocationId = widget.locationId ?? widget.session.locationId;
    _loadDependencies();
  }

  @override
  void dispose() {
    _invoiceNumberCtrl.dispose();
    _notesCtrl.dispose();
    _paymentRefCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDependencies() async {
    setState(() => _loadingDependencies = true);
    try {
      final results = await Future.wait([
        widget.service.supplierOutstanding(
          widget.session,
          locationId: _effectiveLocationId,
          limit: 300,
        ),
        widget.service.inventory(
          widget.session,
          locationId: _effectiveLocationId,
          limit: 500,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _suppliers = results[0];
        _inventoryItems = results[1];
        _loadingDependencies = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDependencies = false);
      ThqNotify.error(context, 'Error', message: 'Failed to load suppliers/products: $e');
    }
  }

  double get _subtotal => _items.fold(0.0, (acc, item) => acc + item.taxableAmount);
  double get _taxTotal => _items.fold(0.0, (acc, item) => acc + item.taxAmount);
  double get _grandTotal => _items.fold(0.0, (acc, item) => acc + item.totalAmount);

  void _addItem() async {
    final added = await showModalBottomSheet<_PurchaseItemEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddItemSheet(
        inventoryItems: _inventoryItems,
        currency: widget.session.currency,
      ),
    );
    if (added != null && mounted) {
      setState(() {
        _items.add(added);
        if (_initialPayment > _grandTotal) {
          _initialPayment = _grandTotal;
        }
      });
    }
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      if (_initialPayment > _grandTotal) {
        _initialPayment = _grandTotal;
      }
    });
  }

  Future<void> _submit() async {
    if (_selectedSupplierId == null) {
      ThqNotify.error(context, 'Validation', message: 'Please select a supplier.');
      return;
    }
    if (_items.isEmpty) {
      ThqNotify.error(context, 'Validation', message: 'Please add at least one line item.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Purchase Bill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Supplier: $_selectedSupplierName'),
            const SizedBox(height: 4),
            Text('Items: ${_items.length} line items'),
            const SizedBox(height: 4),
            Text(
              'Total: ${widget.session.currency} ${_grandTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Payment: ${widget.session.currency} ${_initialPayment.toStringAsFixed(2)} ($_paymentMethod)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Record Purchase'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final payloadItems = _items.map((item) => item.toMap()).toList();
      final result = await widget.service.createPurchase(
        widget.session,
        supplierId: _selectedSupplierId!,
        purchaseDate: _purchaseDate,
        dueDate: _dueDate,
        items: payloadItems,
        supplierInvoiceNumber: _invoiceNumberCtrl.text.trim(),
        additionalCharges: 0,
        roundOff: 0,
        initialPayment: _initialPayment,
        paymentMethod: _paymentMethod,
        paymentReference: _paymentRefCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        locationId: _effectiveLocationId,
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      final purchaseNum = result['purchase_number'] ?? result['document_number'] ?? 'Recorded';
      ThqNotify.success(context, 'Purchase Created', message: 'Purchase $purchaseNum posted successfully.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ThqNotify.error(context, 'Purchase Failed', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = widget.session.currency;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Purchase Bill'),
        actions: [
          IconButton(
            tooltip: 'Reload catalog',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadingDependencies ? null : _loadDependencies,
          ),
        ],
      ),
      body: _loadingDependencies
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                // Supplier Selection Card
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.business_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Supplier & Document Details',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pickSupplier,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _selectedSupplierId == null
                                    ? Theme.of(context).colorScheme.error.withValues(alpha: 0.5)
                                    : Theme.of(context).colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.store_mall_directory_outlined,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedSupplierName ?? 'Select Supplier *',
                                        style: TextStyle(
                                          fontWeight: _selectedSupplierName != null ? FontWeight.w600 : FontWeight.normal,
                                          color: _selectedSupplierName != null
                                              ? Theme.of(context).colorScheme.onSurface
                                              : Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _pickPurchaseDate,
                                borderRadius: BorderRadius.circular(10),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Bill Date',
                                    prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  child: Text(
                                    '${_purchaseDate.year}-${_purchaseDate.month.toString().padLeft(2, '0')}-${_purchaseDate.day.toString().padLeft(2, '0')}',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _invoiceNumberCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Supplier Inv #',
                                  hintText: 'e.g. INV-9021',
                                  prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Items Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Line Items (${_items.length})',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Item'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 36,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No items added yet',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap "Add Item" to add products from inventory or direct entry',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${item.quantity} ${item.unitCode} @ $currency ${item.unitPrice.toStringAsFixed(2)}'
                                    '${item.taxRate > 0 ? " • GST ${item.taxRate.toStringAsFixed(0)}%" : ""}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$currency ${item.totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () => _removeItem(idx),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 20,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 16),

                // Payment and Settlement Section
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Settlement & Payment',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _paymentMethod,
                                decoration: InputDecoration(
                                  labelText: 'Method',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                                  DropdownMenuItem(value: 'upi', child: Text('UPI / QR')),
                                  DropdownMenuItem(value: 'credit', child: Text('Credit / Later')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _paymentMethod = val;
                                      if (val == 'credit') {
                                        _initialPayment = 0;
                                      }
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                initialValue: _initialPayment.toStringAsFixed(2),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Initial Paid',
                                  prefixText: '$currency ',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                onChanged: (val) {
                                  final num = double.tryParse(val) ?? 0.0;
                                  setState(() => _initialPayment = num);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: _grandTotal > 0
                                  ? () => setState(() => _initialPayment = _grandTotal)
                                  : null,
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                              label: const Text('Pay In Full'),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => setState(() => _initialPayment = 0.0),
                              icon: const Icon(Icons.hourglass_empty_rounded, size: 16),
                              label: const Text('Pay Later (Full Credit)'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _notesCtrl,
                          decoration: InputDecoration(
                            labelText: 'Notes / Remarks',
                            hintText: 'Internal note or reference...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Calculation Summary
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(label: 'Taxable Subtotal', value: '$currency ${_subtotal.toStringAsFixed(2)}'),
                      const SizedBox(height: 4),
                      _SummaryRow(label: 'Total GST / Tax', value: '$currency ${_taxTotal.toStringAsFixed(2)}'),
                      const Divider(height: 14),
                      _SummaryRow(
                        label: 'Grand Total',
                        value: '$currency ${_grandTotal.toStringAsFixed(2)}',
                        isBold: true,
                        fontSize: 16,
                      ),
                      const SizedBox(height: 4),
                      _SummaryRow(
                        label: 'Initial Payment',
                        value: '$currency ${_initialPayment.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 4),
                      _SummaryRow(
                        label: 'Balance Payable',
                        value: '$currency ${(_grandTotal - _initialPayment).clamp(0.0, double.infinity).toStringAsFixed(2)}',
                        isBold: true,
                        color: (_grandTotal - _initialPayment) > 0 ? Theme.of(context).colorScheme.error : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomSheet: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                offset: const Offset(0, -3),
                blurRadius: 10,
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_submitting ? 'Recording Purchase...' : 'Confirm & Post Purchase ($currency ${_grandTotal.toStringAsFixed(2)})'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }

  void _pickSupplier() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _SupplierPickerSheet(suppliers: _suppliers),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedSupplierId = (selected['party_id'] ?? selected['supplier_id'] ?? selected['id']).toString();
        _selectedSupplierName = (selected['party_name'] ?? selected['supplier_name'] ?? selected['name']).toString();
      });
    }
  }

  void _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) {
      setState(() => _purchaseDate = picked);
    }
  }
}

class _PurchaseItemEntry {
  final String? variantId;
  final String name;
  final String unitCode;
  final double quantity;
  final double unitPrice;
  final double taxRate;

  _PurchaseItemEntry({
    this.variantId,
    required this.name,
    required this.unitCode,
    required this.quantity,
    required this.unitPrice,
    this.taxRate = 0.0,
  });

  double get discountAmount => 0.0;

  double get lineSubtotal => (quantity * unitPrice) - discountAmount;
  double get taxableAmount => lineSubtotal;
  double get taxAmount => taxableAmount * (taxRate / 100.0);
  double get totalAmount => taxableAmount + taxAmount;

  Map<String, dynamic> toMap() => {
        if (variantId != null) 'variant_id': variantId,
        if (variantId != null) 'product_id': variantId,
        'item_name': name,
        'unit_code': unitCode,
        'quantity': quantity,
        'unit_price': unitPrice,
        'tax_rate': taxRate,
        'discount_amount': discountAmount,
        'taxable_amount': taxableAmount,
        'tax_amount': taxAmount,
        'line_total': totalAmount,
      };
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final double fontSize;
  final Color? color;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.fontSize = 13,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _SupplierPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> suppliers;

  const _SupplierPickerSheet({required this.suppliers});

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _filter.trim().toLowerCase();
    final filtered = widget.suppliers.where((s) {
      if (q.isEmpty) return true;
      final name = (s['party_name'] ?? s['supplier_name'] ?? s['name'] ?? '').toString().toLowerCase();
      final phone = (s['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Select Supplier',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search by supplier name or phone...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (val) => setState(() => _filter = val),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No suppliers found'))
                : ListView.separated(
                    controller: scroll,
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = filtered[i];
                      final name = (item['party_name'] ?? item['supplier_name'] ?? item['name'] ?? 'Supplier').toString();
                      final phone = (item['phone'] ?? '').toString();
                      final due = item['outstanding'] ?? item['total_outstanding'];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'S'),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: phone.isNotEmpty ? Text(phone) : null,
                        trailing: due != null
                            ? Text(
                                'Due: $due',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddItemSheet extends StatefulWidget {
  final List<Map<String, dynamic>> inventoryItems;
  final String currency;

  const _AddItemSheet({
    required this.inventoryItems,
    required this.currency,
  });

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _rateCtrl = TextEditingController();
  final _customNameCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'pcs');

  Map<String, dynamic>? _selectedProduct;
  double _taxRate = 18.0;
  bool _customMode = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    _customNameCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  void _onProductSelected(Map<String, dynamic> product) {
    setState(() {
      _selectedProduct = product;
      final cost = product['cost_price'] ?? product['unit_price'] ?? product['purchase_rate'];
      if (cost != null) {
        _rateCtrl.text = cost.toString();
      }
      final unit = product['unit_code'] ?? product['base_unit'];
      if (unit != null) {
        _unitCtrl.text = unit.toString();
      }
      final gst = product['gst_rate'] ?? product['tax_rate'];
      if (gst != null) {
        _taxRate = (gst as num).toDouble();
      }
    });
  }

  void _done() {
    final name = _customMode
        ? _customNameCtrl.text.trim()
        : (_selectedProduct?['product_name'] ?? _selectedProduct?['name'] ?? '').toString();

    if (name.isEmpty) {
      ThqNotify.error(context, 'Validation', message: 'Please specify an item name.');
      return;
    }

    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0.0;
    if (qty <= 0) {
      ThqNotify.error(context, 'Validation', message: 'Quantity must be greater than zero.');
      return;
    }

    final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    if (rate <= 0) {
      ThqNotify.error(context, 'Validation', message: 'Purchase rate must be greater than zero.');
      return;
    }

    final entry = _PurchaseItemEntry(
      variantId: _customMode ? null : (_selectedProduct?['variant_id'] ?? _selectedProduct?['id'])?.toString(),
      name: name,
      unitCode: _unitCtrl.text.trim().isEmpty ? 'pcs' : _unitCtrl.text.trim(),
      quantity: qty,
      unitPrice: rate,
      taxRate: _taxRate,
    );

    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add Line Item',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => setState(() => _customMode = !_customMode),
                  child: Text(_customMode ? 'Pick from Products' : 'Custom Item Entry'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_customMode) ...[
              if (_selectedProduct == null) ...[
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search product in inventory...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _filteredInventory.length.clamp(0, 50),
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = _filteredInventory[i];
                      final name = (item['product_name'] ?? item['name'] ?? 'Product').toString();
                      final stock = item['quantity'] ?? item['stock'];
                      final unit = item['unit_code'] ?? 'pcs';
                      return ListTile(
                        dense: true,
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: stock != null ? Text('Stock: $stock $unit') : null,
                        onTap: () => _onProductSelected(item),
                      );
                    },
                  ),
                ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (_selectedProduct!['product_name'] ?? _selectedProduct!['name']).toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Selected product'),
                  trailing: TextButton(
                    onPressed: () => setState(() => _selectedProduct = null),
                    child: const Text('Change'),
                  ),
                ),
              ],
            ] else ...[
              TextField(
                controller: _customNameCtrl,
                decoration: InputDecoration(
                  labelText: 'Item Name *',
                  hintText: 'e.g. Bulk Cement 50kg',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Quantity *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _unitCtrl,
                    decoration: InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Rate *',
                      prefixText: '${widget.currency} ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<double>(
              initialValue: _taxRate,
              decoration: InputDecoration(
                labelText: 'GST Tax Rate',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 0.0, child: Text('0% (Exempt / Non-GST)')),
                DropdownMenuItem(value: 5.0, child: Text('5% GST')),
                DropdownMenuItem(value: 12.0, child: Text('12% GST')),
                DropdownMenuItem(value: 18.0, child: Text('18% GST')),
                DropdownMenuItem(value: 28.0, child: Text('28% GST')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _taxRate = val);
              },
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _done,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Add to Bill'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredInventory {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.inventoryItems;
    return widget.inventoryItems.where((item) {
      final name = (item['product_name'] ?? item['name'] ?? '').toString().toLowerCase();
      final sku = (item['sku'] ?? '').toString().toLowerCase();
      return name.contains(q) || sku.contains(q);
    }).toList();
  }
}
