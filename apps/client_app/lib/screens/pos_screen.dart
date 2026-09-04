import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/pricing_service.dart';
import '../services/sales_service.dart';
import '../widgets/searchable_select.dart';

class PosScreen extends StatefulWidget {
  final ClientSession session;

  const PosScreen({super.key, required this.session});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final InventoryService _inventory = InventoryService();
  final CustomerService _customersService = CustomerService();
  final SalesService _sales = SalesService();
  final PricingService _pricing = PricingService();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _tendered = TextEditingController();
  final List<_PosLine> _cart = <_PosLine>[];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<InventoryProduct> _products = <InventoryProduct>[];
  List<Customer> _customers = <Customer>[];
  String? _customerId;
  String _paymentMethod = 'cash';
  double _roundOff = 0.0;

  bool get _canUse {
    return widget.session.hasPermission('pos.use') ||
        widget.session.hasPermission('sales.manage') ||
        widget.session.hasRole('owner');
  }

  Customer? get _customer {
    for (final Customer customer in _customers) {
      if (customer.id == _customerId) {
        return customer;
      }
    }

    return null;
  }

  double get _subtotal {
    return _cart.fold<double>(
      0.0,
      (double sum, _PosLine line) => sum + (line.quantity * line.unitPrice),
    );
  }

  double get _discount {
    return _cart.fold<double>(
      0.0,
      (double sum, _PosLine line) => sum + line.discount,
    );
  }

  double get _tax {
    return _cart.fold<double>(0.0, (double sum, _PosLine line) {
      final double taxable = (line.quantity * line.unitPrice) - line.discount;
      return sum + (taxable * line.product.taxRate / 100.0);
    });
  }

  double get _beforeRoundOff => _subtotal - _discount + _tax;

  double get _total => _beforeRoundOff.roundToDouble();

  // ignore: unused_element
  double get _automaticRoundOff => _total - _beforeRoundOff;

  void _applyRoundOff() {
    setState(() {
      final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;
      _roundOff = delta.abs() < 0.000001
          ? 0.0
          : double.parse(delta.toStringAsFixed(2));
      _syncTendered();
    });
  }

  double get _tenderedAmount {
    return double.tryParse(_tendered.text.trim()) ?? 0.0;
  }

  double get _change {
    if (_paymentMethod == 'cash' && _tenderedAmount > _total) {
      return _tenderedAmount - _total;
    }

    return 0.0;
  }

