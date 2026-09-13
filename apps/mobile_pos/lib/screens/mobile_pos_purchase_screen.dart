import 'package:flutter/material.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';
import '../services/mobile_pos_local_store.dart';
import '../services/mobile_pos_purchase_service.dart';
import '../services/mobile_pos_sync_service.dart';

class MobilePosPurchaseScreen extends StatefulWidget {
  final PosSession session;
  final bool offlineMode;

  const MobilePosPurchaseScreen({
    super.key,
    required this.session,
    required this.offlineMode,
  });

  @override
  State<MobilePosPurchaseScreen> createState() =>
      _MobilePosPurchaseScreenState();
}

class _MobilePosPurchaseScreenState extends State<MobilePosPurchaseScreen> {
  final MobilePosPurchaseService _service = MobilePosPurchaseService();
  final MobilePosLocalStore _local = MobilePosLocalStore.instance;
  final MobilePosSyncService _sync = MobilePosSyncService();
  final TextEditingController _invoice = TextEditingController();
  final TextEditingController _payment = TextEditingController(text: '0');
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<MobileSupplier> _suppliers = const [];
  List<MobileProduct> _products = const [];
  String? _supplierId;
  DateTime _purchaseDate = DateTime.now();
  DateTime? _dueDate;
  String _paymentMethod = 'cash';
  final List<_MobilePurchaseLine> _lines = <_MobilePurchaseLine>[];

  bool get _moduleBlocked =>
      widget.session.allowedModules.isNotEmpty &&
      !widget.session.hasDeviceModule('purchases');

  MobileSupplier? get _supplier {
    final id = _supplierId;
    if (id == null) return null;
    for (final row in _suppliers) {
      if (row.id == id) return row;
    }
    return null;
  }

  double get _subtotal =>
      _lines.fold<double>(0, (sum, row) => sum + row.subtotal);
  double get _discount =>
      _lines.fold<double>(0, (sum, row) => sum + row.discount);
  double get _tax => _lines.fold<double>(0, (sum, row) => sum + row.tax);
  double get _previewTotal => _subtotal - _discount + _tax;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _invoice.dispose();
    _payment.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _products = await _local.products(
        widget.session.tenantId,
        widget.session.locationId,
      );
      if (!widget.offlineMode && !_moduleBlocked) {
        _suppliers = await _service.suppliers(widget.session);
        if (_supplierId == null && _suppliers.isNotEmpty) {
          _supplierId = _suppliers.first.id;
        }
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(double value) => widget.session.currencyCode == 'INR'
      ? '₹${value.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _purchaseDate = picked;
      if (_dueDate != null && _dueDate!.isBefore(picked)) _dueDate = null;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _purchaseDate,
      firstDate: _purchaseDate,
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  Future<void> _addItem() async {
    if (_products.isEmpty) {
      setState(() => _error = 'No cached products are available. Sync the POS first.');
      return;
    }
    final used = _lines.map((row) => row.product.variantId).toSet();
    final available = _products
        .where((row) => !used.contains(row.variantId))
        .toList(growable: false);
    final line = await showDialog<_MobilePurchaseLine>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MobilePurchaseItemDialog(
        products: available.isEmpty ? _products : available,
      ),
    );
    if (line != null && mounted) {
      setState(() {
        _lines.add(line);
        _error = null;
      });
    }
  }

  List<Map<String, dynamic>> _preparedItems() => _lines
      .map(
        (line) => <String, dynamic>{
          'variant_id': line.product.variantId,
          'quantity': line.quantity,
          'unit_id': line.unit.unitId.isEmpty ? null : line.unit.unitId,
          'unit_cost': line.unitCost,
          'discount_amount': line.discount,
          'tax_rate': line.taxRate,
          if (line.serialNumbers.isNotEmpty)
            'serial_numbers': List<String>.from(line.serialNumbers),
          if (line.batches.isNotEmpty)
            'batches': line.batches
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
        },
      )
      .toList();

