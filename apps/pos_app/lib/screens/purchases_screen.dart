import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
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
  final bool historyOnly;

  const PurchasesScreen({
    super.key,
    required this.session,
    this.historyOnly = false,
  });

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

      ThqNotify.showSnackBar(
        context,
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
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.historyOnly
                            ? 'Purchase History'
                            : 'Today’s Purchases',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.historyOnly
                            ? 'Legacy direct-purchase history'
                            : 'Purchase bills and stock received',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
                if (_canManage && !widget.historyOnly) ...[
                  const SizedBox(width: 3),
                  FilledButton.icon(
                    onPressed: _newPurchase,
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('New Purchase'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
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
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh, size: 15),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final purchases = snapshot.data ?? [];
                if (purchases.isEmpty) {
                  return Center(
                    child: Text(
                      widget.historyOnly
                          ? 'No purchase history.'
                          : 'No purchases yet today.',
                    ),
                  );
                }

                final total = purchases.fold<double>(
                  0,
                  (sum, row) => sum + row.grandTotal,
                );
                final due = purchases.fold<double>(
                  0,
                  (sum, row) => sum + row.balanceDue,
                );

                return Column(
                  children: [
                    SizedBox(
                      height: 54,
                      child: Row(
                        children: [
                          Expanded(
                            child: _purchaseMetric(
                              'Bills',
                              '${purchases.length}',
                              Icons.receipt_long_outlined,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _purchaseMetric(
                              'Purchases',
                              _money(total),
                              Icons.shopping_cart_outlined,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _purchaseMetric(
                              'Balance Due',
                              _money(due),
                              Icons.schedule_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              color: scheme.surfaceContainerHighest.withValues(
                                alpha: .45,
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Purchase',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Supplier / Invoice',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Total',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Due',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  SizedBox(width: 105),
                                  SizedBox(width: 28),
                                ],
                              ),
                            ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: _refresh,
                                child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.zero,
                                  itemCount: purchases.length,
                                  itemBuilder: (context, index) {
                                    final purchase = purchases[index];
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _openPurchase(purchase),
                                        child: Container(
                                          constraints: const BoxConstraints(
                                            minHeight: 46,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: scheme.outlineVariant,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 2,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      purchase.number,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    Text(
                                                      _date(
                                                        purchase.purchaseDate,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      purchase.supplierName,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    Text(
                                                      purchase.supplierInvoiceNumber ??
                                                          'No supplier invoice',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _money(purchase.grandTotal),
                                                  textAlign: TextAlign.right,
                                                  maxLines: 1,
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _money(purchase.balanceDue),
                                                  textAlign: TextAlign.right,
                                                  maxLines: 1,
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              SizedBox(
                                                width: 105,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: _PaymentBadge(
                                                    status:
                                                        purchase.paymentStatus,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(
                                                width: 28,
                                                child: Icon(
                                                  Icons.chevron_right,
                                                  size: 15,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _purchaseMetric(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
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

  final _roundOffController = TextEditingController(text: '0');

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

  double get _roundOff => _number(_roundOffController);

  double get _beforeRoundOff => _subtotal - _discount + _tax + _additional;

  double get _grandTotal => _beforeRoundOff + _roundOff;

  void _applyRoundOff() {
    final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;
    _roundOffController.text = delta.abs() < 0.000001
        ? '0.00'
        : delta.toStringAsFixed(2);
    setState(() {});
  }

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
      ThqNotify.showSnackBar(
        context,
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

    if (_roundOff.abs() > 1.000001) {
      setState(() {
        _error = 'Round off must be between -1.00 and 1.00.';
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
                if (line.serialNumbers.isNotEmpty)
                  'serial_numbers': line.serialNumbers,
                if (line.batches.isNotEmpty) 'batches': line.batches,
              },
            )
            .toList(),
        additionalCharges: additional,
        roundOff: _roundOff,
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
    _roundOffController.dispose();
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

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _roundOffController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Round Off',
                    helperText: 'Post-tax adjustment (-1.00 to 1.00)',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _saving ? null : _applyRoundOff,
                icon: const Icon(Icons.exposure_zero),
                label: const Text('Round Total'),
              ),
              const Spacer(flex: 2),
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
                  if (_roundOff.abs() > 0.000001)
                    _TotalRow(label: 'Round Off', value: _money(_roundOff)),
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
  final List<String> serialNumbers;
  final List<Map<String, dynamic>> batches;

  const _PurchaseLine({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.discount,
    required this.taxRate,
    this.serialNumbers = const [],
    this.batches = const [],
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
  final _serialsController = TextEditingController();
  final List<Map<String, dynamic>> _batches = [];

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

      _serialsController.clear();
      _batches.clear();

      if (product != null) {
        final unit = product.defaultPurchaseUnit;
        _unitId = unit?.unitId;
        _costController.text =
            (unit?.purchaseCostFor(product.costPrice) ?? product.costPrice)
                .toStringAsFixed(2);
        _taxController.text = product.taxRate.toStringAsFixed(2);
      }
    });
  }

  List<String> _serialValues() => _serialsController.text
      .split(RegExp(r'[\n,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _addBatch() async {
    final batch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PurchaseBatchDialog(),
    );
    if (batch != null && mounted) setState(() => _batches.add(batch));
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

    final baseQuantity = quantity * (selectedUnit?.conversionToBase ?? 1);
    final serialNumbers = _serialValues();
    if (product.trackingMode == 'serial') {
      if (baseQuantity != baseQuantity.truncateToDouble()) {
        setState(
          () => _error =
              'Serial-tracked products require a whole base-unit quantity.',
        );
        return;
      }
      if (serialNumbers.length != baseQuantity.round()) {
        setState(
          () => _error =
              'Serial count must match the base quantity (${baseQuantity.toStringAsFixed(0)}).',
        );
        return;
      }
    }
    if (product.trackingMode == 'batch') {
      final batchQuantity = _batches.fold<double>(
        0,
        (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0),
      );
      if ((batchQuantity - baseQuantity).abs() > 0.000001) {
        setState(
          () => _error =
              'Batch quantities must total the base quantity (${baseQuantity.toStringAsFixed(4)}).',
        );
        return;
      }
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
        serialNumbers: product.trackingMode == 'serial'
            ? serialNumbers
            : const [],
        batches: product.trackingMode == 'batch'
            ? List<Map<String, dynamic>>.from(_batches)
            : const [],
      ),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    _discountController.dispose();
    _taxController.dispose();
    _serialsController.dispose();

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
                    .map(
                      (u) => DropdownMenuItem(
                        value: u.unitId,
                        child: Text(
                          '${u.name} (${u.code}) • 1 = ${u.conversionToBase} ${_product!.baseUnitCode}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _unitId = value;
                    final unit = _selectedUnit;
                    if (unit != null) {
                      _costController.text = unit
                          .purchaseCostFor(_product!.costPrice)
                          .toStringAsFixed(2);
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

            if (_product?.trackingMode == 'serial') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _serialsController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Serial numbers (one per base unit)',
                  hintText: 'SN0001\nSN0002',
                  border: OutlineInputBorder(),
                ),
              ),
            ],

            if (_product?.trackingMode == 'batch') ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Batch allocation',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              ..._batches.asMap().entries.map(
                (entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${entry.value['batch_number']} • ${entry.value['quantity']} ${_product?.baseUnitCode ?? ''}',
                  ),
                  subtitle: Text(
                    'MFG ${entry.value['manufactured_on'] ?? '-'} • EXP ${entry.value['expiry_on'] ?? '-'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _batches.removeAt(entry.key)),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addBatch,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Batch'),
                ),
              ),
            ],

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

class _PurchaseBatchDialog extends StatefulWidget {
  const _PurchaseBatchDialog();
  @override
  State<_PurchaseBatchDialog> createState() => _PurchaseBatchDialogState();
}

class _PurchaseBatchDialogState extends State<_PurchaseBatchDialog> {
  final _number = TextEditingController();
  final _quantity = TextEditingController();
  final _manufactured = TextEditingController();
  final _expiry = TextEditingController();
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
      setState(
        () => _error = 'Enter a batch number and positive base quantity.',
      );
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'batch_number': _number.text.trim(),
      'quantity': qty,
      'manufactured_on': _manufactured.text.trim().isEmpty
          ? null
          : _manufactured.text.trim(),
      'expiry_on': _expiry.text.trim().isEmpty ? null : _expiry.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Batch'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _number,
            decoration: const InputDecoration(
              labelText: 'Batch / lot number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Quantity in base unit',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _manufactured,
            decoration: const InputDecoration(
              labelText: 'Manufacture date (YYYY-MM-DD)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _expiry,
            decoration: const InputDecoration(
              labelText: 'Expiry date (YYYY-MM-DD)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Add')),
    ],
  );
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