  @override
  void initState() {
    super.initState();

    _paymentMethod =
        widget.session
            .setting('pos.default_payment_method', 'cash')
            ?.toString() ??
        'cash';

    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<InventoryProduct> products = await _inventory.getProducts(
        tenantId: widget.session.business.id,
      );

      final List<Customer> customers = await _customersService.getCustomers(
        tenantId: widget.session.business.id,
      );

      final List<Customer> activeCustomers = customers
          .where((Customer customer) => customer.isActive)
          .toList();

      String? customerId;

      for (final Customer customer in activeCustomers) {
        if (customer.isWalkIn) {
          customerId = customer.id;
          break;
        }
      }

      customerId ??= activeCustomers.isEmpty ? null : activeCustomers.first.id;

      if (!mounted) {
        return;
      }

      setState(() {
        _products = products
            .where(
              (InventoryProduct product) =>
                  product.productStatus == 'active' &&
                  product.variantStatus == 'active',
            )
            .toList();
        _customers = activeCustomers;
        _customerId = customerId;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<InventoryProduct> get _filtered {
    final String query = _search.text.trim().toLowerCase();

    if (query.isEmpty) {
      return _products.take(60).toList();
    }

    return _products
        .where(
          (InventoryProduct product) =>
              product.productName.toLowerCase().contains(query) ||
              product.sku.toLowerCase().contains(query) ||
              (product.barcode ?? '').toLowerCase().contains(query) ||
              (product.partNumber ?? '').toLowerCase().contains(query),
        )
        .take(60)
        .toList();
  }

  void _scanOrSearchSubmitted(String value) {
    final String query = value.trim().toLowerCase();

    if (query.isEmpty) {
      return;
    }

    InventoryProduct? exact;

    for (final InventoryProduct product in _products) {
      if (product.sku.toLowerCase() == query ||
          (product.barcode ?? '').toLowerCase() == query) {
        exact = product;
        break;
      }
    }

    if (exact != null) {
      _add(exact);
      _search.clear();
    }
  }

  void _add(InventoryProduct product) {
    final int index = _cart.indexWhere(
      (_PosLine line) => line.product.variantId == product.variantId,
    );
    _PosLine? changed;
    setState(() {
      if (index >= 0) {
        final line = _cart[index];
        final next = line.quantity + line.quantityStep;
        if (product.itemType != 'stock' ||
            next * line.conversionToBase <= product.stockQuantity + 0.000001) {
          line.quantity = next;
          line.resolvedUnitPrice = null;
          changed = line;
        }
      } else {
        final line = _PosLine(product: product);
        if (product.itemType != 'stock' ||
            line.baseQuantity <= product.stockQuantity + 0.000001) {
          _cart.add(line);
          changed = line;
        }
      }
      _syncTendered();
    });
    if (changed != null) unawaited(_resolveLinePrice(changed!));
  }

  void _quantity(_PosLine line, double delta) {
    var keep = true;
    setState(() {
      final next = line.quantity + (delta.sign * line.quantityStep);
      if (next <= 0.000001) {
        _cart.remove(line);
        keep = false;
      } else if (line.product.itemType != 'stock' ||
          next * line.conversionToBase <=
              line.product.stockQuantity + 0.000001) {
        line.quantity = next;
        line.resolvedUnitPrice = null;
      }
      _syncTendered();
    });
    if (keep) unawaited(_resolveLinePrice(line));
  }

  Future<void> _chooseUnit(_PosLine line) async {
    final units = line.product.saleUnits
        .where((unit) => unit.allowSale && unit.active)
        .toList();
    if (units.length <= 1) return;
    final selected = await showDialog<ProductUnitOption>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Billing unit • ${line.product.productName}'),
        children: units
            .map(
              (unit) => SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, unit),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${unit.name} (${unit.code})'),
                  subtitle: Text(
                    '1 ${unit.code} = ${unit.conversionToBase} ${line.product.baseUnitCode}',
                  ),
                  trailing: Text(
                    _money(unit.salePriceFor(line.product.sellingPrice)),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null || !mounted) return;
    var quantity = line.quantity;
    if (!selected.acceptsQuantity(quantity)) {
      quantity = selected.quantityStep > 1 ? selected.quantityStep : 1;
    }
    if (line.product.itemType == 'stock' &&
        quantity * selected.conversionToBase >
            line.product.stockQuantity + 0.000001) {
      setState(
        () => _error =
            'Insufficient ${line.product.baseUnitCode} stock for ${selected.code}.',
      );
      return;
    }
    setState(() {
      line.unit = selected;
      line.quantity = quantity;
      line.resolvedUnitPrice = null;
      line.pricingSource = null;
      _syncTendered();
    });
    await _resolveLinePrice(line);
  }

  Future<void> _resolveLinePrice(_PosLine line) async {
    if (!_cart.contains(line)) return;
    final customerId = _customerId;
    final unitId = line.unit?.unitId;
    final quantity = line.quantity;
    try {
      final resolution = await _pricing.resolve(
        tenantId: widget.session.business.id,
        variantId: line.product.variantId,
        customerId: customerId,
        unitId: unitId,
        quantity: quantity,
        locationId: LocationScopeService.selectedLocationId.value,
      );
      if (!mounted ||
          !_cart.contains(line) ||
          _customerId != customerId ||
          line.unit?.unitId != unitId ||
          (line.quantity - quantity).abs() > 0.000001) {
        return;
      }
      setState(() {
        line.resolvedUnitPrice = resolution.unitPrice;
        line.pricingSource = resolution.sourceLabel;
        _syncTendered();
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Pricing refresh failed: $error');
    }
  }

  Future<void> _resolveAllPrices() async {
    await Future.wait(List<_PosLine>.from(_cart).map(_resolveLinePrice));
  }

  Future<void> _editDiscount(_PosLine line) async {
    final TextEditingController controller = TextEditingController(
      text: line.discount.toStringAsFixed(2),
    );

    final double? value = await showDialog<double>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Discount • ${line.product.productName}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Line discount amount',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  double.tryParse(controller.text.trim()) ?? 0.0,
                );
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (value == null || !mounted) {
      return;
    }

    final double maximumDiscount = line.quantity * line.unitPrice;

    setState(() {
      line.discount = value.clamp(0.0, maximumDiscount).toDouble();
      _syncTendered();
    });
  }

  void _syncTendered() {
    if (_paymentMethod != 'cash') {
      _tendered.text = _total.toStringAsFixed(2);
      return;
    }

    if (_tendered.text.trim().isEmpty) {
      _tendered.text = _total.toStringAsFixed(2);
    }
  }

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }

    return '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';
  }

  Future<void> _checkout() async {
    if (!_canUse) {
      setState(() {
        _error = 'You do not have POS permission.';
      });
      return;
    }

    final Customer? customer = _customer;

    if (customer == null) {
      setState(() {
        _error = 'Choose a customer.';
      });
      return;
    }

    if (_cart.isEmpty) {
      setState(() {
        _error = 'Cart is empty.';
      });
      return;
    }

    if (customer.isWalkIn && _paymentMethod == 'credit') {
      setState(() {
        _error = 'Walk-in Customer cannot use credit.';
      });
      return;
    }

    if (_paymentMethod == 'cash' && _tenderedAmount + 0.0001 < _total) {
      setState(() {
        _error = 'Cash received is less than the total.';
      });
      return;
    }

    final paymentAllocations = <Map<String, dynamic>>[
      <String, dynamic>{
        'method_code': _paymentMethod,
        'tendered_amount': _paymentMethod == 'credit'
            ? _total
            : (_paymentMethod == 'cash' ? _tenderedAmount : _total),
        'reference_number': '',
      },
    ];

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final Map<String, dynamic> result = await _sales.createSale(
        tenantId: widget.session.business.id,
        customerId: customer.id,
        saleDate: DateTime.now(),
        dueDate: _paymentMethod == 'credit'
            ? DateTime.now().add(const Duration(days: 30))
            : null,
        items: _cart
            .map(
              (_PosLine line) => <String, dynamic>{
                'variant_id': line.product.variantId,
                'quantity': line.quantity,
                'unit_id': line.unit?.unitId,
                'unit_price': line.unitPrice,
                'discount_amount': line.discount,
                'tax_rate': line.product.taxRate,
              },
            )
            .toList(),
        paymentAllocations: paymentAllocations,
        notes: 'POS sale',
      );

      if (!mounted) {
        return;
      }

      final String saleNumber =
          result['sale_number']?.toString() ?? 'Sale completed';
      final String changeText = _change > 0.0
          ? ' • Change ${_money(_change)}'
          : '';

      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('$saleNumber completed$changeText')),
      );

      setState(() {
        _cart.clear();
        _search.clear();
        _tendered.clear();
        _roundOff = 0.0;
      });

      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
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
    _search.dispose();
    _tendered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Point of Sale',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Fast checkout using the existing Sales, Inventory and Customer engines.',
                    ),
                  ],
                ),
              ),
              if (widget.session.subscription.hasPlan)
                Chip(
                  label: Text(
                    widget.session.subscription.planName ??
                        widget.session.subscription.planKey ??
                        'Plan',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool wide = constraints.maxWidth >= 950;
                final Widget products = _productsPane();
                final Widget cart = _cartPane();

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(flex: 3, child: products),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: cart),
                    ],
                  );
                }

                return Column(
                  children: <Widget>[
                    Expanded(child: products),
                    const SizedBox(height: 12),
                    SizedBox(height: 420, child: cart),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _productsPane() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              onSubmitted: _scanOrSearchSubmitted,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.qr_code_scanner),
                labelText: 'Scan barcode or search product / SKU / part number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisExtent: 145,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: _filtered.length,
                itemBuilder: (BuildContext context, int index) {
                  final InventoryProduct product = _filtered[index];
                  final bool outOfStock =
                      product.itemType == 'stock' &&
                      product.stockQuantity <= 0.0;

                  return InkWell(
                    onTap: outOfStock ? null : () => _add(product),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(14),
                        color: outOfStock ? Colors.grey.shade100 : Colors.white,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            product.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.sku,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  _money(product.sellingPrice),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                product.itemType == 'stock'
                                    ? 'Stock ${product.stockQuantity.toStringAsFixed(0)}'
                                    : product.itemType,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: outOfStock
                                      ? Colors.red
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartPane() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            SearchableSelect<String>(
              value: _customerId,
              labelText: 'Customer',
              isRequired: true,
              enabled: !_saving,
              hintText: 'Search customer name, ID, phone or GSTIN',
              prefixIcon: Icons.person_search_outlined,
              options: _customers
                  .map(
                    (customer) => SearchableSelectOption<String>(
                      value: customer.id,
                      label: customer.isWalkIn
                          ? '${customer.name} (Default)'
                          : customer.name,
                      subtitle:
                          [
                                customer.publicId,
                                customer.phone,
                                customer.taxNumber,
                              ]
                              .whereType<String>()
                              .where((v) => v.trim().isNotEmpty)
                              .join(' • '),
                      searchText:
                          '${customer.name} ${customer.publicId} ${customer.phone ?? ''} ${customer.email ?? ''} ${customer.taxNumber ?? ''}',
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (String? value) {
                      setState(() {
                        _customerId = value;
                        for (final line in _cart) {
                          line.resolvedUnitPrice = null;
                          line.pricingSource = null;
                        }
                      });
                      unawaited(_resolveAllPrices());
                    },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _cart.isEmpty
                  ? const Center(
                      child: Text('Scan or click a product to start a sale.'),
                    )
                  : ListView.separated(
                      itemCount: _cart.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (BuildContext context, int index) {
                        final _PosLine line = _cart[index];

                        return Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    line.product.productName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${_money(line.unitPrice)} / ${line.unitCode} • tax ${line.product.taxRate.toStringAsFixed(0)}%${line.pricingSource == null ? '' : ' • ${line.pricingSource}'}${line.discount > 0.0 ? ' • disc ${_money(line.discount)}' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (line.product.saleUnits.length > 1)
                              TextButton(
                                onPressed: () => _chooseUnit(line),
                                child: Text(line.unitCode),
                              ),
                            IconButton(
                              onPressed: () => _quantity(line, -1.0),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              line.quantity.toStringAsFixed(
                                line.quantity % 1.0 == 0.0 ? 0 : 2,
                              ),
                            ),
                            IconButton(
                              onPressed: () => _quantity(line, 1.0),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            IconButton(
                              tooltip: 'Discount',
                              onPressed: () => _editDiscount(line),
                              icon: const Icon(Icons.discount_outlined),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            const Divider(),
            _totalRow('Subtotal', _subtotal),
            _totalRow('Discount', -_discount),
            _totalRow('Tax', _tax),
            if (_roundOff.abs() > 0.000001) _totalRow('Round Off', _roundOff),
            _totalRow('Total', _total, bold: true),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _applyRoundOff,
                icon: const Icon(Icons.exposure_zero),
                label: const Text('Round Total'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank')),
                      DropdownMenuItem(value: 'credit', child: Text('Credit')),
                    ],
                    onChanged: _saving
                        ? null
                        : (String? value) {
                            if (value == null) {
                              return;
                            }

                            setState(() {
                              _paymentMethod = value;
                              _syncTendered();
                            });
                          },
                  ),
                ),
                if (_paymentMethod == 'cash') ...<Widget>[
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _tendered,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cash received',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_paymentMethod == 'cash' && _change > 0.0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Change: ${_money(_change)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving || !_canUse ? null : _checkout,
                icon: const Icon(Icons.done),
                label: Text(
                  _saving
                      ? 'Completing...'
                      : 'Complete Sale • ${_money(_total)}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            _money(value),
            style: TextStyle(
              fontSize: bold ? 19 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosLine {
  final InventoryProduct product;
  ProductUnitOption? unit;
  double quantity;
  double discount;
  double? resolvedUnitPrice;
  String? pricingSource;

  _PosLine({required this.product})
    : unit = product.defaultSaleUnit,
      discount = 0.0,
      quantity =
          (product.defaultSaleUnit?.quantityStep ?? product.quantityStep) > 1
          ? (product.defaultSaleUnit?.quantityStep ?? product.quantityStep)
          : 1.0,
      resolvedUnitPrice = null;

  double get conversionToBase => unit?.conversionToBase ?? 1.0;
  double get baseQuantity => quantity * conversionToBase;
  double get quantityStep => (unit?.quantityStep ?? product.quantityStep) > 0
      ? (unit?.quantityStep ?? product.quantityStep)
      : 1.0;
  double get unitPrice =>
      resolvedUnitPrice ??
      unit?.salePriceFor(product.sellingPrice) ??
      product.sellingPrice;
  String get unitCode => unit?.code ?? product.baseUnitCode;
}
