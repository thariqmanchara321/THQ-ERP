import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../services/customer_service.dart';
import '../services/inventory_service.dart';
import '../services/restaurant_service.dart';
import '../services/sales_service.dart';
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
  final SalesService _sales = SalesService();
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
              final taxable = line.quantity * line.product.sellingPrice;
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
                                    '${product.productName}\n${_money(product.sellingPrice)}',
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
                                      cart[index].quantity += 1.0;
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
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setLocalState(() {
                                        line.quantity -= 1.0;
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
                                      () => line.quantity += 1.0,
                                    ),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      _money(
                                        line.quantity *
                                            line.product.sellingPrice,
                                      ),
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
                                    'unit_price': line.product.sellingPrice,
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
    final payment = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Finalize ${order['order_number']}'),
        content: const Text(
          'Choose payment method. Finalization creates the normal Sales invoice.',
        ),
        actions: ['cash', 'upi', 'card', 'credit']
            .map(
              (method) => FilledButton.tonal(
                onPressed: () => Navigator.pop(dialogContext, method),
                child: Text(method.toUpperCase()),
              ),
            )
            .toList(),
      ),
    );
    if (payment == null) return;

    try {
      final detail = await _restaurant.detail(
        widget.session.business.id,
        order['id'].toString(),
        _deviceId!,
      );
      final orderMap = Map<String, dynamic>.from(detail['order'] as Map);
      final itemRows = detail['items'] as List? ?? const [];
      final items = itemRows.map((row) {
        final item = Map<String, dynamic>.from(row as Map);
        return <String, dynamic>{
          'variant_id': item['variant_id'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
          'discount_amount': item['discount_amount'],
          'tax_rate': item['tax_rate'],
        };
      }).toList();

      final customerId = orderMap['customer_id']?.toString() ?? _walkIn?.id;
      if (customerId == null) {
        throw Exception('No customer is available for billing.');
      }
      final customer = _customerRows
          .where((value) => value.id == customerId)
          .cast<Customer?>()
          .firstWhere((value) => value != null, orElse: () => null);
      if (payment == 'credit' && customer?.isWalkIn == true) {
        throw Exception('Walk-in Customer cannot use credit.');
      }

      final total =
          (order['total'] as num?)?.toDouble() ??
          double.tryParse('${order['total']}') ??
          0.0;
      final sale = await _sales.createSale(
        tenantId: widget.session.business.id,
        customerId: customerId,
        saleDate: DateTime.now(),
        dueDate: payment == 'credit'
            ? DateTime.now().add(const Duration(days: 30))
            : null,
        items: items,
        additionalCharges: 0,
        initialPayment: payment == 'credit' ? 0 : total,
        paymentMethod: payment,
        paymentReference: '',
        notes: 'Restaurant ${order['order_number']}',
      );
      final saleNumber =
          sale['sale_number']?.toString() ?? sale['number']?.toString();
      if (saleNumber == null || saleNumber.isEmpty) {
        throw Exception('Sale created but number was not returned.');
      }
      await _restaurant.markBilledByReference(
        widget.session.business.id,
        order['id'].toString(),
        _deviceId!,
        saleNumber,
      );
      _message('$saleNumber billed successfully.');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Restaurant',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${widget.session.device?.locationName ?? ''} • Dine in, takeaway, delivery and KOT',
                    ),
                  ],
                ),
              ),
              if (widget.session.hasPermission('restaurant.manage'))
                OutlinedButton.icon(
                  onPressed: _addTable,
                  icon: const Icon(Icons.table_restaurant_outlined),
                  label: const Text('Add Table'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _newOrder,
                icon: const Icon(Icons.add),
                label: const Text('New Order'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tables
                .where((table) => table['active'] != false)
                .map(
                  (table) => Chip(
                    avatar: const Icon(Icons.table_restaurant, size: 18),
                    label: Text('${table['table_code']} • ${table['name']}'),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Live Orders / Kitchen',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (_orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: Text('No live restaurant orders.')),
            ),
          ..._orders.map(
            (order) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${order['order_number']} • ${order['table_name'] ?? order['order_type']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${order['customer_name'] ?? 'Walk-in'} • Prep ${order['preparation_minutes']} min • ${order['tracking_code'] ?? ''}',
                          ),
                          if ((order['chef_note'] ?? '').toString().isNotEmpty)
                            Text(
                              'Chef: ${order['chef_note']}',
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(
                        (order['status'] ?? 'open')
                            .toString()
                            .replaceAll('_', ' ')
                            .toUpperCase(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _money(order['total']),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'bill') {
                          _bill(order);
                        } else {
                          _setStatus(order, value);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'preparing',
                          child: Text('Start Preparing'),
                        ),
                        PopupMenuItem(
                          value: 'ready',
                          child: Text('Mark Ready'),
                        ),
                        PopupMenuItem(
                          value: 'served',
                          child: Text('Mark Served'),
                        ),
                        PopupMenuItem(
                          value: 'bill',
                          child: Text('Finalize / Bill'),
                        ),
                        PopupMenuItem(
                          value: 'cancelled',
                          child: Text('Cancel Order'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantLine {
  final InventoryProduct product;
  double quantity = 1.0;

  _RestaurantLine(this.product);
}
