import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/restaurant_service.dart';
import '../services/pos_completion_service.dart';
import '../services/pos_hardware_service.dart';

class RestaurantScreen extends StatefulWidget {
  final ClientSession session;

  const RestaurantScreen({super.key, required this.session});

  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends State<RestaurantScreen> {
  final RestaurantService _restaurant = RestaurantService();
  final InventoryService _inventory = InventoryService();
  final CustomerService _customers = CustomerService();
  final PosCompletionService _completion = PosCompletionService();
  final PosHardwareService _hardware = PosHardwareService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _orders = [];
  List<InventoryProduct> _products = [];
  List<Customer> _customerRows = [];

  String? get _locationId => widget.session.device?.locationId;
  String? get _deviceId => widget.session.device?.deviceId;

  Customer? get _walkIn {
    for (final customer in _customerRows) {
      if (customer.isWalkIn) return customer;
    }
    return _customerRows.isEmpty ? null : _customerRows.first;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final locationId = _locationId;
    final deviceId = _deviceId;
    if (locationId == null || deviceId == null) {
      setState(() {
        _loading = false;
        _error =
            'This installation is not linked to a registered POS location.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _restaurant.tables(widget.session.business.id, locationId, deviceId),
        _restaurant.orders(widget.session.business.id, locationId, deviceId),
        _inventory.getProducts(
          tenantId: widget.session.business.id,
          locationId: widget.session.device?.locationId,
        ),
        _customers.getCustomers(tenantId: widget.session.business.id),
      ]);

      if (!mounted) return;

      setState(() {
        _tables = results[0] as List<Map<String, dynamic>>;
        _orders = results[1] as List<Map<String, dynamic>>;
        _products = (results[2] as List<InventoryProduct>)
            .where(
              (product) =>
                  product.variantStatus == 'active' &&
                  product.productStatus == 'active',
            )
            .toList();
        _customerRows = (results[3] as List<Customer>)
            .where((customer) => customer.isActive)
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _money(dynamic value) {
    final amount =
        (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0.0;
    if (widget.session.currencyCode == 'INR') {
      return '₹${amount.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  Future<void> _addTable() async {
    if (!widget.session.hasPermission('restaurant.manage')) {
      _message('restaurant.manage permission required.');
      return;
    }
    final locationId = _locationId;
    if (locationId == null) return;

    final code = TextEditingController();
    final name = TextEditingController();
    final capacity = TextEditingController(text: '4');
    final area = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Restaurant Table'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                decoration: const InputDecoration(labelText: 'Table code (T1)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Capacity'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: area,
                decoration: const InputDecoration(labelText: 'Area / floor'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _restaurant.saveTable(
                  tenantId: widget.session.business.id,
                  locationId: locationId,
                  deviceId: _deviceId!,
                  code: code.text,
                  name: name.text.trim().isEmpty ? code.text : name.text,
                  capacity: int.tryParse(capacity.text) ?? 4,
                  area: area.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await _load();
              } catch (error) {
                _message(error.toString());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    code.dispose();
    name.dispose();
    capacity.dispose();
    area.dispose();
  }

  Future<void> _newOrder() async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }
    final locationId = _locationId;
    final deviceId = _deviceId;
    if (locationId == null || deviceId == null) {
      _message('This system must be activated before restaurant ordering.');
      return;
    }
    if (_products.isEmpty) {
      _message('Add products/menu items first.');
      return;
    }

    String orderType = 'dine_in';
    final activeTables = _tables
        .where((table) => table['active'] != false)
        .toList();
    String? tableId = activeTables.isEmpty
        ? null
        : activeTables.first['id']?.toString();
    String? customerId = _walkIn?.id;
    final prep = TextEditingController(text: '15');
    final chefNote = TextEditingController();
    final deliveryAddress = TextEditingController();
    final search = TextEditingController();
    final cart = <_RestaurantLine>[];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          List<InventoryProduct> filteredProducts() {
            final query = search.text.trim().toLowerCase();
            return _products
                .where(
                  (product) =>
                      query.isEmpty ||
                      product.productName.toLowerCase().contains(query) ||
                      product.sku.toLowerCase().contains(query) ||
                      (product.barcode ?? '').toLowerCase().contains(query),
                )
                .take(24)
                .toList();
          }

          double orderTotal() {
            return cart.fold<double>(0.0, (sum, line) {
              final taxable = line.quantity * line.unitPrice;
              return sum + taxable + (taxable * line.product.taxRate / 100.0);
            });
          }

          return AlertDialog(
            title: const Text('New Restaurant Order'),
            content: SizedBox(
              width: 920,
              height: 650,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: orderType,
                          decoration: const InputDecoration(
                            labelText: 'Order type',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'dine_in',
                              child: Text('Dine In'),
                            ),
                            DropdownMenuItem(
                              value: 'takeaway',
                              child: Text('Take Away'),
                            ),
                            DropdownMenuItem(
                              value: 'delivery',
                              child: Text('Delivery'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setLocalState(() => orderType = value);
                            }
                          },
                        ),
                      ),
                      if (orderType == 'dine_in') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: tableId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Table',
                            ),
                            items: activeTables
                                .map(
                                  (table) => DropdownMenuItem<String?>(
                                    value: table['id']?.toString(),
                                    child: Text(
                                      '${table['table_code']} • ${table['name']}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setLocalState(() => tableId = value),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: customerId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Customer',
                          ),
                          items: _customerRows
                              .map(
                                (customer) => DropdownMenuItem<String?>(
                                  value: customer.id,
                                  child: Text(
                                    customer.isWalkIn
                                        ? '${customer.name} (Default)'
                                        : customer.name,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setLocalState(() => customerId = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 190,
                        child: TextField(
                          controller: prep,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Preparation minutes',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: chefNote,
                          decoration: const InputDecoration(
                            labelText: 'Chef / kitchen note',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (orderType == 'delivery')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: deliveryAddress,
                        decoration: const InputDecoration(
                          labelText: 'Delivery address',
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: search,
                    onChanged: (_) => setLocalState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search menu/product / SKU / barcode',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: filteredProducts()
                          .map(
                            (product) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  child: Text(
                                    '${product.productName}\n${_money(product.defaultSaleUnit?.salePriceFor(product.sellingPrice) ?? product.sellingPrice)}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                onPressed: () {
                                  setLocalState(() {
                                    final index = cart.indexWhere(
                                      (line) =>
                                          line.product.variantId ==
                                          product.variantId,
                                    );
                                    if (index >= 0) {
                                      cart[index].quantity +=
                                          cart[index].quantityStep;
                                    } else {
                                      cart.add(_RestaurantLine(product));
                                    }
                                  });
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: cart.isEmpty
                        ? const Center(child: Text('Add menu items'))
                        : ListView.separated(
                            itemCount: cart.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, index) {
                              final line = cart[index];
                              return Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          line.product.productName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '${line.product.sku} • tax ${line.product.taxRate.toStringAsFixed(0)}%',
                                        ),
                                        if (line.product.saleUnits.length > 1)
                                          SizedBox(
                                            width: 180,
                                            child:
                                                DropdownButton<
                                                  ProductUnitOption
                                                >(
                                                  value: line.unit,
                                                  isExpanded: true,
                                                  items: line.product.saleUnits
                                                      .map(
                                                        (
                                                          unit,
                                                        ) => DropdownMenuItem(
                                                          value: unit,
                                                          child: Text(
                                                            '${unit.code} • ${_money(unit.salePriceFor(line.product.sellingPrice))}',
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                                  onChanged: (unit) {
                                                    if (unit == null) return;
                                                    setLocalState(() {
                                                      line.unit = unit;
                                                      line.quantity =
                                                          unit.quantityStep > 0
                                                          ? unit.quantityStep
                                                          : 1;
                                                    });
                                                  },
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setLocalState(() {
                                        line.quantity -= line.quantityStep;
                                        if (line.quantity <= 0) {
                                          cart.removeAt(index);
                                        }
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  Text(line.quantity.toStringAsFixed(0)),
                                  IconButton(
                                    onPressed: () => setLocalState(
                                      () => line.quantity += line.quantityStep,
                                    ),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      _money(line.quantity * line.unitPrice),
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Order total ${_money(orderTotal())}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: cart.isEmpty
                    ? null
                    : () async {
                        try {
                          final result = await _restaurant.createOrder(
                            tenantId: widget.session.business.id,
                            locationId: locationId,
                            deviceId: deviceId,
                            orderType: orderType,
                            tableId: orderType == 'dine_in' ? tableId : null,
                            customerId: customerId,
                            preparationMinutes: int.tryParse(prep.text) ?? 15,
                            chefNote: chefNote.text,
                            deliveryAddress: deliveryAddress.text,
                            items: cart
                                .map(
                                  (line) => <String, dynamic>{
                                    'variant_id': line.product.variantId,
                                    'quantity': line.quantity,
                                    'unit_id': line.unit?.unitId,
                                    'unit_price': line.unitPrice,
                                    'discount_amount': 0.0,
                                    'tax_rate': line.product.taxRate,
                                    'item_note': '',
                                  },
                                )
                                .toList(),
                          );
                          await _restaurant.sendKot(
                            widget.session.business.id,
                            result['order_id'].toString(),
                            deviceId,
                            chefNote.text,
                          );
                          String? kotPrintWarning;
                          try {
                            final profiles = await _completion.printerProfiles(
                              tenantId: widget.session.business.id,
                              deviceId: deviceId,
                            );
                            final kotProfiles = profiles
                                .where(
                                  (row) =>
                                      row['purpose']?.toString() == 'kot' &&
                                      row['active'] != false &&
                                      row['auto_print'] == true,
                                )
                                .toList();
                            String? tableName;
                            if (orderType == 'dine_in' && tableId != null) {
                              for (final table in activeTables) {
                                if (table['id']?.toString() == tableId) {
                                  tableName =
                                      '${table['table_code'] ?? ''} ${table['name'] ?? ''}'
                                          .trim();
                                  break;
                                }
                              }
                            }
                            await _hardware.printKot(
                              profiles: kotProfiles,
                              orderNumber:
                                  result['order_number']?.toString() ??
                                  result['order_id'].toString(),
                              orderType: orderType,
                              tableName: tableName,
                              prepMinutes: int.tryParse(prep.text) ?? 15,
                              chefNote: chefNote.text,
                              items: cart
                                  .map(
                                    (line) => <String, dynamic>{
                                      'name': line.product.productName,
                                      'quantity': line.quantity,
                                    },
                                  )
                                  .toList(),
                            );
                          } catch (error) {
                            kotPrintWarning = error.toString();
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (kotPrintWarning == null) {
                            _message(
                              '${result['order_number']} sent to kitchen.',
                            );
                          } else {
                            _message(
                              '${result['order_number']} saved and KOT queued. Printer: $kotPrintWarning',
                            );
                          }
                          await _load();
                        } catch (error) {
                          _message(error.toString());
                        }
                      },
                icon: const Icon(Icons.soup_kitchen_outlined),
                label: const Text('Place Order + KOT'),
              ),
            ],
          );
        },
      ),
    );

    prep.dispose();
    chefNote.dispose();
    deliveryAddress.dispose();
    search.dispose();
  }

  Future<void> _setStatus(Map<String, dynamic> order, String status) async {
    try {
      await _restaurant.setStatus(
        widget.session.business.id,
        order['id'].toString(),
        _deviceId!,
        status,
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _bill(Map<String, dynamic> order) async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    try {
      final detail = await _restaurant.detail(
        widget.session.business.id,
        order['id'].toString(),
        deviceId,
      );
      if (!mounted) return;
      final orderMap = Map<String, dynamic>.from(detail['order'] as Map);
      final itemRows = detail['items'] as List? ?? const [];

      double storedTotal = 0;
      for (final raw in itemRows) {
        final item = Map<String, dynamic>.from(raw as Map);
        final quantity =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            0;
        final unitPrice =
            (item['unit_price'] as num?)?.toDouble() ??
            double.tryParse('${item['unit_price']}') ??
            0;
        final discount =
            (item['discount_amount'] as num?)?.toDouble() ??
            double.tryParse('${item['discount_amount']}') ??
            0;
        final taxRate =
            (item['tax_rate'] as num?)?.toDouble() ??
            double.tryParse('${item['tax_rate']}') ??
            0;
        final taxable = (quantity * unitPrice - discount).clamp(
          0,
          double.infinity,
        );
        storedTotal += taxable * (1 + taxRate / 100);
      }
      storedTotal = double.parse(storedTotal.toStringAsFixed(2));

      final choice = await _restaurantBillingDialog(
        orderNumber: order['order_number']?.toString() ?? 'Restaurant Order',
        total: storedTotal,
      );
      if (choice == null || !mounted) return;

      final customerId = orderMap['customer_id']?.toString() ?? _walkIn?.id;
      if (customerId == null) {
        throw Exception('No customer is available for billing.');
      }
      Customer? customer;
      for (final value in _customerRows) {
        if (value.id == customerId) {
          customer = value;
          break;
        }
      }
      if (choice.paymentMethod == 'credit' && customer?.isWalkIn == true) {
        throw Exception('Walk-in Customer cannot use credit.');
      }

      final finalTotal = double.parse(
        (storedTotal + choice.roundOff).toStringAsFixed(2),
      );
      if (finalTotal < 0) throw Exception('Rounded total cannot be negative.');
      final sale = await _restaurant.billOrder(
        tenantId: widget.session.business.id,
        orderId: order['id'].toString(),
        deviceId: deviceId,
        customerId: customerId,
        dueDate: choice.paymentMethod == 'credit'
            ? DateTime.now().add(const Duration(days: 30))
            : null,
        initialPayment: choice.paymentMethod == 'credit' ? 0 : finalTotal,
        paymentMethod: choice.paymentMethod,
        paymentReference: '',
        roundOff: choice.roundOff,
      );
      final saleNumber =
          sale['sale_number']?.toString() ?? sale['number']?.toString();
      if (saleNumber == null || saleNumber.isEmpty) {
        throw Exception('Sale created but number was not returned.');
      }
      _message('$saleNumber billed successfully.');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<_RestaurantBillingChoice?> _restaurantBillingDialog({
    required String orderNumber,
    required double total,
  }) async {
    final roundController = TextEditingController(text: '0.00');
    String paymentMethod = 'cash';
    final result = await showDialog<_RestaurantBillingChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final roundOff = double.tryParse(roundController.text.trim()) ?? 0;
          final finalTotal = total + roundOff;
          return AlertDialog(
            title: Text('Finalize $orderNumber'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Order total: ${_money(total)}'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: roundController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Round Off',
                      helperText: 'Allowed range: -1.00 to +1.00',
                      suffixIcon: TextButton(
                        onPressed: () {
                          final rounded = total.roundToDouble();
                          roundController.text = (rounded - total)
                              .toStringAsFixed(2);
                          setDialogState(() {});
                        },
                        child: const Text('Round'),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Final total: ${_money(finalTotal)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('CASH')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI')),
                      DropdownMenuItem(value: 'card', child: Text('CARD')),
                      DropdownMenuItem(value: 'credit', child: Text('CREDIT')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => paymentMethod = value);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final roundOff =
                      double.tryParse(roundController.text.trim()) ?? 0;
                  if (roundOff.abs() > 1.000001) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Round off must be between -1.00 and +1.00.',
                        ),
                      ),
                    );
                    return;
                  }
                  if (total + roundOff < 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Rounded total cannot be negative.'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    _RestaurantBillingChoice(paymentMethod, roundOff),
                  );
                },
                child: const Text('Create Sales Invoice'),
              ),
            ],
          );
        },
      ),
    );
    roundController.dispose();
    return result;
  }

  Map<String, dynamic>? _tableOrder(String tableId) {
    for (final order in _orders) {
      if (order['table_id']?.toString() == tableId &&
          !const {
            'billed',
            'cancelled',
          }.contains(order['status']?.toString())) {
        return order;
      }
    }
    return null;
  }

  Widget _orderCard(Map<String, dynamic> order, {bool compact = false}) {
    final status = (order['status'] ?? 'open').toString();
    final title =
        '${order['order_number']} • ${order['table_name'] ?? order['order_type']}';
    return Card(
      margin: compact
          ? const EdgeInsets.only(bottom: 8)
          : const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 14),
        child: Row(
          children: [
            CircleAvatar(
              child: Icon(
                order['order_type'] == 'dine_in'
                    ? Icons.table_restaurant
                    : order['order_type'] == 'delivery'
                    ? Icons.delivery_dining
                    : Icons.takeout_dining,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${order['customer_name'] ?? 'Walk-in'} • Prep ${order['preparation_minutes'] ?? 0} min',
                  ),
                  if ((order['chef_note'] ?? '').toString().trim().isNotEmpty)
                    Text(
                      'Kitchen: ${order['chef_note']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Chip(label: Text(status.replaceAll('_', ' ').toUpperCase())),
            const SizedBox(width: 8),
            Text(
              _money(order['total']),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            PopupMenuButton<String>(
              tooltip: 'Order actions',
              onSelected: (value) {
                if (value == 'bill') {
                  _bill(order);
                } else {
                  _setStatus(order, value);
                }
              },
              itemBuilder: (_) => [
                if (status == 'open' || status == 'sent_to_kitchen')
                  const PopupMenuItem(
                    value: 'preparing',
                    child: Text('Start Preparing'),
                  ),
                if (status == 'preparing' || status == 'sent_to_kitchen')
                  const PopupMenuItem(
                    value: 'ready',
                    child: Text('Mark Ready'),
                  ),
                if (status == 'ready')
                  const PopupMenuItem(
                    value: 'served',
                    child: Text('Mark Served'),
                  ),
                if (status != 'billed' && status != 'cancelled')
                  const PopupMenuItem(
                    value: 'bill',
                    child: Text('Finalize / Bill'),
                  ),
                if (status != 'billed' && status != 'cancelled')
                  const PopupMenuItem(
                    value: 'cancelled',
                    child: Text('Cancel Order'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _floorView() {
    final active = _tables.where((table) => table['active'] != false).toList();
    if (active.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.table_restaurant_outlined, size: 54),
            const SizedBox(height: 10),
            const Text('No restaurant tables configured.'),
            const SizedBox(height: 10),
            if (widget.session.hasPermission('restaurant.manage'))
              FilledButton.icon(
                onPressed: _addTable,
                icon: const Icon(Icons.add),
                label: const Text('Add first table'),
              ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 180,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: active.length,
      itemBuilder: (context, index) {
        final table = active[index];
        final id = table['id']?.toString() ?? '';
        final order = _tableOrder(id);
        final occupied = order != null;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: occupied ? () => _bill(order) : _newOrder,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        child: Icon(
                          occupied
                              ? Icons.restaurant
                              : Icons.table_restaurant_outlined,
                        ),
                      ),
                      const Spacer(),
                      Chip(label: Text(occupied ? 'OCCUPIED' : 'AVAILABLE')),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${table['table_code']} • ${table['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${table['area'] ?? 'Main floor'} • ${table['capacity'] ?? 0} seats',
                  ),
                  if (occupied) ...[
                    const SizedBox(height: 5),
                    Text(
                      '${order['order_number']} • ${_money(order['total'])}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      (order['status'] ?? '')
                          .toString()
                          .replaceAll('_', ' ')
                          .toUpperCase(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _ordersView() {
    if (_orders.isEmpty) {
      return const Center(child: Text('No live restaurant orders.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        itemBuilder: (context, index) => _orderCard(_orders[index]),
      ),
    );
  }

  Widget _kitchenView() {
    final groups = <String, List<Map<String, dynamic>>>{
      'QUEUE': _orders
          .where(
            (o) => const {
              'open',
              'sent_to_kitchen',
            }.contains(o['status']?.toString()),
          )
          .toList(),
      'PREPARING': _orders
          .where((o) => o['status']?.toString() == 'preparing')
          .toList(),
      'READY': _orders
          .where((o) => o['status']?.toString() == 'ready')
          .toList(),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = groups.entries
            .map(
              (entry) => Card(
                margin: const EdgeInsets.all(6),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Chip(label: Text('${entry.value.length}')),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: entry.value.isEmpty
                            ? Center(
                                child: Text(
                                  'No ${entry.key.toLowerCase()} orders',
                                ),
                              )
                            : ListView(
                                children: entry.value
                                    .map((o) => _orderCard(o, compact: true))
                                    .toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList();
        if (constraints.maxWidth < 900) {
          return ListView(
            padding: const EdgeInsets.all(8),
            children: groups.entries
                .map(
                  (entry) => SizedBox(
                    height: 330,
                    child: columns[groups.keys.toList().indexOf(entry.key)],
                  ),
                )
                .toList(),
          );
        }
        return Row(children: columns.map((c) => Expanded(child: c)).toList());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final occupied = _tables
        .where(
          (t) =>
              t['active'] != false &&
              _tableOrder(t['id']?.toString() ?? '') != null,
        )
        .length;
    final ready = _orders
        .where((o) => o['status']?.toString() == 'ready')
        .length;

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Restaurant Operations',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${widget.session.device?.locationName ?? ''} • ${_orders.length} live orders • $occupied occupied tables • $ready ready',
                      ),
                    ],
                  ),
                ),
                if (widget.session.hasPermission('restaurant.manage'))
                  OutlinedButton.icon(
                    onPressed: _addTable,
                    icon: const Icon(Icons.table_restaurant_outlined),
                    label: const Text('Tables'),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _newOrder,
                  icon: const Icon(Icons.add),
                  label: const Text('New Order'),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ),
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.table_restaurant_outlined), text: 'Floor'),
              Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Orders'),
              Tab(icon: Icon(Icons.soup_kitchen_outlined), text: 'Kitchen'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_floorView(), _ordersView(), _kitchenView()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantBillingChoice {
  final String paymentMethod;
  final double roundOff;

  const _RestaurantBillingChoice(this.paymentMethod, this.roundOff);
}

class _RestaurantLine {
  final InventoryProduct product;
  ProductUnitOption? unit;
  double quantity;

  _RestaurantLine(this.product)
    : unit = product.defaultSaleUnit,
      quantity = product.defaultSaleUnit?.quantityStep ?? product.quantityStep;

  double get unitPrice =>
      unit?.salePriceFor(product.sellingPrice) ?? product.sellingPrice;
  double get quantityStep => (unit?.quantityStep ?? product.quantityStep) > 0
      ? (unit?.quantityStep ?? product.quantityStep)
      : 1;
}
