import 'dart:async';

import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../models/sale.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/pricing_service.dart';
import '../services/sales_service.dart';
import 'sale_detail_screen.dart';

class SalesScreen extends StatefulWidget {
  final ClientSession session;
  final bool startInCreate;
  final bool historyOnly;

  const SalesScreen({
    super.key,
    required this.session,
    this.startInCreate = false,
    this.historyOnly = false,
  });

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final SalesService _service = SalesService();

  late Future<List<Sale>> _salesFuture;

  bool _creating = false;

  bool get _canManage => widget.session.hasPermission('sales.manage');

  @override
  void initState() {
    super.initState();
    LocationScopeService.selectedLocationId.addListener(_locationChanged);
    _load();
    _creating =
        widget.startInCreate &&
        _canManage &&
        LocationScopeService.selectedLocationId.value != null;
  }

  void _locationChanged() {
    if (!mounted) return;
    setState(() {
      _load();
      if (widget.startInCreate && _canManage) {
        _creating = LocationScopeService.selectedLocationId.value != null;
      }
    });
  }

  @override
  void dispose() {
    LocationScopeService.selectedLocationId.removeListener(_locationChanged);
    super.dispose();
  }

  void _load() {
    _salesFuture = _service.getSales(tenantId: widget.session.business.id);
  }

  Future<void> _refresh() async {
    setState(_load);

    await _salesFuture;
  }

