import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../models/sale.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/sales_service.dart';
import 'sale_detail_screen.dart';

class SalesScreen extends StatefulWidget {
  final ClientSession session;

  const SalesScreen({super.key, required this.session});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final SalesService _service = SalesService();

  late Future<List<Sale>> _salesFuture;

  bool get _canManage => widget.session.hasPermission('sales.manage');

  @override
  void initState() {
    super.initState();

    _load();
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
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewSaleScreen(session: widget.session)),
    );

    if (created == true && mounted) {
      setState(_load);

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
                      const Text(
                        'Todayâ€™s Sales',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Invoices, payments and customer sales',
                        style: TextStyle(
                          fontSize: 8.3,
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
                if (_canManage) ...[
                  const SizedBox(width: 3),
                  FilledButton.icon(
                    onPressed: _newSale,
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('New Sale'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 5),
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

                final sales = snapshot.data ?? [];
                if (sales.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.point_of_sale_outlined,
                          size: 36,
                          color: scheme.outline,
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'No sales yet today.',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_canManage) ...[
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _newSale,
                            icon: const Icon(Icons.add, size: 15),
                            label: const Text('Create Sale'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                final total = sales.fold<double>(
                  0,
                  (sum, row) => sum + row.grandTotal,
                );
                final due = sales.fold<double>(
                  0,
                  (sum, row) => sum + row.balanceDue,
                );
                final profit = sales.fold<double>(
                  0,
                  (sum, row) => sum + row.grossProfit,
                );

                return Column(
                  children: [
                    SizedBox(
                      height: 54,
                      child: Row(
                        children: [
                          Expanded(
                            child: _salesMetric(
                              'Invoices',
                              '${sales.length}',
                              Icons.receipt_long_outlined,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _salesMetric(
                              'Sales',
                              _money(total),
                              Icons.point_of_sale_outlined,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _salesMetric(
                              'Balance Due',
                              _money(due),
                              Icons.schedule_outlined,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _salesMetric(
                              'Gross Profit',
                              _money(profit),
                              Icons.trending_up,
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
                              height: 34,
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
                                      'Invoice',
                                      style: TextStyle(
                                        fontSize: 8.8,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Customer',
                                      style: TextStyle(
                                        fontSize: 8.8,
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
                                        fontSize: 8.8,
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
                                        fontSize: 8.8,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Profit',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 8.8,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
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
                                  itemCount: sales.length,
                                  itemBuilder: (context, index) {
                                    final sale = sales[index];
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _openSale(sale),
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
                                                      sale.number,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 8.8,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    Text(
                                                      _date(sale.saleDate),
                                                      style: TextStyle(
                                                        fontSize: 7.2,
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  sale.customerName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _money(sale.grandTotal),
                                                  textAlign: TextAlign.right,
                                                  maxLines: 1,
                                                  style: const TextStyle(
                                                    fontSize: 8.7,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _money(sale.balanceDue),
                                                  textAlign: TextAlign.right,
                                                  maxLines: 1,
                                                  style: const TextStyle(
                                                    fontSize: 8.4,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _money(sale.grossProfit),
                                                  textAlign: TextAlign.right,
                                                  maxLines: 1,
                                                  style: const TextStyle(
                                                    fontSize: 8.4,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 105,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: _SalePaymentBadge(
                                                    status: sale.paymentStatus,
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

  Widget _salesMetric(String label, String value, IconData icon) {
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
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 7.3,
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

class NewSaleScreen extends StatefulWidget {
  final ClientSession session;

  const NewSaleScreen({super.key, required this.session});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final SalesService _salesService = SalesService();

  final CustomerService _customerService = CustomerService();

  final InventoryService _inventoryService = InventoryService();

  final TextEditingController _additionalController = TextEditingController(
    text: '0',
  );

  final TextEditingController _roundOffController = TextEditingController(
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

  double get _additional => 0.0;

  double get _roundOff {
    final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;
    return delta.abs() < 0.000001 ? 0.0 : delta;
  }

  double get _beforeRoundOff => _subtotal - _discount + _tax + _additional;

  double get _grandTotal => _beforeRoundOff + _roundOff;

  void _applyRoundOff() {
    final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;

    _roundOffController.text = delta.abs() < 0.000001
        ? '0.00'
        : delta.toStringAsFixed(2);

    setState(() {});
  }

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

    setState(() {
      _lines.add(line);
    });
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

    if (_number(_additionalController).abs() > 0.0001) {
      setState(() {
        _error =
            'Additional Charges were removed in Build 30. '
            'Add the charge as a GST-classified Service product.';
      });

      return;
    }

    if (_roundOff.abs() > 1.000001) {
      setState(() {
        _error = 'Round off must be between -1.00 and 1.00.';
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
      final paymentAllocations = <Map<String, dynamic>>[];

      if (_paymentMethod == 'credit') {
        paymentAllocations.add(<String, dynamic>{
          'method_code': 'credit',
          'tendered_amount': _grandTotal,
          'reference_number': '',
        });
      } else {
        if (_payment > 0.005) {
          paymentAllocations.add(<String, dynamic>{
            'method_code': _paymentMethod,
            'tendered_amount': _payment,
            'reference_number': _paymentReferenceController.text.trim(),
          });
        }

        if (_balanceDue > 0.005) {
          paymentAllocations.add(<String, dynamic>{
            'method_code': 'credit',
            'tendered_amount': _balanceDue,
            'reference_number': '',
          });
        }
      }

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
                if (line.serialNumbers.isNotEmpty)
                  'serial_numbers': line.serialNumbers,
              },
            )
            .toList(),

        paymentAllocations: paymentAllocations,

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
    _additionalController.dispose();

    _roundOffController.dispose();

    _paymentController.dispose();

    _paymentReferenceController.dispose();

    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(
        title: const Text(
          'New Sale',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _customers.isEmpty
          ? const Center(child: Text('No active customers available.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(28),

              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1150),

                  child: Column(
                    children: [
                      _customerCard(),

                      const SizedBox(height: 20),

                      _itemsCard(),

                      const SizedBox(height: 20),

                      _paymentCard(),
                    ],
                  ),
                ),
              ),
            ),
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
                    label: 'Additional Charges',

                    value: _money(_additional),
                  ),

                  if (_roundOff.abs() > 0.000001)
                    _SaleTotalRow(label: 'Round Off', value: _money(_roundOff)),

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
  final List<String> serialNumbers;

  const _SaleLine({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    this.serialNumbers = const [],
  });

  String get unitCode => unit?.code ?? product.baseUnitCode;
  double get baseQuantity => quantity * (unit?.conversionToBase ?? 1);
  double get subtotal => quantity * unitPrice;

  double get taxable => subtotal - discount;

  double get tax => taxable * taxRate / 100;

  double get total => taxable + tax;
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

  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );

  final TextEditingController _priceController = TextEditingController();

  final TextEditingController _discountController = TextEditingController(
    text: '0',
  );

  final TextEditingController _taxController = TextEditingController();
  final TextEditingController _serialsController = TextEditingController();

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

      _serialsController.clear();

      if (product != null) {
        final unit = product.defaultSaleUnit;
        _unitId = unit?.unitId;
        _priceController.text =
            (unit?.salePriceFor(product.sellingPrice) ?? product.sellingPrice)
                .toStringAsFixed(2);

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

  List<String> _serialValues() => _serialsController.text
      .split(RegExp(r'[\n,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

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
        quantity * (selectedUnit?.conversionToBase ?? 1) >
            product.stockQuantity + 0.0001) {
      setState(() {
        _error =
            'Insufficient stock. Available: '
            '${product.stockQuantity.toStringAsFixed(2)}';
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
        serialNumbers: product.trackingMode == 'serial'
            ? serialNumbers
            : const [],
      ),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();

    _priceController.dispose();

    _discountController.dispose();

    _taxController.dispose();
    _serialsController.dispose();

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
            DropdownButtonFormField<String>(
              initialValue: _variantId,

              isExpanded: true,

              decoration: const InputDecoration(
                labelText: 'Product',

                border: OutlineInputBorder(),
              ),

              items: widget.products
                  .map(
                    (product) => DropdownMenuItem(
                      value: product.variantId,

                      child: Text(
                        '${product.productName} — ${product.sku}',

                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),

              onChanged: _selectProduct,
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
                    .map(
                      (u) => DropdownMenuItem(
                        value: u.unitId,
                        child: Text(
                          '${u.name} (${u.code}) • 1 = ${u.conversionToBase} ${product.baseUnitCode}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _unitId = value;
                    final unit = _selectedUnit;
                    if (unit != null) {
                      _priceController.text = unit
                          .salePriceFor(product.sellingPrice)
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
                    controller: _priceController,

                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),

                    decoration: const InputDecoration(
                      labelText: 'Selling Price',

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
                  labelText: 'Serial numbers to sell',
                  hintText: 'Scan or enter one serial per base unit',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_product?.trackingMode == 'batch') ...[
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Batch stock will be allocated automatically using FEFO (earliest expiry first).',
                ),
              ),
            ],

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
              ],
            ),
          ),

          Expanded(child: Text(_quantity(line.quantity))),

          Expanded(child: Text(money(line.unitPrice))),

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