  double _num(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _post() async {
    if (widget.offlineMode) {
      setState(() => _error =
          'Purchase posting is online-only. Go online and Sync before confirming a purchase.');
      return;
    }
    if (_moduleBlocked) {
      setState(() => _error =
          'This POS terminal is not enabled for the Purchases module. Enable Purchases for this terminal in Admin.');
      return;
    }
    if (_supplierId == null) {
      setState(() => _error = 'Select a supplier.');
      return;
    }
    if (_invoice.text.trim().isEmpty) {
      setState(() => _error =
          'Supplier invoice number is required for an authoritative GST purchase.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    final requestedPayment = double.tryParse(_payment.text.trim()) ?? 0;
    if (requestedPayment < 0) {
      setState(() => _error = 'Initial payment cannot be negative.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final items = _preparedItems();
      final baseQuote = await _service.quote(
        session: widget.session,
        supplierId: _supplierId!,
        purchaseDate: _purchaseDate,
        items: items,
        roundOff: 0,
      );
      final baseTotals = baseQuote['totals'] is Map
          ? Map<String, dynamic>.from(baseQuote['totals'] as Map)
          : <String, dynamic>{};
      final beforeRound = _num(baseTotals['grand_total']);
      final calculatedRound = beforeRound.roundToDouble() - beforeRound;
      final roundOff = calculatedRound.abs() < 0.000001 ? 0.0 : calculatedRound;
      final finalQuote = roundOff == 0
          ? baseQuote
          : await _service.quote(
              session: widget.session,
              supplierId: _supplierId!,
              purchaseDate: _purchaseDate,
              items: items,
              roundOff: roundOff,
            );
      final finalTotals = finalQuote['totals'] is Map
          ? Map<String, dynamic>.from(finalQuote['totals'] as Map)
          : <String, dynamic>{};
      final authoritativeTotal = _num(finalTotals['grand_total']);
      if (requestedPayment > authoritativeTotal + 0.005) {
        throw StateError(
          'Initial payment cannot exceed authoritative purchase total ${_money(authoritativeTotal)}.',
        );
      }

      final result = await _service.create(
        session: widget.session,
        supplierId: _supplierId!,
        supplierInvoiceNumber: _invoice.text,
        purchaseDate: _purchaseDate,
        dueDate: _dueDate,
        items: items,
        roundOff: roundOff,
        initialPayment: requestedPayment,
        paymentMethod: _paymentMethod,
        paymentReference: _reference.text,
        notes: _notes.text,
      );

      try {
        await _sync.refreshCatalogue(widget.session);
      } catch (_) {}
      if (!mounted) return;
      final number = result['purchase_number']?.toString() ?? 'Purchase';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$number posted with authoritative GST evidence.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final blocked = widget.offlineMode || _moduleBlocked;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (blocked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: scheme.errorContainer,
                child: Text(
                  widget.offlineMode
                      ? 'Purchase posting requires an online authoritative GST check. Sales can continue offline; purchases cannot be queued through a legacy path.'
                      : 'Purchases are disabled for this POS terminal. Enable the Purchases module for the device in Admin.',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                color: scheme.errorContainer.withValues(alpha: .65),
                child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _section(
                      context,
                      title: 'Supplier & Invoice',
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _supplierId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Supplier *',
                              prefixIcon: Icon(Icons.local_shipping_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: _suppliers
                                .map(
                                  (row) => DropdownMenuItem<String>(
                                    value: row.id,
                                    child: Text(
                                      row.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: blocked || _saving
                                ? null
                                : (value) => setState(() => _supplierId = value),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _invoice,
                            enabled: !blocked && !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Supplier Invoice No. *',
                              prefixIcon: Icon(Icons.tag_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: blocked || _saving
                                      ? null
                                      : _pickPurchaseDate,
                                  icon: const Icon(Icons.calendar_month_outlined),
                                  label: Text('Invoice ${_date(_purchaseDate)}'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: blocked || _saving ? null : _pickDueDate,
                                  icon: const Icon(Icons.event_outlined),
                                  label: Text(_dueDate == null
                                      ? 'Due date'
                                      : _date(_dueDate!)),
                                ),
                              ),
                            ],
                          ),
                          if (_supplier != null &&
                              (_supplier!.taxNumber.isNotEmpty ||
                                  _supplier!.state.isNotEmpty)) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                [
                                  if (_supplier!.taxNumber.isNotEmpty)
                                    'GSTIN ${_supplier!.taxNumber}',
                                  if (_supplier!.state.isNotEmpty)
                                    _supplier!.state,
                                ].join(' • '),
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _section(
                      context,
                      title: 'Items (${_lines.length})',
                      trailing: FilledButton.icon(
                        onPressed: blocked || _saving ? null : _addItem,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Product'),
                      ),
                      child: _lines.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text('Add a product to start this purchase.'),
                              ),
                            )
                          : Column(
                              children: _lines.asMap().entries.map((entry) {
                                final row = entry.value;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    row.product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${row.quantity} ${row.unit.code} × ${_money(row.unitCost)} • GST ${row.taxRate.toStringAsFixed(2)}%'
                                    '${row.discount > 0 ? ' • Disc ${_money(row.discount)}' : ''}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _money(row.total),
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove',
                                        onPressed: _saving
                                            ? null
                                            : () => setState(
                                                  () => _lines.removeAt(entry.key),
                                                ),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(height: 10),
                    _section(
                      context,
                      title: 'Payment & Totals',
                      child: Column(
                        children: [
                          _totalRow('Subtotal', _subtotal),
                          _totalRow('Discount', -_discount),
                          _totalRow('GST preview', _tax),
                          const Divider(),
                          _totalRow('Preview total', _previewTotal, strong: true),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: _paymentMethod,
                                  decoration: const InputDecoration(
                                    labelText: 'Payment Method',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                    DropdownMenuItem(value: 'card', child: Text('Card')),
                                    DropdownMenuItem(value: 'upi', child: Text('UPI')),
                                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                                    DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                                    DropdownMenuItem(value: 'other', child: Text('Other')),
                                  ],
                                  onChanged: blocked || _saving
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(() => _paymentMethod = value);
                                          }
                                        },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _payment,
                                  enabled: !blocked && !_saving,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Initial Payment',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _reference,
                            enabled: !blocked && !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Payment Reference',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _notes,
                            enabled: !blocked && !_saving,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Notes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_lines.length} item(s) • ${_money(_previewTotal)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: blocked || _saving ? null : _post,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_saving ? 'Confirming...' : 'Confirm Purchase'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
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
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              _money(value),
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _MobilePurchaseLine {
  final MobileProduct product;
  final MobilePurchaseUnit unit;
  final double quantity;
  final double unitCost;
  final double discount;
  final double taxRate;
  final List<String> serialNumbers;
  final List<Map<String, dynamic>> batches;

  const _MobilePurchaseLine({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.discount,
    required this.taxRate,
    required this.serialNumbers,
    required this.batches,
  });

  double get subtotal => quantity * unitCost;
  double get tax =>
      (subtotal - discount).clamp(0.0, double.infinity) * taxRate / 100;
  double get total => subtotal - discount + tax;
}

class _MobilePurchaseItemDialog extends StatefulWidget {
  final List<MobileProduct> products;

  const _MobilePurchaseItemDialog({required this.products});

  @override
  State<_MobilePurchaseItemDialog> createState() =>
      _MobilePurchaseItemDialogState();
}

class _MobilePurchaseItemDialogState extends State<_MobilePurchaseItemDialog> {
  final TextEditingController _qty = TextEditingController(text: '1');
  final TextEditingController _cost = TextEditingController();
  final TextEditingController _discount = TextEditingController(text: '0');
  final TextEditingController _tax = TextEditingController();
  final TextEditingController _serials = TextEditingController();
  MobileProduct? _product;
  MobilePurchaseUnit? _unit;
  final List<Map<String, dynamic>> _batches = <Map<String, dynamic>>[];
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _discount.dispose();
    _tax.dispose();
    _serials.dispose();
    super.dispose();
  }

  Iterable<MobileProduct> _options(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return widget.products.take(40);
    return widget.products.where((row) {
      return row.name.toLowerCase().contains(q) ||
          row.sku.toLowerCase().contains(q) ||
          row.barcode.toLowerCase().contains(q) ||
          row.searchCodes.toLowerCase().contains(q);
    }).take(40);
  }

  void _select(MobileProduct product) {
    final unit = product.defaultPurchaseUnit;
    setState(() {
      _product = product;
      _unit = unit;
      _cost.text = (unit.purchaseCost > 0 ? unit.purchaseCost : product.costPrice)
          .toStringAsFixed(2);
      _tax.text = product.taxRate.toStringAsFixed(2);
      _batches.clear();
      _serials.clear();
      _error = null;
    });
  }

  List<String> _serialValues() => _serials.text
      .split(RegExp(r'[\n,;]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _addBatch() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _MobileBatchDialog(),
    );
    if (result != null && mounted) setState(() => _batches.add(result));
  }

  void _save() {
    final product = _product;
    final unit = _unit;
    final qty = double.tryParse(_qty.text.trim());
    final cost = double.tryParse(_cost.text.trim());
    final discount = double.tryParse(_discount.text.trim()) ?? 0;
    final tax = double.tryParse(_tax.text.trim()) ?? 0;
    if (product == null || unit == null) {
      setState(() => _error = 'Select a product.');
      return;
    }
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Quantity must be greater than zero.');
      return;
    }
    if (unit.quantityStep > 0) {
      final steps = qty / unit.quantityStep;
      if ((steps - steps.roundToDouble()).abs() > 0.000001) {
        setState(() => _error =
            '${unit.code} quantity must use increments of ${unit.quantityStep}.');
        return;
      }
    }
    if (cost == null || cost < 0) {
      setState(() => _error = 'Enter a valid purchase cost.');
      return;
    }
    if (discount < 0 || discount > qty * cost) {
      setState(() => _error = 'Discount cannot exceed the line value.');
      return;
    }
    if (tax < 0 || tax > 100) {
      setState(() => _error = 'Tax rate must be between 0 and 100.');
      return;
    }

    final baseQty = qty * unit.conversionToBase;
    final serials = _serialValues();
    if (product.trackingMode == 'serial') {
      if ((baseQty - baseQty.roundToDouble()).abs() > 0.000001 ||
          serials.length != baseQty.round()) {
        setState(() => _error =
            'Serial count must exactly match the whole base quantity (${baseQty.toStringAsFixed(0)}).');
        return;
      }
    }
    if (product.trackingMode == 'batch') {
      final allocated = _batches.fold<double>(
        0,
        (sum, row) => sum + numberValue(row['quantity']),
      );
      if ((allocated - baseQty).abs() > 0.000001) {
        setState(() => _error =
            'Batch quantities must total the base quantity (${baseQty.toStringAsFixed(4)}).');
        return;
      }
    }

    Navigator.of(context).pop(
      _MobilePurchaseLine(
        product: product,
        unit: unit,
        quantity: qty,
        unitCost: cost,
        discount: discount,
        taxRate: tax,
        serialNumbers: product.trackingMode == 'serial' ? serials : const [],
        batches: product.trackingMode == 'batch'
            ? List<Map<String, dynamic>>.from(_batches)
            : const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Add Purchase Product'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<MobileProduct>(
              displayStringForOption: (row) => '${row.name} — ${row.sku}',
              optionsBuilder: (value) => _options(value.text),
              onSelected: _select,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                  TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Product / SKU / Barcode',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_product != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_product!.name} • ${_product!.trackingMode.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (_product!.purchaseUnits.length > 1) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _unit?.unitId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Purchase Unit',
                    border: OutlineInputBorder(),
                  ),
                  items: _product!.purchaseUnits
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: row.unitId,
                          child: Text('${row.name} (${row.code})'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    for (final row in _product!.purchaseUnits) {
                      if (row.unitId == value) {
                        setState(() {
                          _unit = row;
                          _cost.text = (row.purchaseCost > 0
                                  ? row.purchaseCost
                                  : _product!.costPrice)
                              .toStringAsFixed(2);
                        });
                        break;
                      }
                    }
                  },
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _cost,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Unit Cost',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _discount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Discount Amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _tax,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Tax Rate %',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              if (_product!.trackingMode == 'serial') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _serials,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Serial Numbers',
                    hintText: 'One per line, comma or semicolon',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_product!.trackingMode == 'batch') ...[
                const SizedBox(height: 10),
                ..._batches.asMap().entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value['batch_number']?.toString() ?? ''),
                    subtitle: Text('Qty ${entry.value['quantity']}'),
                    trailing: IconButton(
                      onPressed: () =>
                          setState(() => _batches.removeAt(entry.key)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _addBatch,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Batch / Lot'),
                  ),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add Item')),
      ],
    );
  }
}

class _MobileBatchDialog extends StatefulWidget {
  const _MobileBatchDialog();

  @override
  State<_MobileBatchDialog> createState() => _MobileBatchDialogState();
}

class _MobileBatchDialogState extends State<_MobileBatchDialog> {
  final TextEditingController _number = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _manufactured = TextEditingController();
  final TextEditingController _expiry = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _quantity.dispose();
    _manufactured.dispose();
    _expiry.dispose();
    super.dispose();
  }

  void _save() {
    final qty = double.tryParse(_quantity.text.trim());
    if (_number.text.trim().isEmpty || qty == null || qty <= 0) {
      setState(() => _error = 'Enter a batch number and quantity greater than zero.');
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'batch_number': _number.text.trim(),
      'quantity': qty,
      if (_manufactured.text.trim().isNotEmpty)
        'manufactured_on': _manufactured.text.trim(),
      if (_expiry.text.trim().isNotEmpty) 'expiry_on': _expiry.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Batch / Lot'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Batch / Lot Number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Base Quantity',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _manufactured,
            decoration: const InputDecoration(
              labelText: 'Manufactured On (YYYY-MM-DD)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _expiry,
            decoration: const InputDecoration(
              labelText: 'Expiry On (YYYY-MM-DD)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Add Batch')),
      ],
    );
  }
}

