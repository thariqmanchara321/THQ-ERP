import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../models/inventory_product.dart';
import '../models/purchase.dart';
import '../models/supplier.dart';
import '../services/inventory_service.dart';
import '../services/purchase_service.dart';
import '../services/supplier_service.dart';
import 'purchase_detail_screen.dart';

class PurchasesScreen extends StatefulWidget {
  final ClientSession session;

  const PurchasesScreen({super.key, required this.session});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final PurchaseService _service = PurchaseService();

  late Future<List<Purchase>> _purchasesFuture;

  bool get _canManage => widget.session.hasPermission('purchases.manage');

  @override
  void initState() {
    super.initState();

    _load();
  }

  void _load() {
    _purchasesFuture = _service.getPurchases(
      tenantId: widget.session.business.id,
    );
  }

  Future<void> _refresh() async {
    setState(_load);

    await _purchasesFuture;
  }

  Future<void> _newPurchase() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewPurchaseScreen(session: widget.session),
      ),
    );

    if (created == true && mounted) {
      setState(_load);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase posted successfully.')),
      );
    }
  }

  Future<void> _openPurchase(Purchase purchase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseDetailScreen(
          session: widget.session,
          purchaseId: purchase.id,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(_load);
  }

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }

    return '${widget.session.currencyCode} '
        '${value.toStringAsFixed(2)}';
  }

  String _date(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today’s Purchases',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text('Today’s purchase bills and stock received • use Terminal Daily for history'),
                  ],
                ),
              ),

              if (_canManage)
                FilledButton.icon(
                  onPressed: _newPurchase,
                  icon: const Icon(Icons.add),
                  label: const Text('New Purchase'),
                ),
            ],
          ),

          const SizedBox(height: 24),

          Expanded(
            child: FutureBuilder<List<Purchase>>(
              future: _purchasesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 56),
                        const SizedBox(height: 14),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final purchases = snapshot.data ?? [];

                if (purchases.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_cart_outlined, size: 70),
                        const SizedBox(height: 18),
                        const Text(
                          'No Purchases Yet',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_canManage) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _newPurchase,
                            icon: const Icon(Icons.add),
                            label: const Text('Create First Purchase'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    itemCount: purchases.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final purchase = purchases[index];

                      return InkWell(
                        borderRadius: BorderRadius.circular(16),

                        onTap: () => _openPurchase(purchase),

                        child: Container(
                          padding: const EdgeInsets.all(18),

                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),

                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      purchase.number,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      _date(purchase.purchaseDate),
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      purchase.supplierName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      purchase.supplierInvoiceNumber ??
                                          'No supplier invoice',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Total',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),

                                    const SizedBox(height: 3),

                                    Text(
                                      _money(purchase.grandTotal),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Balance Due',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),

                                    const SizedBox(height: 3),

                                    Text(
                                      _money(purchase.balanceDue),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              _PaymentBadge(status: purchase.paymentStatus),

                              const SizedBox(width: 10),

                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class NewPurchaseScreen extends StatefulWidget {
  final ClientSession session;

  const NewPurchaseScreen({super.key, required this.session});

  @override
  State<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<NewPurchaseScreen> {
  final PurchaseService _purchaseService = PurchaseService();

  final SupplierService _supplierService = SupplierService();

  final InventoryService _inventoryService = InventoryService();

  final _invoiceController = TextEditingController();

  final _additionalController = TextEditingController(text: '0');

  final _paymentController = TextEditingController(text: '0');

  final _notesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String? _error;

  List<Supplier> _suppliers = [];
  List<InventoryProduct> _products = [];

  String? _supplierId;

  DateTime _purchaseDate = DateTime.now();

  DateTime? _dueDate;

  String _paymentMethod = 'cash';

  final List<_PurchaseLine> _lines = [];

  @override
  void initState() {
    super.initState();

    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _supplierService.getSuppliers(tenantId: widget.session.business.id),
        _inventoryService.getProducts(
          tenantId: widget.session.business.id,
          locationId: widget.session.device?.locationId,
        ),
      ]);

      if (!mounted) {
        return;
      }

      final suppliers = results[0] as List<Supplier>;

      final products = results[1] as List<InventoryProduct>;

      setState(() {
        _suppliers = suppliers.where((supplier) => supplier.isActive).toList();

        _products = products
            .where(
              (product) =>
                  product.itemType == 'stock' &&
                  product.productStatus == 'active' &&
                  product.variantStatus == 'active',
            )
            .toList();

        if (_suppliers.isNotEmpty) {
          _supplierId = _suppliers.first.id;
        }

        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  double _number(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double get _subtotal =>
      _lines.fold(0, (total, line) => total + line.subtotal);

  double get _discount =>
      _lines.fold(0, (total, line) => total + line.discount);

  double get _tax => _lines.fold(0, (total, line) => total + line.tax);

  double get _additional => _number(_additionalController);

  double get _grandTotal => _subtotal - _discount + _tax + _additional;

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }

    return '${widget.session.currencyCode} '
        '${value.toStringAsFixed(2)}';
  }

  Future<void> _addLine() async {
    final available = _products
        .where(
          (product) => !_lines.any(
            (line) => line.product.variantId == product.variantId,
          ),
        )
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more products available to add.')),
      );

      return;
    }

    final line = await showDialog<_PurchaseLine>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddPurchaseItemDialog(products: available),
    );

    if (line != null && mounted) {
      setState(() {
        _lines.add(line);
      });
    }
  }

  Future<void> _choosePurchaseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        _purchaseDate = date;

        if (_dueDate != null && _dueDate!.isBefore(date)) {
          _dueDate = null;
        }
      });
    }
  }

  Future<void> _chooseDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _purchaseDate,
      firstDate: _purchaseDate,
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        _dueDate = date;
      });
    }
  }

  String _date(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.year}';
  }

  Future<void> _post() async {
    if (_supplierId == null) {
      setState(() {
        _error = 'Select a supplier.';
      });
      return;
    }

    if (_lines.isEmpty) {
      setState(() {
        _error = 'Add at least one product.';
      });
      return;
    }

    final additional = _number(_additionalController);

    final payment = _number(_paymentController);

    if (additional < 0) {
      setState(() {
        _error = 'Additional charges cannot be negative.';
      });
      return;
    }

    if (payment < 0) {
      setState(() {
        _error = 'Payment cannot be negative.';
      });
      return;
    }

    if (payment > _grandTotal + 0.0001) {
      setState(() {
        _error = 'Payment cannot exceed grand total.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _purchaseService.createPurchase(
        tenantId: widget.session.business.id,
        supplierId: _supplierId!,
        supplierInvoiceNumber: _invoiceController.text,
        purchaseDate: _purchaseDate,
        dueDate: _dueDate,
        items: _lines
            .map(
              (line) => {
                'variant_id': line.product.variantId,
                'quantity': line.quantity,
                'unit_id': line.unit?.unitId,
                'unit_cost': line.unitCost,
                'discount_amount': line.discount,
                'tax_rate': line.taxRate,
              },
            )
            .toList(),
        additionalCharges: additional,
        initialPayment: payment,
        paymentMethod: _paymentMethod,
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
    _invoiceController.dispose();
    _additionalController.dispose();
    _paymentController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'New Purchase',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _suppliers.isEmpty
          ? Center(child: Text(_error!))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    children: [
                      _headerCard(),
                      const SizedBox(height: 20),
                      _itemsCard(),
                      const SizedBox(height: 20),
                      _summaryCard(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _headerCard() {
    return _PurchaseCard(
      title: 'Purchase Details',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _supplierId,
            decoration: const InputDecoration(
              labelText: 'Supplier *',
              border: OutlineInputBorder(),
            ),
            items: _suppliers
                .map(
                  (supplier) => DropdownMenuItem(
                    value: supplier.id,
                    child: Text(supplier.name),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) {
                    setState(() {
                      _supplierId = value;
                    });
                  },
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _invoiceController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Supplier Invoice No.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _choosePurchaseDate,
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Purchase Date: ${_date(_purchaseDate)}'),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _chooseDueDate,
                  icon: const Icon(Icons.event),
                  label: Text(
                    _dueDate == null
                        ? 'Set Due Date'
                        : 'Due: ${_date(_dueDate!)}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemsCard() {
    return _PurchaseCard(
      title: 'Items',
      trailing: FilledButton.icon(
        onPressed: _saving ? null : _addLine,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      child: _lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 35),
              child: Center(child: Text('No products added yet.')),
            )
          : Column(
              children: [
                for (var i = 0; i < _lines.length; i++)
                  _PurchaseLineRow(
                    line: _lines[i],
                    money: _money,
                    onDelete: _saving
                        ? null
                        : () {
                            setState(() {
                              _lines.removeAt(i);
                            });
                          },
                  ),
              ],
            ),
    );
  }

  Widget _summaryCard() {
    return _PurchaseCard(
      title: 'Totals & Payment',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _additionalController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Additional Charges',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _paymentController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Initial Payment',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<String>(
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
                          if (value != null) {
                            setState(() {
                              _paymentMethod = value;
                            });
                          }
                        },
                ),
              ),
            ],
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

          const SizedBox(height: 22),

          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 380,
              child: Column(
                children: [
                  _TotalRow(label: 'Subtotal', value: _money(_subtotal)),
                  _TotalRow(label: 'Discount', value: '- ${_money(_discount)}'),
                  _TotalRow(label: 'Tax', value: _money(_tax)),
                  _TotalRow(
                    label: 'Additional Charges',
                    value: _money(_additional),
                  ),
                  const Divider(),
                  _TotalRow(
                    label: 'Grand Total',
                    value: _money(_grandTotal),
                    bold: true,
                  ),
                  _TotalRow(
                    label: 'Payment',
                    value: _money(_number(_paymentController)),
                  ),
                  _TotalRow(
                    label: 'Balance Due',
                    value: _money(_grandTotal - _number(_paymentController)),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 18),
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

          const SizedBox(height: 22),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _post,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'Posting...' : 'Post Purchase'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PurchaseLine {
  final InventoryProduct product;
  final ProductUnitOption? unit;
  final double quantity;
  final double unitCost;
  final double discount;
  final double taxRate;

  const _PurchaseLine({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.discount,
    required this.taxRate,
  });

  String get unitCode => unit?.code ?? product.baseUnitCode;
  double get baseQuantity => quantity * (unit?.conversionToBase ?? 1);
  double get subtotal => quantity * unitCost;

  double get taxable => subtotal - discount;

  double get tax => taxable * taxRate / 100;

  double get total => taxable + tax;
}

class _AddPurchaseItemDialog extends StatefulWidget {
  final List<InventoryProduct> products;

  const _AddPurchaseItemDialog({required this.products});

  @override
  State<_AddPurchaseItemDialog> createState() => _AddPurchaseItemDialogState();
}

class _AddPurchaseItemDialogState extends State<_AddPurchaseItemDialog> {
  String? _variantId;
  String? _unitId;

  final _quantityController = TextEditingController(text: '1');

  final _costController = TextEditingController();

  final _discountController = TextEditingController(text: '0');

  final _taxController = TextEditingController();

  String? _error;

  InventoryProduct? get _product {
    if (_variantId == null) {
      return null;
    }

    for (final product in widget.products) {
      if (product.variantId == _variantId) {
        return product;
      }
    }

    return null;
  }

  ProductUnitOption? get _selectedUnit {
    final product = _product;
    if (product == null) return null;
    for (final unit in product.purchaseUnits) {
      if (unit.unitId == _unitId) return unit;
    }
    return product.defaultPurchaseUnit;
  }

  void _selectProduct(String? value) {
    setState(() {
      _variantId = value;

      final product = _product;

      if (product != null) {
        final unit = product.defaultPurchaseUnit;
        _unitId = unit?.unitId;
        _costController.text = (unit?.purchaseCostFor(product.costPrice) ?? product.costPrice).toStringAsFixed(2);
        _taxController.text = product.taxRate.toStringAsFixed(2);
      }
    });
  }

  void _add() {
    final product = _product;

    final quantity = double.tryParse(_quantityController.text.trim());

    final cost = double.tryParse(_costController.text.trim());

    final discount = double.tryParse(_discountController.text.trim()) ?? 0;

    final tax = double.tryParse(_taxController.text.trim()) ?? 0;

    if (product == null) {
      setState(() {
        _error = 'Select a product.';
      });
      return;
    }

    if (quantity == null || quantity <= 0) {
      setState(() {
        _error = 'Quantity must be greater than zero.';
      });
      return;
    }

    final selectedUnit = _selectedUnit;
    if (selectedUnit != null && !selectedUnit.acceptsQuantity(quantity)) {
      setState(() {
        _error = selectedUnit.allowFractional
            ? '${selectedUnit.code} quantity must use increments of ${selectedUnit.quantityStep}.'
            : '${selectedUnit.code} only allows whole quantities in increments of ${selectedUnit.quantityStep}.';
      });
      return;
    }

    if (cost == null || cost < 0) {
      setState(() {
        _error = 'Enter a valid purchase cost.';
      });
      return;
    }

    if (discount < 0 || discount > quantity * cost) {
      setState(() {
        _error = 'Invalid discount amount.';
      });
      return;
    }

    if (tax < 0 || tax > 100) {
      setState(() {
        _error = 'Tax must be between 0 and 100.';
      });
      return;
    }

    Navigator.of(context).pop(
      _PurchaseLine(
        product: product,
        unit: _selectedUnit,
        quantity: quantity,
        unitCost: cost,
        discount: discount,
        taxRate: tax,
      ),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    _discountController.dispose();
    _taxController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Product'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _variantId,
              decoration: const InputDecoration(
                labelText: 'Product',
                border: OutlineInputBorder(),
              ),
              items: widget.products
                  .map(
                    (product) => DropdownMenuItem(
                      value: product.variantId,
                      child: Text('${product.productName} — ${product.sku}'),
                    ),
                  )
                  .toList(),
              onChanged: _selectProduct,
            ),

            if ((_product?.purchaseUnits.length ?? 0) > 1) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _unitId,
                decoration: const InputDecoration(
                  labelText: 'Purchase Unit',
                  border: OutlineInputBorder(),
                ),
                items: _product!.purchaseUnits
                    .map((u) => DropdownMenuItem(value: u.unitId, child: Text('${u.name} (${u.code}) • 1 = ${u.conversionToBase} ${_product!.baseUnitCode}')))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _unitId = value;
                    final unit = _selectedUnit;
                    if (unit != null) {
                      _costController.text = unit.purchaseCostFor(_product!.costPrice).toStringAsFixed(2);
                    }
                  });
                },
              ),
            ],

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Unit Cost',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _discountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Discount Amount',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _taxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tax Rate',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _add, child: const Text('Add Item')),
      ],
    );
  }
}

class _PurchaseLineRow extends StatelessWidget {
  final _PurchaseLine line;

  final String Function(double) money;

  final VoidCallback? onDelete;

  const _PurchaseLineRow({
    required this.line,
    required this.money,
    required this.onDelete,
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
                  line.product.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  line.product.sku,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          Expanded(child: Text('${line.quantity} ${line.unitCode}')),

          Expanded(child: Text(money(line.unitCost))),

          Expanded(child: Text(money(line.discount))),

          Expanded(child: Text('${line.taxRate.toStringAsFixed(2)}%')),

          Expanded(
            child: Text(
              money(line.total),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _PurchaseCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _PurchaseCard({
    required this.title,
    required this.child,
    this.trailing,
  });

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
          const SizedBox(height: 20),
          child,
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

class _PaymentBadge extends StatelessWidget {
  final String status;

  const _PaymentBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final text = status.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status == 'paid'
            ? Colors.green.shade50
            : status == 'partial'
            ? Colors.orange.shade50
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