  Future<void> _openSale(Sale sale) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SaleDetailScreen(session: widget.session, saleId: sale.id),
      ),
    );

    if (!mounted) return;
    setState(_load);
  }

  Future<void> _newSale() async {
    if (LocationScopeService.selectedLocationId.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select a specific store before creating a transaction. All Stores is view-only.',
          ),
        ),
      );
      return;
    }
    setState(() => _creating = true);
  }

  void _finishNewSale(bool created) {
    if (!mounted) return;
    setState(() {
      _creating = false;
      if (created) _load();
    });
    if (created) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sale completed successfully.')),
      );
    }
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
    if (widget.startInCreate && !_canManage) {
      return const Center(
        child: Text('You do not have permission to create sales.'),
      );
    }
    if (widget.startInCreate &&
        LocationScopeService.selectedLocationId.value == null) {
      return const Center(
        child: Text(
          'Select a specific store above to start a new sale. All Stores is view-only.',
        ),
      );
    }
    if (widget.startInCreate && !_creating) {
      return Center(
        child: FilledButton.icon(
          onPressed: _newSale,
          icon: const Icon(Icons.add),
          label: const Text('Start New Sale'),
        ),
      );
    }
    if (_creating) {
      return NewSaleScreen(
        session: widget.session,
        locationId: LocationScopeService.currentForCreate(widget.session),
        embedded: true,
        onFinished: _finishNewSale,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),

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
                      widget.historyOnly ? 'Sales History' : 'Sales',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    SizedBox(height: 5),

                    Text('Invoices, payments and customer sales'),
                  ],
                ),
              ),

              if (_canManage && !widget.historyOnly)
                FilledButton.icon(
                  onPressed: _newSale,
                  icon: const Icon(Icons.add),
                  label: const Text('New Sale'),
                ),
            ],
          ),

          const SizedBox(height: 14),

          Expanded(
            child: FutureBuilder<List<Sale>>(
              future: _salesFuture,

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

                        const SizedBox(height: 16),

                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 18),

                        OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final sales = snapshot.data ?? [];

                if (sales.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.point_of_sale_outlined, size: 72),

                        const SizedBox(height: 18),

                        const Text(
                          'No Sales Yet',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Create your first sales invoice.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),

                        if (_canManage && !widget.historyOnly) ...[
                          const SizedBox(height: 22),

                          FilledButton.icon(
                            onPressed: _newSale,
                            icon: const Icon(Icons.add),
                            label: const Text('Create First Sale'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,

                  child: ListView.separated(
                    itemCount: sales.length,

                    separatorBuilder: (_, _) => const SizedBox(height: 10),

                    itemBuilder: (context, index) {
                      final sale = sales[index];

                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openSale(sale),
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
                                      sale.number,

                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      _date(sale.saleDate),

                                      style: TextStyle(
                                        fontSize: 12,

                                        color: Colors.grey.shade600,
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
                                      sale.customerName,

                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      'Customer',

                                      style: TextStyle(
                                        fontSize: 11,

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
                                      _money(sale.grandTotal),

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
                                      _money(sale.balanceDue),

                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
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
                                      'Gross Profit',

                                      style: TextStyle(
                                        fontSize: 11,

                                        color: Colors.grey.shade600,
                                      ),
                                    ),

                                    const SizedBox(height: 3),

                                    Text(
                                      _money(sale.grossProfit),

                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              _SalePaymentBadge(status: sale.paymentStatus),
                              const SizedBox(width: 8),
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

class NewSaleScreen extends StatefulWidget {
  final ClientSession session;
  final String locationId;
  final bool embedded;
  final ValueChanged<bool>? onFinished;

  const NewSaleScreen({
    super.key,
    required this.session,
    required this.locationId,
    this.embedded = false,
    this.onFinished,
  });

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final SalesService _salesService = SalesService();

  final CustomerService _customerService = CustomerService();

  final PricingService _pricingService = PricingService();

  final InventoryService _inventoryService = InventoryService();

  final TextEditingController _additionalController = TextEditingController(
    text: '0',
  );

  final TextEditingController _paymentController = TextEditingController(
    text: '0',
  );

  final TextEditingController _paymentReferenceController =
      TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String? _error;

  List<Customer> _customers = [];

  List<InventoryProduct> _products = [];

  String? _customerId;

  DateTime _saleDate = DateTime.now();

  DateTime? _dueDate;

  String _paymentMethod = 'cash';

  final List<_SaleLine> _lines = [];

  Customer? get _selectedCustomer {
    final id = _customerId;

    if (id == null) {
      return null;
    }

    for (final customer in _customers) {
      if (customer.id == id) {
        return customer;
      }
    }

    return null;
  }

  @override
  void initState() {
    super.initState();

    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final customersFuture = _customerService.getCustomers(
        tenantId: widget.session.business.id,
      );

      final productsFuture = _inventoryService.getProducts(
        tenantId: widget.session.business.id,
        locationId: widget.locationId,
      );

      final customers = await customersFuture;

      final products = await productsFuture;

      if (!mounted) {
        return;
      }

      final activeCustomers = customers
          .where((customer) => customer.isActive)
          .toList();

      final activeProducts = products
          .where(
            (product) =>
                product.productStatus == 'active' &&
                product.variantStatus == 'active',
          )
          .toList();

      String? initialCustomer;

      for (final customer in activeCustomers) {
        if (customer.isWalkIn) {
          initialCustomer = customer.id;

          break;
        }
      }

      initialCustomer ??= activeCustomers.isEmpty
          ? null
          : activeCustomers.first.id;

      setState(() {
        _customers = activeCustomers;

        _products = activeProducts;

        _customerId = initialCustomer;

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

  double get _cuttingCharges =>
      _lines.fold(0, (total, line) => total + line.cuttingCharge);

  double get _additional => _number(_additionalController) + _cuttingCharges;

  double get _grandTotal => _subtotal - _discount + _tax + _additional;

  double get _payment => _number(_paymentController);

  double get _balanceDue => _grandTotal - _payment;

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

  Future<void> _chooseSaleDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        _saleDate = date;

        if (_dueDate != null && _dueDate!.isBefore(date)) {
          _dueDate = null;
        }
      });
    }
  }

  Future<void> _chooseDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _saleDate,
      firstDate: _saleDate,
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        _dueDate = date;
      });
    }
  }

  Future<_SaleLine> _resolvedLine(_SaleLine line) async {
    final price = await _pricingService.resolve(
      tenantId: widget.session.business.id,
      variantId: line.product.variantId,
      customerId: _customerId,
      unitId: line.unit?.unitId,
      quantity: line.quantity,
      locationId: widget.locationId,
    );
    return line.copyWith(unitPrice: price.unitPrice, pricingSource: price.sourceLabel);
  }

  Future<void> _repriceLines() async {
    if (_lines.isEmpty) return;
    try {
      final repriced = await Future.wait(_lines.map(_resolvedLine));
      if (!mounted) return;
      setState(() {
        _lines
          ..clear()
          ..addAll(repriced);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh customer pricing: $error')),
      );
    }
  }

  Future<void> _addLine() async {
    final available = _products.where((product) {
      return !_lines.any((line) => line.product.variantId == product.variantId);
    }).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more products available to add.')),
      );

      return;
    }

    final line = await showDialog<_SaleLine>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddSaleItemDialog(products: available),
    );

    if (line == null || !mounted) {
      return;
    }

    try {
      final pricedLine = await _resolvedLine(line);
      if (!mounted) return;
      setState(() {
        _lines.add(pricedLine);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve selling price: $error')),
      );
    }
  }

  void _payFull() {
    setState(() {
      _paymentController.text = _grandTotal.toStringAsFixed(2);
    });
  }

  Future<void> _post() async {
    final customer = _selectedCustomer;

    if (customer == null) {
      setState(() {
        _error = 'Select a customer.';
      });

      return;
    }

    if (_lines.isEmpty) {
      setState(() {
        _error = 'Add at least one product.';
      });

      return;
    }

    if (_additional < 0) {
      setState(() {
        _error = 'Additional charges cannot be negative.';
      });

      return;
    }

    if (_payment < 0) {
      setState(() {
        _error = 'Payment cannot be negative.';
      });

      return;
    }

    if (_payment > _grandTotal + 0.0001) {
      setState(() {
        _error = 'Payment cannot exceed the sale total.';
      });

      return;
    }

    if (customer.isWalkIn && _balanceDue > 0.0001) {
      setState(() {
        _error =
            'Walk-in Customer sales must be fully paid. Use Pay Full before completing the sale.';
      });

      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _salesService.createSale(
        tenantId: widget.session.business.id,

        customerId: customer.id,

        saleDate: _saleDate,

        dueDate: _dueDate,

        items: _lines
            .map(
              (line) => {
                'variant_id': line.product.variantId,

                'quantity': line.quantity,

                'unit_id': line.unit?.unitId,

                'unit_price': line.unitPrice,

                'discount_amount': line.discount,

                'tax_rate': line.taxRate,
              },
            )
            .toList(),

        additionalCharges: _additional,

        initialPayment: _payment,

        paymentMethod: _paymentMethod,

        paymentReference: _paymentReferenceController.text,

        notes: _notesController.text,
        locationId: widget.locationId,
      );

      if (!mounted) {
        return;
      }

      if (widget.embedded) {
        widget.onFinished?.call(true);
      } else {
        Navigator.of(context).pop(true);
      }
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
    _additionalController.dispose();

    _paymentController.dispose();

    _paymentReferenceController.dispose();

    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _customers.isEmpty
        ? const Center(child: Text('No active customers available.'))
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1150),
                child: Column(
                  children: [
                    if (widget.embedded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: _saving
                                  ? null
                                  : () => widget.onFinished?.call(false),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'New Sale',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _customerCard(),
                    const SizedBox(height: 14),
                    _itemsCard(),
                    const SizedBox(height: 14),
                    _paymentCard(),
                  ],
                ),
              ),
            ),
          );
    if (widget.embedded) {
      return ColoredBox(color: const Color(0xFFF5F7FA), child: content);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'New Sale',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: content,
    );
  }

  Widget _customerCard() {
    final customer = _selectedCustomer;

    return _SaleCard(
      title: 'Sale Details',

      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,

                child: DropdownButtonFormField<String>(
                  initialValue: _customerId,

                  isExpanded: true,

                  decoration: const InputDecoration(
                    labelText: 'Customer *',

                    border: OutlineInputBorder(),
                  ),

                  items: _customers
                      .map(
                        (customer) => DropdownMenuItem(
                          value: customer.id,

                          child: Text(
                            customer.isWalkIn
                                ? '${customer.name} — Counter Sale'
                                : customer.name,

                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),

                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() {
                            _customerId = value;

                            _error = null;
                          });
                          unawaited(_repriceLines());
                        },
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _chooseSaleDate,

                  icon: const Icon(Icons.calendar_month),

                  label: Text('Sale Date: ${_date(_saleDate)}'),
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

          if (customer != null) ...[
            const SizedBox(height: 14),

            Align(
              alignment: Alignment.centerLeft,

              child: Wrap(
                spacing: 12,
                runSpacing: 8,

                children: [
                  if (customer.isWalkIn)
                    const Chip(
                      avatar: Icon(Icons.storefront, size: 17),
                      label: Text('Walk-in sale — full payment required'),
                    )
                  else
                    Chip(
                      avatar: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 17,
                      ),

                      label: Text(
                        customer.creditLimit > 0
                            ? 'Credit limit: ${_money(customer.creditLimit)}'
                            : 'No configured credit limit',
                      ),
                    ),

                  if (customer.phone != null)
                    Chip(
                      avatar: const Icon(Icons.phone_outlined, size: 17),
                      label: Text(customer.phone!),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemsCard() {
    return _SaleCard(
      title: 'Items',

      trailing: FilledButton.icon(
        onPressed: _saving ? null : _addLine,

        icon: const Icon(Icons.add),

        label: const Text('Add Product'),
      ),

      child: _lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 38),

              child: Center(child: Text('No products added yet.')),
            )
          : Column(
              children: [
                for (var i = 0; i < _lines.length; i++)
                  _SaleLineRow(
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

  Widget _paymentCard() {
    return _SaleCard(
      title: 'Totals & Payment',

      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Expanded(
                child: TextField(
                  controller: _additionalController,

                  enabled: !_saving,

                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),

                  onChanged: (_) {
                    setState(() {});
                  },

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

                  onChanged: (_) {
                    setState(() {});
                  },

                  decoration: const InputDecoration(
                    labelText: 'Payment Received',

                    prefixText: '₹ ',

                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Padding(
                padding: const EdgeInsets.only(top: 4),

                child: OutlinedButton(
                  onPressed: _saving ? null : _payFull,

                  child: const Text('Pay Full'),
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

                    DropdownMenuItem(value: 'upi', child: Text('UPI')),

                    DropdownMenuItem(value: 'card', child: Text('Card')),

                    DropdownMenuItem(value: 'bank', child: Text('Bank')),

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
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _paymentReferenceController,

                  enabled: !_saving,

                  decoration: const InputDecoration(
                    labelText: 'Payment Reference',

                    hintText: 'UPI / bank / card reference',

                    border: OutlineInputBorder(),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: TextField(
                  controller: _notesController,

                  enabled: !_saving,

                  decoration: const InputDecoration(
                    labelText: 'Notes',

                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Align(
            alignment: Alignment.centerRight,

            child: SizedBox(
              width: 420,

              child: Column(
                children: [
                  _SaleTotalRow(label: 'Subtotal', value: _money(_subtotal)),

                  _SaleTotalRow(
                    label: 'Discount',

                    value: '- ${_money(_discount)}',
                  ),

                  _SaleTotalRow(label: 'Tax', value: _money(_tax)),

                  _SaleTotalRow(
                    label: _cuttingCharges > 0 ? 'Additional / Cutting Charges' : 'Additional Charges',

                    value: _money(_additional),
                  ),

                  const Divider(),

                  _SaleTotalRow(
                    label: 'Grand Total',

                    value: _money(_grandTotal),

                    bold: true,
                  ),

                  _SaleTotalRow(label: 'Received', value: _money(_payment)),

                  _SaleTotalRow(
                    label: 'Balance Due',

                    value: _money(_balanceDue),

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
                    : const Icon(Icons.point_of_sale_outlined),

                label: Text(_saving ? 'Completing...' : 'Complete Sale'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaleLine {
  final InventoryProduct product;

  final ProductUnitOption? unit;

  final double quantity;

  final double unitPrice;

  final double discount;

  final double taxRate;

  final bool cuttingChargeApplied;

  final String? pricingSource;

  const _SaleLine({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    required this.cuttingChargeApplied,
    this.pricingSource,
  });

  String get unitCode => unit?.code ?? product.baseUnitCode;
  double get baseQuantity => quantity * (unit?.conversionToBase ?? 1);
  double get subtotal => quantity * unitPrice;

  double get taxable => subtotal - discount;

  double get tax => taxable * taxRate / 100;

  double get cuttingCharge =>
      cuttingChargeApplied ? (unit?.cuttingCharge ?? 0) : 0;

  double get total => taxable + tax + cuttingCharge;

  _SaleLine copyWith({double? unitPrice, String? pricingSource}) => _SaleLine(
        product: product,
        unit: unit,
        quantity: quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        discount: discount,
        taxRate: taxRate,
        cuttingChargeApplied: cuttingChargeApplied,
        pricingSource: pricingSource ?? this.pricingSource,
      );
}

class _AddSaleItemDialog extends StatefulWidget {
  final List<InventoryProduct> products;

  const _AddSaleItemDialog({required this.products});

  @override
  State<_AddSaleItemDialog> createState() => _AddSaleItemDialogState();
}

class _AddSaleItemDialogState extends State<_AddSaleItemDialog> {
  String? _variantId;

  String? _unitId;
  bool _cuttingChargeApplied = false;

  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );

  final TextEditingController _priceController = TextEditingController();

  final TextEditingController _discountController = TextEditingController(
    text: '0',
  );

  final TextEditingController _taxController = TextEditingController();

  String? _error;

  InventoryProduct? get _product {
    final id = _variantId;

    if (id == null) {
      return null;
    }

    for (final product in widget.products) {
      if (product.variantId == id) {
        return product;
      }
    }

    return null;
  }

  ProductUnitOption? get _selectedUnit {
    final product = _product;
    if (product == null) return null;
    for (final unit in product.saleUnits) {
      if (unit.unitId == _unitId) return unit;
    }
    return product.defaultSaleUnit;
  }

  void _selectProduct(String? value) {
    setState(() {
      _variantId = value;

      final product = _product;

      if (product != null) {
        final unit = product.defaultSaleUnit;
        _unitId = unit?.unitId;
        _cuttingChargeApplied = false;
        _priceController.text = (unit?.salePriceFor(product.sellingPrice) ?? product.sellingPrice).toStringAsFixed(2);

        _taxController.text = product.taxRate.toStringAsFixed(2);

        _error = null;
      }
    });
  }

  String _stockText(InventoryProduct product) {
    if (product.itemType != 'stock') {
      return product.itemType == 'service' ? 'Service' : 'Non-stock';
    }

    return 'Stock: '
        '${product.stockQuantity.toStringAsFixed(2)} '
        '${product.baseUnitCode}';
  }

  void _add() {
    final product = _product;

    final quantity = double.tryParse(_quantityController.text.trim());

    final price = double.tryParse(_priceController.text.trim());

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

    if (product.itemType == 'stock' &&
        quantity * (selectedUnit?.conversionToBase ?? 1) > product.stockQuantity + 0.0001) {
      setState(() {
        _error =
            'Insufficient stock. Available: '
            '${product.stockQuantity.toStringAsFixed(2)}';
      });

      return;
    }

    if (price == null || price < 0) {
      setState(() {
        _error = 'Enter a valid selling price.';
      });

      return;
    }

    if (discount < 0 || discount > quantity * price) {
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
      _SaleLine(
        product: product,

        unit: selectedUnit,

        quantity: quantity,

        unitPrice: price,

        discount: discount,

        taxRate: tax,
        cuttingChargeApplied: _cuttingChargeApplied,
      ),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();

    _priceController.dispose();

    _discountController.dispose();

    _taxController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;

    return AlertDialog(
      title: const Text('Add Sale Item'),

      content: SizedBox(
        width: 680,

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            Autocomplete<InventoryProduct>(
              displayStringForOption: (p) => '${p.productName} — ${p.sku}',
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return widget.products.take(12);
                return widget.products
                    .where(
                      (p) =>
                          p.productName.toLowerCase().contains(q) ||
                          p.sku.toLowerCase().contains(q) ||
                          (p.partNumber ?? '').toLowerCase().contains(q) ||
                          (p.barcode ?? '').toLowerCase().contains(q) ||
                          p.searchCodes.toLowerCase().contains(q),
                    )
                    .take(20);
              },
              onSelected: (p) => _selectProduct(p.variantId),
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Search Product',
                      hintText: 'Type name, SKU, part number or barcode',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
            ),

            if (product != null) ...[
              const SizedBox(height: 10),

              Align(
                alignment: Alignment.centerLeft,

                child: Wrap(
                  spacing: 10,

                  children: [
                    Chip(label: Text(_stockText(product))),

                    if (product.partNumber != null)
                      Chip(label: Text('Part: ${product.partNumber}')),
                  ],
                ),
              ),
            ],

            if ((product?.saleUnits.length ?? 0) > 1) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _unitId,
                decoration: const InputDecoration(
                  labelText: 'Sale Unit',
                  border: OutlineInputBorder(),
                ),
                items: product!.saleUnits
                    .map((u) => DropdownMenuItem(
                          value: u.unitId,
                          child: Text('${u.name} (${u.code}) • 1 = ${u.conversionToBase} ${product.baseUnitCode}'),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _unitId = value;
                    _cuttingChargeApplied = false;
                    final unit = _selectedUnit;
                    if (unit != null) {
                      _priceController.text = unit.salePriceFor(product.sellingPrice).toStringAsFixed(2);
                    }
                  });
                },
              ),
            ],

            if ((_selectedUnit?.cuttingAllowed ?? false) &&
                (_selectedUnit?.cuttingCharge ?? 0) > 0) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _cuttingChargeApplied,
                onChanged: (value) => setState(() => _cuttingChargeApplied = value),
                title: Text(
                  'Add cutting charge ₹${(_selectedUnit?.cuttingCharge ?? 0).toStringAsFixed(2)}',
                ),
                subtitle: const Text(
                  'Optional charge added once for this line.',
                ),
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
                    controller: _priceController,

                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),

                    decoration: const InputDecoration(
                      labelText: 'Base / Preview Price',

                      prefixText: '₹ ',

                      border: OutlineInputBorder(),
                      helperText: 'THQ pricing is resolved again for the selected customer and quantity.',
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

              Align(
                alignment: Alignment.centerLeft,

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
          onPressed: () => Navigator.of(context).pop(),

          child: const Text('Cancel'),
        ),

        FilledButton(onPressed: _add, child: const Text('Add Item')),
      ],
    );
  }
}

class _SaleLineRow extends StatelessWidget {
  final _SaleLine line;

  final String Function(double) money;

  final VoidCallback? onDelete;

  const _SaleLineRow({
    required this.line,
    required this.money,
    required this.onDelete,
  });

  String _quantity(double value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(2);
  }

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
                  [line.product.sku, line.product.partNumber]
                      .where((value) => value != null && value.isNotEmpty)
                      .join(' • '),

                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (line.cuttingCharge > 0)
                  Text(
                    'Cutting charge ${money(line.cuttingCharge)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),

          Expanded(child: Text('${_quantity(line.quantity)} ${line.unitCode}')),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(money(line.unitPrice)),
                if (line.pricingSource?.isNotEmpty == true)
                  Text(line.pricingSource!, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),

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

class _SaleCard extends StatelessWidget {
  final String title;

  final Widget child;

  final Widget? trailing;

  const _SaleCard({required this.title, required this.child, this.trailing});

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

class _SaleTotalRow extends StatelessWidget {
  final String label;

  final String value;

  final bool bold;

  const _SaleTotalRow({
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

class _SalePaymentBadge extends StatelessWidget {
  final String status;

  const _SalePaymentBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color background;
    Color foreground;

    switch (status) {
      case 'paid':
        background = Colors.green.shade50;

        foreground = Colors.green.shade700;

      case 'partial':
        background = Colors.orange.shade50;

        foreground = Colors.orange.shade800;

      default:
        background = Colors.red.shade50;

        foreground = Colors.red.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

      decoration: BoxDecoration(
        color: background,

        borderRadius: BorderRadius.circular(20),
      ),

      child: Text(
        status.toUpperCase(),

        style: TextStyle(
          fontSize: 11,

          fontWeight: FontWeight.bold,

          color: foreground,
        ),
      ),
    );
  }
}
