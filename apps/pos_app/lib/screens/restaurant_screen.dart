import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

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
  List<Map<String, dynamic>> _waiters = [];
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
        _restaurant.waiters(widget.session.business.id, locationId, deviceId),
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
        _waiters = results[2] as List<Map<String, dynamic>>;
        _products = (results[3] as List<InventoryProduct>)
            .where(
              (product) =>
                  product.variantStatus == 'active' &&
                  product.productStatus == 'active',
            )
            .toList();
        _customerRows = (results[4] as List<Customer>)
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
    ThqNotify.showSnackBar(context, SnackBar(content: Text(text)));
  }

  String _money(dynamic value) {
    final amount =
        (value as num?)?.toDouble() ?? double.tryParse('$value') ?? 0.0;
    if (widget.session.currencyCode == 'INR') {
      return '₹${amount.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${amount.toStringAsFixed(2)}';
  }

  String _restaurantProductLabel(String? variantId) {
    if (variantId == null || variantId.isEmpty) return 'Menu item';
    for (final product in _products) {
      if (product.variantId == variantId) {
        return product.productName;
      }
    }
    return 'Menu item';
  }

  Map<String, dynamic> _restaurantItemPayload(_RestaurantLine line) =>
      <String, dynamic>{
        'variant_id': line.product.variantId,
        'quantity': line.quantity,
        'unit_id': line.unit?.unitId,
        'unit_price': line.unitPrice,
        'discount_amount': 0.0,
        'tax_rate': line.product.taxRate,
        'item_note': '',
      };

  Widget _restaurantDashboardStrip() {
    final locationId = _locationId;
    final deviceId = _deviceId;
    final scheme = Theme.of(context).colorScheme;

    if (locationId == null || deviceId == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _restaurant.dashboardSummary(
        tenantId: widget.session.business.id,
        locationId: locationId,
        deviceId: deviceId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Container(
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Restaurant dashboard unavailable: ${snapshot.error}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.8,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Retry dashboard',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data ?? const <String, dynamic>{};
        final tables = Map<String, dynamic>.from(
          data['tables'] as Map? ?? const {},
        );
        final orders = Map<String, dynamic>.from(
          data['orders'] as Map? ?? const {},
        );
        final kitchen = Map<String, dynamic>.from(
          data['kitchen'] as Map? ?? const {},
        );
        final waitlist = Map<String, dynamic>.from(
          data['waitlist'] as Map? ?? const {},
        );
        final reservations = Map<String, dynamic>.from(
          data['reservations'] as Map? ?? const {},
        );
        final sales = Map<String, dynamic>.from(
          data['sales'] as Map? ?? const {},
        );

        String count(dynamic value) =>
            ((value as num?)?.toInt() ?? int.tryParse('$value') ?? 0)
                .toString();

        Widget metric({
          required IconData icon,
          required String label,
          required String value,
          required String detail,
          bool alert = false,
        }) {
          return Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: alert
                  ? scheme.errorContainer.withValues(alpha: .55)
                  : scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: alert ? scheme.error : scheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: alert ? scheme.error : scheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.2,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 8.6,
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

        final overdue =
            (kitchen['overdue'] as num?)?.toInt() ??
            int.tryParse('${kitchen['overdue']}') ??
            0;

        final cards = <Widget>[
          metric(
            icon: Icons.table_restaurant_outlined,
            label: 'TABLES',
            value:
                '${count(tables['available'])} free / '
                '${count(tables['occupied'])} occupied',
            detail:
                '${count(tables['reserved'])} reserved â€¢ '
                '${count(tables['cleaning'])} cleaning',
          ),
          metric(
            icon: Icons.receipt_long_outlined,
            label: 'LIVE ORDERS',
            value:
                '${count(orders['live'])} orders â€¢ '
                '${count(orders['live_guests'])} guests',
            detail:
                '${count(orders['dine_in'])} dine-in â€¢ '
                '${count(orders['takeaway'])} takeaway â€¢ '
                '${count(orders['delivery'])} delivery',
          ),
          metric(
            icon: Icons.soup_kitchen_outlined,
            label: 'KITCHEN',
            value:
                '${count(kitchen['queued'])} queue â€¢ '
                '${count(kitchen['preparing'])} preparing',
            detail:
                '${count(kitchen['ready'])} ready â€¢ '
                '${count(kitchen['avg_prep_minutes_today'])} min avg',
            alert: overdue > 0,
          ),
          metric(
            icon: Icons.groups_2_outlined,
            label: 'WAITLIST',
            value:
                '${count(waitlist['waiting'])} waiting â€¢ '
                '${count(waitlist['notified'])} notified',
            detail:
                '${count(waitlist['waiting_guests'])} guests waiting â€¢ '
                '${count(reservations['next_24h'])} reservations / 24h',
          ),
          metric(
            icon: Icons.payments_outlined,
            label: 'TODAY',
            value: _money(sales['sales_today']),
            detail:
                '${count(sales['bills_today'])} bills â€¢ '
                'avg ${_money(sales['avg_ticket_today'])}',
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 980) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }

            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 5),
                    Expanded(child: cards[1]),
                    const SizedBox(width: 5),
                    Expanded(child: cards[2]),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(child: cards[3]),
                    const SizedBox(width: 5),
                    Expanded(child: cards[4]),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
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
    String waiterUserId = '';
    final guests = TextEditingController(text: '1');
    final orderNote = TextEditingController();
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
                        width: 120,
                        child: TextField(
                          controller: guests,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Guests',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: waiterUserId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Waiter / server',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Unassigned'),
                            ),
                            ..._waiters.map(
                              (waiter) => DropdownMenuItem<String>(
                                value: waiter['user_id']?.toString() ?? '',
                                child: Text(
                                  waiter['display_name']?.toString() ??
                                      waiter['user_id']?.toString() ??
                                      'Staff',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setLocalState(() => waiterUserId = value ?? ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: orderNote,
                          decoration: const InputDecoration(
                            labelText: 'Order / guest note',
                          ),
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
                            guestCount: (int.tryParse(guests.text.trim()) ?? 1)
                                .clamp(1, 999),
                            waiterUserId: waiterUserId.isEmpty
                                ? null
                                : waiterUserId,
                            orderNote: orderNote.text,
                            items: cart.map(_restaurantItemPayload).toList(),
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

    guests.dispose();
    orderNote.dispose();
    prep.dispose();
    chefNote.dispose();
    deliveryAddress.dispose();
    search.dispose();
  }

  Future<void> _editOrder(Map<String, dynamic> order) async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }

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
      final currentTableId = orderMap['table_id']?.toString();
      final availableTables = _tables.where((table) {
        if (table['active'] == false) return false;
        final id = table['id']?.toString() ?? '';
        final liveOrder = _tableOrder(id);
        return liveOrder == null || id == currentTableId;
      }).toList();

      String? tableId = currentTableId;
      String? customerId = orderMap['customer_id']?.toString();
      String waiterUserId = orderMap['waiter_user_id']?.toString() ?? '';
      final guests = TextEditingController(
        text: '${orderMap['guest_count'] ?? 1}',
      );
      final orderNote = TextEditingController(
        text: orderMap['order_note']?.toString() ?? '',
      );
      final chefNote = TextEditingController(
        text: orderMap['chef_note']?.toString() ?? '',
      );
      final deliveryAddress = TextEditingController(
        text: orderMap['delivery_address']?.toString() ?? '',
      );

      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: Text(
              'Edit ${orderMap['order_number'] ?? 'Restaurant Order'}',
            ),
            content: SizedBox(
              width: 720,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (orderMap['order_type']?.toString() == 'dine_in')
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: tableId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Table',
                            ),
                            items: availableTables
                                .map(
                                  (table) => DropdownMenuItem<String?>(
                                    value: table['id']?.toString(),
                                    child: Text(
                                      '${table['table_code']} â€¢ ${table['name']}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setLocalState(() => tableId = value),
                          ),
                        ),
                      if (orderMap['order_type']?.toString() == 'dine_in')
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
                                  child: Text(customer.name),
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
                        width: 120,
                        child: TextField(
                          controller: guests,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Guests',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: waiterUserId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Waiter / server',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Unassigned'),
                            ),
                            ..._waiters.map(
                              (waiter) => DropdownMenuItem<String>(
                                value: waiter['user_id']?.toString() ?? '',
                                child: Text(
                                  waiter['display_name']?.toString() ??
                                      waiter['user_id']?.toString() ??
                                      'Staff',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) =>
                              setLocalState(() => waiterUserId = value ?? ''),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: orderNote,
                    decoration: const InputDecoration(
                      labelText: 'Order / guest note',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: chefNote,
                    decoration: const InputDecoration(
                      labelText: 'Chef / kitchen note',
                    ),
                  ),
                  if (orderMap['order_type']?.toString() == 'delivery') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: deliveryAddress,
                      decoration: const InputDecoration(
                        labelText: 'Delivery address',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final guestCount = int.tryParse(guests.text.trim()) ?? 1;
                  if (guestCount < 1 || guestCount > 999) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      const SnackBar(
                        content: Text('Guest count must be between 1 and 999.'),
                      ),
                    );
                    return;
                  }

                  try {
                    await _restaurant.updateOrder(
                      tenantId: widget.session.business.id,
                      orderId: order['id'].toString(),
                      deviceId: deviceId,
                      tableId: tableId,
                      customerId: customerId,
                      guestCount: guestCount,
                      waiterUserId: waiterUserId.isEmpty ? null : waiterUserId,
                      orderNote: orderNote.text,
                      chefNote: chefNote.text,
                      deliveryAddress: deliveryAddress.text,
                    );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    ThqNotify.showSnackBar(
                      dialogContext,
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Changes'),
              ),
            ],
          ),
        ),
      );

      guests.dispose();
      orderNote.dispose();
      chefNote.dispose();
      deliveryAddress.dispose();

      if (saved == true) {
        _message('Restaurant order updated.');
        await _load();
      }
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _addItemsToOrder(Map<String, dynamic> order) async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }
    if (_products.isEmpty) {
      _message('Add products/menu items first.');
      return;
    }

    final search = TextEditingController();
    final cart = <_RestaurantLine>[];

    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final query = search.text.trim().toLowerCase();
          final filtered = _products
              .where(
                (product) =>
                    query.isEmpty ||
                    product.productName.toLowerCase().contains(query) ||
                    product.sku.toLowerCase().contains(query) ||
                    (product.barcode ?? '').toLowerCase().contains(query),
              )
              .take(30)
              .toList();

          return AlertDialog(
            title: Text(
              'Add Items â€¢ ${order['order_number'] ?? 'Restaurant Order'}',
            ),
            content: SizedBox(
              width: 760,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    autofocus: true,
                    onChanged: (_) => setLocalState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search menu / SKU / barcode',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: filtered
                          .map(
                            (product) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  child: Text(
                                    '${product.productName}\n'
                                    '${_money(product.defaultSaleUnit?.salePriceFor(product.sellingPrice) ?? product.sellingPrice)}',
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
                        ? const Center(child: Text('Choose items to add'))
                        : ListView.separated(
                            itemCount: cart.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, index) {
                              final line = cart[index];
                              return Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      line.product.productName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (line.product.saleUnits.length > 1)
                                    SizedBox(
                                      width: 150,
                                      child: DropdownButton<ProductUnitOption>(
                                        value: line.unit,
                                        isExpanded: true,
                                        items: line.product.saleUnits
                                            .map(
                                              (unit) => DropdownMenuItem(
                                                value: unit,
                                                child: Text(unit.code),
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: cart.isEmpty
                    ? null
                    : () async {
                        try {
                          await _restaurant.addItems(
                            tenantId: widget.session.business.id,
                            orderId: order['id'].toString(),
                            deviceId: deviceId,
                            items: cart.map(_restaurantItemPayload).toList(),
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (error) {
                          if (!dialogContext.mounted) return;
                          ThqNotify.showSnackBar(
                            dialogContext,
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      },
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: const Text('Add to Order'),
              ),
            ],
          );
        },
      ),
    );

    search.dispose();

    if (added == true) {
      String? kotWarning;
      String? kotNumber;
      var kotCreated = false;

      try {
        final kot = await _restaurant.sendKot(
          widget.session.business.id,
          order['id'].toString(),
          deviceId,
          '',
        );

        kotCreated =
            kot['kot_created'] == true ||
            kot['kot_id']?.toString().isNotEmpty == true;
        kotNumber = kot['kot_number']?.toString();

        if (kotCreated) {
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

          final deltaItems = (kot['items'] as List? ?? const [])
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .map(
                (item) => <String, dynamic>{
                  'name':
                      item['product_name']?.toString() ??
                      item['variant_name']?.toString() ??
                      item['sku']?.toString() ??
                      'Item',
                  'quantity': item['quantity'] ?? 1,
                },
              )
              .toList();

          await _hardware.printKot(
            profiles: kotProfiles,
            orderNumber:
                kotNumber ??
                order['order_number']?.toString() ??
                order['id'].toString(),
            orderType: order['order_type']?.toString() ?? 'dine_in',
            tableName: order['table_name']?.toString(),
            prepMinutes:
                (order['preparation_minutes'] as num?)?.toInt() ??
                int.tryParse('${order['preparation_minutes']}'),
            chefNote: order['chef_note']?.toString(),
            items: deltaItems,
          );
        }
      } catch (error) {
        kotWarning = error.toString();
      }

      if (kotWarning != null) {
        _message('Items added, but kitchen KOT needs attention: $kotWarning');
      } else if (!kotCreated) {
        _message('Items added. No unsent kitchen quantity was found.');
      } else {
        _message('${kotNumber ?? 'Delta KOT'} sent to kitchen.');
      }

      await _load();
    }
  }

  Future<void> _reserveRestaurantTable(Map<String, dynamic> table) async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant reservation permission required.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    var reservationAt = DateTime.now().add(const Duration(hours: 1));
    final name = TextEditingController(
      text: table['reservation_name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: table['reservation_phone']?.toString() ?? '',
    );
    final note = TextEditingController(
      text: table['reservation_note']?.toString() ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          Future<void> chooseDate() async {
            final picked = await showDatePicker(
              context: dialogContext,
              initialDate: reservationAt,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 730)),
            );
            if (picked == null || !dialogContext.mounted) return;
            setLocalState(() {
              reservationAt = DateTime(
                picked.year,
                picked.month,
                picked.day,
                reservationAt.hour,
                reservationAt.minute,
              );
            });
          }

          Future<void> chooseTime() async {
            final picked = await showTimePicker(
              context: dialogContext,
              initialTime: TimeOfDay.fromDateTime(reservationAt),
            );
            if (picked == null || !dialogContext.mounted) return;
            setLocalState(() {
              reservationAt = DateTime(
                reservationAt.year,
                reservationAt.month,
                reservationAt.day,
                picked.hour,
                picked.minute,
              );
            });
          }

          return AlertDialog(
            title: Text(
              'Reserve ${table['table_code'] ?? ''} â€¢ ${table['name'] ?? 'Table'}',
            ),
            content: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Guest / reservation name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: chooseDate,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            '${reservationAt.year.toString().padLeft(4, '0')}-'
                            '${reservationAt.month.toString().padLeft(2, '0')}-'
                            '${reservationAt.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: chooseTime,
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            '${reservationAt.hour.toString().padLeft(2, '0')}:'
                            '${reservationAt.minute.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Reservation note',
                      hintText: 'Optional',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (name.text.trim().isEmpty) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      const SnackBar(
                        content: Text('Reservation name is required.'),
                      ),
                    );
                    return;
                  }

                  try {
                    await _restaurant.reserveTable(
                      tenantId: widget.session.business.id,
                      tableId: table['id'].toString(),
                      deviceId: deviceId,
                      reservationName: name.text,
                      reservationPhone: phone.text,
                      reservationAt: reservationAt,
                      reservationNote: note.text,
                    );
                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext, true);
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    ThqNotify.showSnackBar(
                      dialogContext,
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                },
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Save Reservation'),
              ),
            ],
          );
        },
      ),
    );

    name.dispose();
    phone.dispose();
    note.dispose();

    if (saved == true) {
      _message('Table reservation saved.');
      await _load();
    }
  }

  Future<void> _clearRestaurantTableReservation(
    Map<String, dynamic> table,
  ) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    try {
      await _restaurant.clearTableReservation(
        tenantId: widget.session.business.id,
        tableId: table['id'].toString(),
        deviceId: deviceId,
      );
      _message('Table reservation cleared.');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _setRestaurantTableStatus(
    Map<String, dynamic> table,
    String status,
  ) async {
    if (!widget.session.hasPermission('restaurant.manage')) {
      _message('restaurant.manage permission required.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) return;

    try {
      await _restaurant.setTableOperationalStatus(
        tenantId: widget.session.business.id,
        tableId: table['id'].toString(),
        deviceId: deviceId,
        status: status,
      );
      _message('Table status changed to ${status.replaceAll('_', ' ')}.');
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _manageRestaurantTable(Map<String, dynamic> table) async {
    final status = table['operational_status']?.toString() ?? 'available';
    final hasReservation =
        table['reservation_at'] != null ||
        (table['reservation_name']?.toString().trim().isNotEmpty ?? false);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_restaurant_outlined),
                title: Text(
                  '${table['table_code'] ?? ''} â€¢ ${table['name'] ?? 'Table'}',
                ),
                subtitle: Text(
                  'Status: ${status.replaceAll('_', ' ')}'
                  '${hasReservation ? ' â€¢ Reserved for ${table['reservation_name'] ?? ''}' : ''}',
                ),
              ),
              if (_tableOrder(table['id']?.toString() ?? '') == null &&
                  status != 'cleaning' &&
                  status != 'out_of_service')
                ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(
                    hasReservation ? 'Edit Reservation' : 'Reserve Table',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _reserveRestaurantTable(table);
                  },
                ),
              if (hasReservation)
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: const Text('Clear Reservation'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _clearRestaurantTableReservation(table);
                  },
                ),
              if (widget.session.hasPermission('restaurant.manage')) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Mark Available'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _setRestaurantTableStatus(table, 'available');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Mark Cleaning'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _setRestaurantTableStatus(table, 'cleaning');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('Mark Out of Service'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _setRestaurantTableStatus(table, 'out_of_service');
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addWaitlistGuest() async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }

    final locationId = _locationId;
    final deviceId = _deviceId;
    if (locationId == null || deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    final guestName = TextEditingController();
    final phone = TextEditingController();
    final guestCount = TextEditingController(text: '2');
    final waitMinutes = TextEditingController(text: '15');
    final preferredArea = TextEditingController();
    final note = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Guest to Waitlist'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: guestName,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Guest name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: guestCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Guests'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: waitMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Estimated wait (minutes)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: preferredArea,
                decoration: const InputDecoration(
                  labelText: 'Preferred area / floor',
                  hintText: 'Optional',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Optional',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final name = guestName.text.trim();
              final guests = int.tryParse(guestCount.text.trim()) ?? 0;
              final estimate = int.tryParse(waitMinutes.text.trim()) ?? -1;

              if (name.isEmpty) {
                ThqNotify.showSnackBar(
                  dialogContext,
                  const SnackBar(content: Text('Guest name is required.')),
                );
                return;
              }
              if (guests < 1 || guests > 999) {
                ThqNotify.showSnackBar(
                  dialogContext,
                  const SnackBar(
                    content: Text('Guest count must be between 1 and 999.'),
                  ),
                );
                return;
              }
              if (estimate < 0 || estimate > 1440) {
                ThqNotify.showSnackBar(
                  dialogContext,
                  const SnackBar(
                    content: Text(
                      'Estimated wait must be between 0 and 1440 minutes.',
                    ),
                  ),
                );
                return;
              }

              try {
                await _restaurant.addWaitlistGuest(
                  tenantId: widget.session.business.id,
                  locationId: locationId,
                  deviceId: deviceId,
                  guestName: name,
                  phone: phone.text,
                  guestCount: guests,
                  estimatedWaitMinutes: estimate,
                  preferredArea: preferredArea.text,
                  note: note.text,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext, true);
              } catch (error) {
                if (!dialogContext.mounted) return;
                ThqNotify.showSnackBar(
                  dialogContext,
                  SnackBar(content: Text(error.toString())),
                );
              }
            },
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Add to Waitlist'),
          ),
        ],
      ),
    );

    guestName.dispose();
    phone.dispose();
    guestCount.dispose();
    waitMinutes.dispose();
    preferredArea.dispose();
    note.dispose();

    if (saved == true) {
      _message('Guest added to restaurant waitlist.');
      setState(() {});
    }
  }

  Future<void> _setWaitlistStatus(
    Map<String, dynamic> entry,
    String status, {
    String? tableId,
    String note = '',
  }) async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    try {
      final result = await _restaurant.setWaitlistStatus(
        tenantId: widget.session.business.id,
        waitlistId: entry['id'].toString(),
        deviceId: deviceId,
        status: status,
        tableId: tableId,
        note: note,
      );
      if (!mounted) return;

      if (status == 'seated') {
        _message(
          '${entry['guest_name'] ?? 'Guest'} seated at '
          '${result['table_name'] ?? 'selected table'}. '
          'Open that table to start the order.',
        );
      } else {
        _message(
          '${entry['guest_name'] ?? 'Guest'} â†’ '
          '${status.replaceAll('_', ' ').toUpperCase()}',
        );
      }
      setState(() {});
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _seatWaitlistGuest(Map<String, dynamic> entry) async {
    final guests =
        (entry['guest_count'] as num?)?.toInt() ??
        int.tryParse('${entry['guest_count']}') ??
        1;

    final availableTables = _tables.where((table) {
      if (table['active'] == false) return false;
      if ((table['operational_status']?.toString() ?? 'available') !=
          'available') {
        return false;
      }

      final id = table['id']?.toString() ?? '';
      if (id.isEmpty || _tableOrder(id) != null) return false;

      final capacity =
          (table['capacity'] as num?)?.toInt() ??
          int.tryParse('${table['capacity']}') ??
          0;
      return capacity >= guests;
    }).toList();

    if (availableTables.isEmpty) {
      _message('No available table can currently seat $guests guest(s).');
      return;
    }

    String tableId = availableTables.first['id'].toString();

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            'Seat ${entry['guest_name'] ?? 'Guest'} â€¢ $guests guest(s)',
          ),
          content: SizedBox(
            width: 560,
            child: DropdownButtonFormField<String>(
              initialValue: tableId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Available table'),
              items: availableTables
                  .map(
                    (table) => DropdownMenuItem<String>(
                      value: table['id'].toString(),
                      child: Text(
                        '${table['table_code'] ?? ''} â€¢ '
                        '${table['name'] ?? ''} â€¢ '
                        '${table['capacity'] ?? 0} seats',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setLocalState(() => tableId = value);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, tableId),
              icon: const Icon(Icons.event_seat_outlined),
              label: const Text('Seat Guest'),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;

    await _setWaitlistStatus(entry, 'seated', tableId: selected);
  }

  Future<void> _setKitchenKotStatus(
    Map<String, dynamic> kot,
    String status,
  ) async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    try {
      final result = await _restaurant.setKotStatus(
        tenantId: widget.session.business.id,
        kotId: kot['kot_id'].toString(),
        deviceId: deviceId,
        status: status,
      );
      if (!mounted) return;
      _message(
        '${result['kot_number'] ?? kot['kot_number'] ?? 'KOT'} â†’ '
        '${status.replaceAll('_', ' ').toUpperCase()}',
      );
      setState(() {});
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _moveItemsToExistingOrder(Map<String, dynamic> order) async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }

    if (order['order_type']?.toString() != 'dine_in') {
      _message('Only dine-in orders can move items between tables.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    final sourceOrderId = order['id']?.toString();
    if (sourceOrderId == null || sourceOrderId.isEmpty) {
      _message('Source restaurant order is missing.');
      return;
    }

    final targetOrders = _orders.where((candidate) {
      final id = candidate['id']?.toString();
      final status = candidate['status']?.toString() ?? '';
      return id != null &&
          id.isNotEmpty &&
          id != sourceOrderId &&
          candidate['order_type']?.toString() == 'dine_in' &&
          candidate['table_id'] != null &&
          status != 'billed' &&
          status != 'cancelled';
    }).toList();

    if (targetOrders.isEmpty) {
      _message(
        'No other active dine-in table order is available to receive items.',
      );
      return;
    }

    try {
      final detail = await _restaurant.detail(
        widget.session.business.id,
        sourceOrderId,
        deviceId,
      );
      if (!mounted) return;

      final activeItems = (detail['items'] as List? ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .where((item) {
            final quantity =
                (item['quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['quantity']}') ??
                0;
            final cancelled =
                (item['cancelled_quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['cancelled_quantity']}') ??
                0;
            return quantity - cancelled > 0.000001;
          })
          .toList();

      if (activeItems.isEmpty) {
        _message('This order has no active items to move.');
        return;
      }

      double activeQuantity(Map<String, dynamic> item) {
        final quantity =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            0;
        final cancelled =
            (item['cancelled_quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['cancelled_quantity']}') ??
            0;
        return (quantity - cancelled).clamp(0, double.infinity).toDouble();
      }

      String itemName(Map<String, dynamic> item) {
        final variantId = item['variant_id']?.toString();
        for (final product in _products) {
          if (product.variantId == variantId) {
            return product.productName;
          }
        }
        return 'Item ${variantId ?? item['id'] ?? ''}';
      }

      String quantityText(double value) {
        if ((value - value.roundToDouble()).abs() < 0.000001) {
          return value.toInt().toString();
        }
        return value
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
      }

      final quantityControllers = <String, TextEditingController>{};
      for (final item in activeItems) {
        quantityControllers[item['id'].toString()] = TextEditingController(
          text: '0',
        );
      }

      final note = TextEditingController();
      var targetOrderId = targetOrders.first['id'].toString();
      var sendTargetUnsentToKitchen = true;
      Map<String, dynamic>? moveResult;
      Map<String, dynamic>? selectedTarget;

      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            selectedTarget = targetOrders.firstWhere(
              (candidate) => candidate['id']?.toString() == targetOrderId,
              orElse: () => targetOrders.first,
            );

            return AlertDialog(
              title: const Text('Move Selected Items to Existing Table'),
              content: SizedBox(
                width: 760,
                height: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'From ${order['table_name'] ?? 'current table'} - '
                        '${order['order_number'] ?? 'order'}. '
                        'Choose an existing occupied table/order and the exact '
                        'item quantities to move.',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    DropdownButtonFormField<String>(
                      initialValue: targetOrderId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Move items to',
                      ),
                      items: targetOrders
                          .map(
                            (target) => DropdownMenuItem<String>(
                              value: target['id'].toString(),
                              child: Text(
                                '${target['table_name'] ?? 'Table'} - '
                                '${target['order_number'] ?? 'Order'} - '
                                '${target['guest_count'] ?? 1} guest(s)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() => targetOrderId = value);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Items to move',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: ListView.separated(
                        itemCount: activeItems.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = activeItems[index];
                          final itemId = item['id'].toString();
                          final active = activeQuantity(item);
                          final sent =
                              (item['kot_sent_quantity'] as num?)?.toDouble() ??
                              double.tryParse('${item['kot_sent_quantity']}') ??
                              0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName(item),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        'Available ${quantityText(active)}'
                                        '${sent > 0 ? ' - KOT sent ${quantityText(sent)}' : ''}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 145,
                                  child: TextField(
                                    controller: quantityControllers[itemId],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'Move qty',
                                      suffixText: '/ ${quantityText(active)}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: sendTargetUnsentToKitchen,
                      title: const Text(
                        'Send target table unsent items to kitchen',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: const Text(
                        'Recommended. This queues all currently unsent items '
                        'on the destination order after the move.',
                        style: TextStyle(fontSize: 9),
                      ),
                      onChanged: (value) {
                        setLocalState(() => sendTargetUnsentToKitchen = value);
                      },
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Move note',
                        hintText: 'Optional reason / instruction',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final items = <Map<String, dynamic>>[];
                    var sourceQuantity = 0.0;
                    var movedQuantity = 0.0;

                    for (final item in activeItems) {
                      final active = activeQuantity(item);
                      sourceQuantity += active;
                      final itemId = item['id'].toString();
                      final quantity =
                          double.tryParse(
                            quantityControllers[itemId]!.text.trim(),
                          ) ??
                          0;

                      if (quantity < 0 || quantity > active + 0.000001) {
                        ThqNotify.showSnackBar(
                          dialogContext,
                          SnackBar(
                            content: Text(
                              '${itemName(item)} move quantity must be '
                              'between 0 and ${quantityText(active)}.',
                            ),
                          ),
                        );
                        return;
                      }

                      if (quantity > 0.000001) {
                        items.add({
                          'order_item_id': itemId,
                          'quantity': quantity,
                        });
                        movedQuantity += quantity;
                      }
                    }

                    if (items.isEmpty) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        const SnackBar(
                          content: Text(
                            'Enter a quantity for at least one item.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (movedQuantity >= sourceQuantity - 0.000001) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        const SnackBar(
                          content: Text(
                            'This would empty the source order. Use '
                            'Merge Tables / Orders instead.',
                          ),
                        ),
                      );
                      return;
                    }

                    try {
                      moveResult = await _restaurant.moveItems(
                        tenantId: widget.session.business.id,
                        sourceOrderId: sourceOrderId,
                        targetOrderId: targetOrderId,
                        deviceId: deviceId,
                        items: items,
                        note: note.text,
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext, true);
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  },
                  icon: const Icon(Icons.compare_arrows_rounded),
                  label: const Text('Move Items'),
                ),
              ],
            );
          },
        ),
      );

      for (final controller in quantityControllers.values) {
        controller.dispose();
      }
      note.dispose();

      if (saved != true || !mounted) return;

      final target =
          selectedTarget ??
          targetOrders.firstWhere(
            (candidate) => candidate['id']?.toString() == targetOrderId,
            orElse: () => targetOrders.first,
          );

      if (!sendTargetUnsentToKitchen) {
        _message(
          'Moved ${moveResult?['quantity_moved'] ?? ''} item quantity to '
          '${moveResult?['target_table_name'] ?? target['table_name'] ?? 'target table'}.',
        );
        await _load();
        return;
      }

      Map<String, dynamic>? kotResult;
      String? kotError;
      String? printWarning;

      try {
        final rawKot = await _restaurant.sendKot(
          widget.session.business.id,
          targetOrderId,
          deviceId,
          'Items moved from ${order['order_number'] ?? 'restaurant order'}',
        );
        kotResult = Map<String, dynamic>.from(rawKot);
      } catch (error) {
        kotError = error.toString();
      }

      if (kotError == null && kotResult?['kot_created'] == true && mounted) {
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

          final kotItems = (kotResult?['items'] as List? ?? const []).map((
            raw,
          ) {
            final item = Map<String, dynamic>.from(raw as Map);
            return <String, dynamic>{
              'name':
                  item['product_name']?.toString() ??
                  item['variant_name']?.toString() ??
                  item['sku']?.toString() ??
                  'Item',
              'quantity':
                  (item['quantity'] as num?)?.toDouble() ??
                  double.tryParse('${item['quantity']}') ??
                  0,
            };
          }).toList();

          await _hardware.printKot(
            profiles: kotProfiles,
            orderNumber: target['order_number']?.toString() ?? targetOrderId,
            orderType: 'dine_in',
            tableName: target['table_name']?.toString(),
            prepMinutes:
                (target['preparation_minutes'] as num?)?.toInt() ??
                int.tryParse('${target['preparation_minutes']}') ??
                0,
            chefNote:
                'Items moved from ${order['order_number'] ?? 'restaurant order'}',
            items: kotItems,
          );
        } catch (error) {
          printWarning = error.toString();
        }
      }

      if (!mounted) return;

      if (kotError != null) {
        _message('Items moved successfully, but KOT send failed: $kotError');
      } else if (kotResult?['kot_created'] == true) {
        final kotNumber = kotResult?['kot_number']?.toString() ?? 'KOT';
        if (printWarning == null) {
          _message('Items moved and $kotNumber sent to kitchen.');
        } else {
          _message('Items moved and $kotNumber queued. Printer: $printWarning');
        }
      } else {
        _message(
          'Items moved. No new KOT was required for the destination order.',
        );
      }

      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _splitRestaurantOrder(Map<String, dynamic> order) async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }

    if (order['order_type']?.toString() != 'dine_in') {
      _message('Only dine-in orders can be split to another table.');
      return;
    }

    final sourceGuests =
        (order['guest_count'] as num?)?.toInt() ??
        int.tryParse('${order['guest_count']}') ??
        1;
    if (sourceGuests <= 1) {
      _message('At least 2 guests are required to split a table.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    final sourceTableId = order['table_id']?.toString();
    if (sourceTableId == null || sourceTableId.isEmpty) {
      _message('This dine-in order is not assigned to a table.');
      return;
    }

    try {
      final detail = await _restaurant.detail(
        widget.session.business.id,
        order['id'].toString(),
        deviceId,
      );
      if (!mounted) return;

      final activeItems = (detail['items'] as List? ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .where((item) {
            final quantity =
                (item['quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['quantity']}') ??
                0;
            final cancelled =
                (item['cancelled_quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['cancelled_quantity']}') ??
                0;
            return quantity - cancelled > 0.000001;
          })
          .toList();

      if (activeItems.isEmpty) {
        _message('This order has no active items to split.');
        return;
      }

      final availableTables = _tables.where((table) {
        if (table['active'] == false) return false;
        final tableId = table['id']?.toString() ?? '';
        if (tableId.isEmpty || tableId == sourceTableId) return false;
        if ((table['operational_status']?.toString() ?? 'available') !=
            'available') {
          return false;
        }
        return _tableOrder(tableId) == null;
      }).toList();

      if (availableTables.isEmpty) {
        _message('No available destination table is free.');
        return;
      }

      double activeQuantity(Map<String, dynamic> item) {
        final quantity =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            0;
        final cancelled =
            (item['cancelled_quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['cancelled_quantity']}') ??
            0;
        return (quantity - cancelled).clamp(0, double.infinity).toDouble();
      }

      String itemName(Map<String, dynamic> item) {
        final variantId = item['variant_id']?.toString();
        for (final product in _products) {
          if (product.variantId == variantId) {
            return product.productName;
          }
        }
        return 'Item ${variantId ?? item['id'] ?? ''}';
      }

      String quantityText(double value) {
        if ((value - value.roundToDouble()).abs() < 0.000001) {
          return value.toInt().toString();
        }
        return value
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
      }

      final quantityControllers = <String, TextEditingController>{};
      for (final item in activeItems) {
        quantityControllers[item['id'].toString()] = TextEditingController(
          text: '0',
        );
      }

      final note = TextEditingController();
      var movingGuests = 1;
      var destinationTableId = availableTables.first['id'].toString();
      Map<String, dynamic>? splitResult;

      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            final destination = availableTables.firstWhere(
              (table) => table['id']?.toString() == destinationTableId,
              orElse: () => availableTables.first,
            );
            final capacity =
                (destination['capacity'] as num?)?.toInt() ??
                int.tryParse('${destination['capacity']}') ??
                0;

            return AlertDialog(
              title: Text(
                'Split ${order['order_number'] ?? 'Restaurant Order'}',
              ),
              content: SizedBox(
                width: 760,
                height: 590,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Source: ${order['table_name'] ?? 'Current table'} - '
                        '$sourceGuests guest(s). Select the guests and item '
                        'quantities moving to the new table.',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: destinationTableId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Destination table',
                            ),
                            items: availableTables
                                .map(
                                  (table) => DropdownMenuItem<String>(
                                    value: table['id'].toString(),
                                    child: Text(
                                      '${table['table_code'] ?? ''} - '
                                      '${table['name'] ?? ''} - '
                                      '${table['capacity'] ?? 0} seats',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setLocalState(() => destinationTableId = value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: movingGuests,
                            decoration: const InputDecoration(
                              labelText: 'Guests moving',
                            ),
                            items: [
                              for (
                                var guests = 1;
                                guests < sourceGuests;
                                guests++
                              )
                                DropdownMenuItem<int>(
                                  value: guests,
                                  child: Text('$guests'),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setLocalState(() => movingGuests = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      capacity < movingGuests
                          ? 'Selected table has only $capacity seat(s). Choose '
                                'another table or move fewer guests.'
                          : '$capacity seats available at the destination.',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: capacity < movingGuests
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: capacity < movingGuests
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Items to move',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: ListView.separated(
                        itemCount: activeItems.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = activeItems[index];
                          final itemId = item['id'].toString();
                          final active = activeQuantity(item);
                          final sent =
                              (item['kot_sent_quantity'] as num?)?.toDouble() ??
                              double.tryParse('${item['kot_sent_quantity']}') ??
                              0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName(item),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        'Available ${quantityText(active)}'
                                        '${sent > 0 ? ' - KOT sent ${quantityText(sent)}' : ''}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 145,
                                  child: TextField(
                                    controller: quantityControllers[itemId],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'Move qty',
                                      suffixText: '/ ${quantityText(active)}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: note,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Split note',
                        hintText: 'Optional',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final selectedTable = availableTables.firstWhere(
                      (table) => table['id']?.toString() == destinationTableId,
                      orElse: () => availableTables.first,
                    );
                    final selectedCapacity =
                        (selectedTable['capacity'] as num?)?.toInt() ??
                        int.tryParse('${selectedTable['capacity']}') ??
                        0;

                    if (selectedCapacity < movingGuests) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(
                          content: Text(
                            'Destination table has only '
                            '$selectedCapacity seat(s).',
                          ),
                        ),
                      );
                      return;
                    }

                    final items = <Map<String, dynamic>>[];
                    var sourceQuantity = 0.0;
                    var movedQuantity = 0.0;

                    for (final item in activeItems) {
                      final active = activeQuantity(item);
                      sourceQuantity += active;
                      final itemId = item['id'].toString();
                      final quantity =
                          double.tryParse(
                            quantityControllers[itemId]!.text.trim(),
                          ) ??
                          0;

                      if (quantity < 0 || quantity > active + 0.000001) {
                        ThqNotify.showSnackBar(
                          dialogContext,
                          SnackBar(
                            content: Text(
                              '${itemName(item)} move quantity must be '
                              'between 0 and ${quantityText(active)}.',
                            ),
                          ),
                        );
                        return;
                      }

                      if (quantity > 0.000001) {
                        items.add({
                          'order_item_id': itemId,
                          'quantity': quantity,
                        });
                        movedQuantity += quantity;
                      }
                    }

                    if (items.isEmpty) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        const SnackBar(
                          content: Text(
                            'Enter a quantity for at least one item.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (movedQuantity >= sourceQuantity - 0.000001) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        const SnackBar(
                          content: Text(
                            'A split must leave at least one active item on '
                            'the source table. Use Move to Another Table when '
                            'moving the whole order.',
                          ),
                        ),
                      );
                      return;
                    }

                    try {
                      splitResult = await _restaurant.splitOrder(
                        tenantId: widget.session.business.id,
                        sourceOrderId: order['id'].toString(),
                        deviceId: deviceId,
                        toTableId: destinationTableId,
                        items: items,
                        guestCount: movingGuests,
                        note: note.text,
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext, true);
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  },
                  icon: const Icon(Icons.call_split_rounded),
                  label: const Text('Split to Table'),
                ),
              ],
            );
          },
        ),
      );

      for (final controller in quantityControllers.values) {
        controller.dispose();
      }
      note.dispose();

      if (saved == true && mounted) {
        _message(
          'Split complete: ${splitResult?['target_order_number'] ?? 'new order'} '
          'to ${splitResult?['target_table_name'] ?? 'destination table'}.',
        );
        await _load();
      }
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _mergeRestaurantOrder(Map<String, dynamic> targetOrder) async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }

    if (targetOrder['order_type']?.toString() != 'dine_in') {
      _message('Only dine-in restaurant orders can be merged.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    final targetId = targetOrder['id']?.toString();
    if (targetId == null || targetId.isEmpty) return;

    final candidates = _orders.where((order) {
      final id = order['id']?.toString();
      final status = order['status']?.toString() ?? '';
      return id != null &&
          id.isNotEmpty &&
          id != targetId &&
          order['order_type']?.toString() == 'dine_in' &&
          order['table_id'] != null &&
          status != 'billed' &&
          status != 'cancelled';
    }).toList();

    if (candidates.isEmpty) {
      _message('No other active dine-in table order is available to merge.');
      return;
    }

    String sourceOrderId = candidates.first['id'].toString();
    final note = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final targetLabel =
              '${targetOrder['table_name'] ?? 'Table'} â€¢ '
              '${targetOrder['order_number'] ?? 'Order'}';

          return AlertDialog(
            title: const Text('Merge Tables / Orders'),
            content: SizedBox(
              width: 640,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Keep as target: $targetLabel',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: sourceOrderId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Merge this table/order into target',
                    ),
                    items: candidates
                        .map(
                          (order) => DropdownMenuItem<String>(
                            value: order['id'].toString(),
                            child: Text(
                              '${order['table_name'] ?? 'Table'} â€¢ '
                              '${order['order_number'] ?? 'Order'} â€¢ '
                              '${_money(order['total'])}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => sourceOrderId = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Merge note',
                      hintText: 'Optional',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'The selected source order will be absorbed into the '
                      'target order. Its items and KOT history move to the '
                      'target, its table becomes free, and final billing '
                      'continues only from the target order.',
                      style: TextStyle(fontSize: 11),
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
                onPressed: () async {
                  try {
                    final merge = await _restaurant.mergeOrders(
                      tenantId: widget.session.business.id,
                      targetOrderId: targetId,
                      sourceOrderId: sourceOrderId,
                      deviceId: deviceId,
                      note: note.text,
                    );
                    if (!dialogContext.mounted) return;
                    Navigator.pop(
                      dialogContext,
                      Map<String, dynamic>.from(merge),
                    );
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    ThqNotify.showSnackBar(
                      dialogContext,
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                },
                icon: const Icon(Icons.merge_type),
                label: const Text('Merge Into Target'),
              ),
            ],
          );
        },
      ),
    );

    note.dispose();

    if (result == null) return;

    _message(
      '${result['source_order_number'] ?? 'Source order'} merged into '
      '${result['target_order_number'] ?? 'target order'}.',
    );
    await _load();
  }

  Future<void> _transferOrderTable(Map<String, dynamic> order) async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }

    if (order['order_type']?.toString() != 'dine_in') {
      _message('Only dine-in orders can be moved between tables.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }

    final currentTableId = order['table_id']?.toString();
    if (currentTableId == null || currentTableId.isEmpty) {
      _message('This restaurant order has no current table.');
      return;
    }

    final availableTables = _tables.where((table) {
      if (table['active'] == false) return false;

      final id = table['id']?.toString() ?? '';
      if (id.isEmpty || id == currentTableId) return false;

      final operationalStatus =
          table['operational_status']?.toString() ?? 'available';
      if (operationalStatus != 'available') return false;

      return _tableOrder(id) == null;
    }).toList();

    if (availableTables.isEmpty) {
      _message('No available destination table was found.');
      return;
    }

    String toTableId = availableTables.first['id'].toString();
    final note = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            'Move Table â€¢ ${order['order_number'] ?? 'Restaurant Order'}',
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: toTableId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Move to table'),
                  items: availableTables
                      .map(
                        (table) => DropdownMenuItem<String>(
                          value: table['id'].toString(),
                          child: Text(
                            '${table['table_code'] ?? ''} â€¢ '
                            '${table['name'] ?? ''} '
                            '(Capacity ${table['capacity'] ?? '-'})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setLocalState(() => toTableId = value);
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Transfer note',
                    hintText: 'Optional',
                  ),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'The destination must be active, available and have no '
                    'other live restaurant order.',
                    style: TextStyle(fontSize: 11),
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
              onPressed: () async {
                try {
                  final transfer = await _restaurant.transferTable(
                    tenantId: widget.session.business.id,
                    orderId: order['id'].toString(),
                    deviceId: deviceId,
                    toTableId: toTableId,
                    note: note.text,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(
                    dialogContext,
                    Map<String, dynamic>.from(transfer),
                  );
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ThqNotify.showSnackBar(
                    dialogContext,
                    SnackBar(content: Text(error.toString())),
                  );
                }
              },
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Move Table'),
            ),
          ],
        ),
      ),
    );

    note.dispose();

    if (result == null) return;

    _message(
      'Order moved from '
      '${result['from_table_name'] ?? 'previous table'} to '
      '${result['to_table_name'] ?? 'new table'}.',
    );
    await _load();
  }

  Future<void> _voidOrderItem(Map<String, dynamic> order) async {
    if (!widget.session.hasPermission('restaurant.order') &&
        !widget.session.hasPermission('restaurant.manage')) {
      _message('Restaurant order permission required.');
      return;
    }

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

      final rawItems = detail['items'] as List? ?? const [];
      final activeItems = rawItems
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .where((item) {
            final quantity =
                (item['quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['quantity']}') ??
                0;
            final cancelled =
                (item['cancelled_quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['cancelled_quantity']}') ??
                0;
            return quantity - cancelled > 0.000001;
          })
          .toList();

      if (activeItems.isEmpty) {
        _message('This order has no active item quantity to cancel.');
        return;
      }

      String selectedItemId = activeItems.first['id'].toString();
      final cancelQuantity = TextEditingController(text: '1');
      final reason = TextEditingController();

      Map<String, dynamic> selectedItem() => activeItems.firstWhere(
        (item) => item['id'].toString() == selectedItemId,
      );

      double remainingFor(Map<String, dynamic> item) {
        final quantity =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            0;
        final cancelled =
            (item['cancelled_quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['cancelled_quantity']}') ??
            0;
        return (quantity - cancelled).clamp(0, double.infinity).toDouble();
      }

      final voidResult = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            final item = selectedItem();
            final remaining = remainingFor(item);
            final productName = _restaurantProductLabel(
              item['variant_id']?.toString(),
            );

            return AlertDialog(
              title: Text(
                'Void / Cancel Item â€¢ ${order['order_number'] ?? 'Order'}',
              ),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedItemId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Order item',
                      ),
                      items: activeItems
                          .map(
                            (row) => DropdownMenuItem<String>(
                              value: row['id'].toString(),
                              child: Text(
                                '${_restaurantProductLabel(row['variant_id']?.toString())} '
                                'â€¢ Remaining ${remainingFor(row).toStringAsFixed(2)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setLocalState(() {
                          selectedItemId = value;
                          final next = selectedItem();
                          final nextRemaining = remainingFor(next);
                          cancelQuantity.text = nextRemaining >= 1
                              ? '1'
                              : nextRemaining.toString();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$productName â€¢ Active quantity ${remaining.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cancelQuantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Quantity to cancel',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            setLocalState(() {
                              cancelQuantity.text = remaining.toString();
                            });
                          },
                          child: const Text('Cancel All Remaining'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reason,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Cancellation / void reason',
                        hintText: 'Required',
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'If this quantity was already sent to the kitchen, '
                        'THQ will create and print a VOID KOT. Unsent quantity '
                        'is cancelled without generating a kitchen void.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final value =
                        double.tryParse(cancelQuantity.text.trim()) ?? 0;
                    final reasonText = reason.text.trim();

                    if (value <= 0 || value > remaining) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(
                          content: Text(
                            'Enter a quantity between 0 and '
                            '${remaining.toStringAsFixed(2)}.',
                          ),
                        ),
                      );
                      return;
                    }
                    if (reasonText.isEmpty) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        const SnackBar(
                          content: Text('Cancellation reason is required.'),
                        ),
                      );
                      return;
                    }

                    try {
                      final result = await _restaurant.cancelItem(
                        tenantId: widget.session.business.id,
                        orderId: order['id'].toString(),
                        orderItemId: selectedItemId,
                        deviceId: deviceId,
                        cancelQuantity: value,
                        reason: reasonText,
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.pop(
                        dialogContext,
                        Map<String, dynamic>.from(result),
                      );
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  },
                  icon: const Icon(Icons.remove_shopping_cart_outlined),
                  label: const Text('Confirm Void / Cancel'),
                ),
              ],
            );
          },
        ),
      );

      cancelQuantity.dispose();
      reason.dispose();

      if (voidResult == null) return;

      String? printWarning;
      final voidKotCreated = voidResult['void_kot_created'] == true;

      if (voidKotCreated) {
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

          final voidItems = (voidResult['void_items'] as List? ?? const [])
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .map(
                (item) => <String, dynamic>{
                  'name':
                      item['product_name']?.toString() ??
                      item['variant_name']?.toString() ??
                      item['sku']?.toString() ??
                      'Item',
                  'quantity': item['quantity'] ?? 1,
                },
              )
              .toList();

          await _hardware.printKot(
            profiles: kotProfiles,
            title: 'VOID KOT',
            orderNumber:
                voidResult['void_kot_number']?.toString() ??
                order['order_number']?.toString() ??
                order['id'].toString(),
            orderType: order['order_type']?.toString() ?? 'dine_in',
            tableName: order['table_name']?.toString(),
            prepMinutes:
                (order['preparation_minutes'] as num?)?.toInt() ??
                int.tryParse('${order['preparation_minutes']}'),
            chefNote: 'VOID: ${voidResult['reason'] ?? ''}',
            items: voidItems,
          );
        } catch (error) {
          printWarning = error.toString();
        }
      }

      if (printWarning != null) {
        _message(
          'Item cancellation saved. VOID KOT printer needs attention: '
          '$printWarning',
        );
      } else if (voidKotCreated) {
        _message(
          '${voidResult['void_kot_number'] ?? 'VOID KOT'} sent to kitchen.',
        );
      } else {
        _message('Item quantity cancelled before kitchen send.');
      }

      await _load();
    } catch (error) {
      _message(error.toString());
    }
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
        final cancelledQuantity =
            (item['cancelled_quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['cancelled_quantity']}') ??
            0;
        final activeQuantity = (quantity - cancelledQuantity)
            .clamp(0, double.infinity)
            .toDouble();
        final unitPrice =
            (item['unit_price'] as num?)?.toDouble() ??
            double.tryParse('${item['unit_price']}') ??
            0;
        final discount =
            (item['discount_amount'] as num?)?.toDouble() ??
            double.tryParse('${item['discount_amount']}') ??
            0;
        final activeDiscount = quantity > 0
            ? discount * (activeQuantity / quantity)
            : 0.0;
        final taxRate =
            (item['tax_rate'] as num?)?.toDouble() ??
            double.tryParse('${item['tax_rate']}') ??
            0;
        final taxable = (activeQuantity * unitPrice - activeDiscount).clamp(
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
                    ThqNotify.showSnackBar(
                      dialogContext,
                      const SnackBar(
                        content: Text(
                          'Round off must be between -1.00 and +1.00.',
                        ),
                      ),
                    );
                    return;
                  }
                  if (total + roundOff < 0) {
                    ThqNotify.showSnackBar(
                      dialogContext,
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
    final scheme = Theme.of(context).colorScheme;
    final status = (order['status'] ?? 'open').toString();
    final title =
        '${order['order_number']} | ${order['table_name'] ?? order['order_type']}';

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 54 : 60),
      margin: EdgeInsets.only(bottom: compact ? 4 : 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              order['order_type'] == 'dine_in'
                  ? Icons.table_restaurant
                  : order['order_type'] == 'delivery'
                  ? Icons.delivery_dining
                  : Icons.takeout_dining,
              size: 15,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${order['customer_name'] ?? 'Walk-in'} | '
                  'Prep ${order['preparation_minutes'] ?? 0} min',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            _money(order['total']),
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
          ),
          PopupMenuButton<String>(
            tooltip: 'Order actions',
            onSelected: (value) {
              if (value == 'edit') {
                _editOrder(order);
              } else if (value == 'add_items') {
                _addItemsToOrder(order);
              } else if (value == 'void_item') {
                _voidOrderItem(order);
              } else if (value == 'transfer_table') {
                _transferOrderTable(order);
              } else if (value == 'merge_order') {
                _mergeRestaurantOrder(order);
              } else if (value == 'split_order') {
                _splitRestaurantOrder(order);
              } else if (value == 'move_items') {
                _moveItemsToExistingOrder(order);
              } else if (value == 'bill') {
                _bill(order);
              } else {
                _setStatus(order, value);
              }
            },
            itemBuilder: (_) => [
              if (status != 'billed' && status != 'cancelled')
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit Order / Guest / Waiter'),
                ),
              if (status != 'billed' && status != 'cancelled')
                const PopupMenuItem(
                  value: 'add_items',
                  child: Text('Add Items'),
                ),
              if (status != 'billed' &&
                  status != 'cancelled' &&
                  order['order_type']?.toString() == 'dine_in')
                const PopupMenuItem(
                  value: 'transfer_table',
                  child: Text('Move to Another Table'),
                ),
              if (status != 'billed' &&
                  status != 'cancelled' &&
                  order['order_type']?.toString() == 'dine_in')
                const PopupMenuItem(
                  value: 'merge_order',
                  child: Text('Merge Tables / Orders'),
                ),
              if (status != 'billed' &&
                  status != 'cancelled' &&
                  order['order_type']?.toString() == 'dine_in')
                const PopupMenuItem(
                  value: 'split_order',
                  child: Text('Split Table / Order'),
                ),
              if (status != 'billed' &&
                  status != 'cancelled' &&
                  order['order_type']?.toString() == 'dine_in')
                const PopupMenuItem(
                  value: 'move_items',
                  child: Text('Move Selected Items to Existing Table'),
                ),
              if (status != 'billed' && status != 'cancelled')
                const PopupMenuItem(
                  value: 'void_item',
                  child: Text('Void / Cancel Item'),
                ),
              if (status == 'open' || status == 'sent_to_kitchen')
                const PopupMenuItem(
                  value: 'preparing',
                  child: Text('Start Preparing'),
                ),
              if (status == 'preparing' || status == 'sent_to_kitchen')
                const PopupMenuItem(value: 'ready', child: Text('Mark Ready')),
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
            icon: const Icon(Icons.more_vert, size: 15),
          ),
        ],
      ),
    );
  }

  Widget _floorView() {
    final active = _tables.where((table) => table['active'] != false).toList();
    final scheme = Theme.of(context).colorScheme;

    if (active.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_restaurant_outlined,
              size: 36,
              color: scheme.outline,
            ),
            const SizedBox(height: 7),
            const Text(
              'No restaurant tables configured.',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (widget.session.hasPermission('restaurant.manage'))
              FilledButton.icon(
                onPressed: _addTable,
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Add First Table'),
              ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(5),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 136,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: active.length,
      itemBuilder: (context, index) {
        final table = active[index];
        final id = table['id']?.toString() ?? '';
        final order = _tableOrder(id);
        final occupied = order != null;
        final operationalStatus =
            table['operational_status']?.toString() ?? 'available';
        final reserved = operationalStatus == 'reserved';
        final blocked =
            operationalStatus == 'cleaning' ||
            operationalStatus == 'out_of_service';

        return Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: occupied
                ? () => _editOrder(order)
                : (reserved || blocked)
                ? () => _manageRestaurantTable(table)
                : _newOrder,
            onLongPress: () => _manageRestaurantTable(table),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        occupied
                            ? Icons.restaurant
                            : Icons.table_restaurant_outlined,
                        size: 17,
                        color: scheme.primary,
                      ),
                      const Spacer(),
                      Text(
                        occupied
                            ? 'OCCUPIED'
                            : operationalStatus
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: occupied
                              ? scheme.error
                              : reserved
                              ? scheme.tertiary
                              : blocked
                              ? scheme.outline
                              : scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${table['table_code']} | ${table['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${table['area'] ?? 'Main floor'} | '
                    '${table['capacity'] ?? 0} seats',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (!occupied && reserved) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reserved: ${table['reservation_name'] ?? 'Guest'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      table['reservation_at']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9.5),
                    ),
                  ],
                  if (!occupied && blocked) ...[
                    const SizedBox(height: 4),
                    Text(
                      operationalStatus == 'cleaning'
                          ? 'Table is being cleaned'
                          : 'Table temporarily unavailable',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                  if (occupied) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${order['order_number']} | ${_money(order['total'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      (order['status'] ?? '')
                          .toString()
                          .replaceAll('_', ' ')
                          .toUpperCase(),
                      maxLines: 1,
                      style: const TextStyle(fontSize: 10),
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
      return const Center(
        child: Text(
          'No live restaurant orders.',
          style: TextStyle(fontSize: 11),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(5),
        itemCount: _orders.length,
        itemBuilder: (context, index) => _orderCard(_orders[index]),
      ),
    );
  }

  Widget _waitlistView() {
    final locationId = _locationId;
    final deviceId = _deviceId;
    final scheme = Theme.of(context).colorScheme;

    if (locationId == null || deviceId == null) {
      return const Center(
        child: Text(
          'This POS is not registered to a restaurant location.',
          style: TextStyle(fontSize: 11),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _restaurant.waitlist(
        tenantId: widget.session.business.id,
        locationId: locationId,
        deviceId: deviceId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: scheme.error),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry Waitlist'),
                  ),
                ],
              ),
            ),
          );
        }

        final rows = snapshot.data ?? const <Map<String, dynamic>>[];

        return Column(
          children: [
            SizedBox(
              height: 38,
              child: Row(
                children: [
                  Text(
                    '${rows.length} waiting guest group(s)',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Refresh'),
                  ),
                  const SizedBox(width: 5),
                  FilledButton.icon(
                    onPressed: _addWaitlistGuest,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
                    label: const Text('Add Guest'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.groups_2_outlined,
                            size: 38,
                            color: scheme.outline,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No guests are currently waiting.',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _addWaitlistGuest,
                            icon: const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 15,
                            ),
                            label: const Text('Add First Guest'),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(5),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 5),
                      itemBuilder: (context, index) {
                        final entry = rows[index];
                        final status = entry['status']?.toString() ?? 'waiting';
                        final waited =
                            (entry['waiting_minutes'] as num?)?.toInt() ??
                            int.tryParse('${entry['waiting_minutes']}') ??
                            0;
                        final estimate =
                            (entry['estimated_wait_minutes'] as num?)
                                ?.toInt() ??
                            int.tryParse(
                              '${entry['estimated_wait_minutes']}',
                            ) ??
                            0;
                        final guests =
                            (entry['guest_count'] as num?)?.toInt() ??
                            int.tryParse('${entry['guest_count']}') ??
                            1;
                        final overdue = estimate > 0 && waited >= estimate;

                        return Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 19,
                                  child: Text(
                                    '$guests',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              entry['guest_name']?.toString() ??
                                                  'Guest',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: status == 'notified'
                                                  ? scheme.tertiaryContainer
                                                  : scheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              status
                                                  .replaceAll('_', ' ')
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        [
                                          '$guests guest(s)',
                                          if (entry['phone']
                                                  ?.toString()
                                                  .trim()
                                                  .isNotEmpty ??
                                              false)
                                            entry['phone'].toString(),
                                          if (entry['preferred_area']
                                                  ?.toString()
                                                  .trim()
                                                  .isNotEmpty ??
                                              false)
                                            entry['preferred_area'].toString(),
                                        ].join(' â€¢ '),
                                        style: TextStyle(
                                          fontSize: 9.8,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.schedule_outlined,
                                            size: 14,
                                            color: overdue
                                                ? scheme.error
                                                : scheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Waiting $waited min â€¢ estimate $estimate min',
                                            style: TextStyle(
                                              fontSize: 9.8,
                                              fontWeight: overdue
                                                  ? FontWeight.w900
                                                  : FontWeight.w600,
                                              color: overdue
                                                  ? scheme.error
                                                  : scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (entry['note']
                                              ?.toString()
                                              .trim()
                                              .isNotEmpty ??
                                          false) ...[
                                        const SizedBox(height: 5),
                                        Text(
                                          entry['note'].toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 9.6,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 5,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    if (status == 'waiting')
                                      OutlinedButton(
                                        onPressed: () => _setWaitlistStatus(
                                          entry,
                                          'notified',
                                        ),
                                        child: const Text('Notify'),
                                      ),
                                    if (status == 'waiting' ||
                                        status == 'notified')
                                      FilledButton.icon(
                                        onPressed: () =>
                                            _seatWaitlistGuest(entry),
                                        icon: const Icon(
                                          Icons.event_seat_outlined,
                                          size: 15,
                                        ),
                                        label: const Text('Seat'),
                                      ),
                                    if (status == 'notified')
                                      OutlinedButton(
                                        onPressed: () => _setWaitlistStatus(
                                          entry,
                                          'no_show',
                                        ),
                                        child: const Text('No Show'),
                                      ),
                                    if (status == 'waiting' ||
                                        status == 'notified')
                                      TextButton(
                                        onPressed: () => _setWaitlistStatus(
                                          entry,
                                          'cancelled',
                                        ),
                                        child: const Text('Cancel'),
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
        );
      },
    );
  }

  Widget _kitchenView() {
    final locationId = _locationId;
    final deviceId = _deviceId;
    final scheme = Theme.of(context).colorScheme;

    if (locationId == null || deviceId == null) {
      return const Center(
        child: Text(
          'This POS is not registered to a restaurant location.',
          style: TextStyle(fontSize: 11),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _restaurant.kitchenQueue(
        tenantId: widget.session.business.id,
        locationId: locationId,
        deviceId: deviceId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: scheme.error),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry Kitchen Queue'),
                  ),
                ],
              ),
            ),
          );
        }

        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final groups = <String, List<Map<String, dynamic>>>{
          'QUEUED': rows
              .where((kot) => kot['status']?.toString() == 'queued')
              .toList(),
          'PREPARING': rows
              .where((kot) => kot['status']?.toString() == 'preparing')
              .toList(),
          'READY': rows
              .where((kot) => kot['status']?.toString() == 'ready')
              .toList(),
        };

        Widget kotCard(Map<String, dynamic> kot) {
          final kind = kot['kind']?.toString() ?? 'items';
          final status = kot['status']?.toString() ?? 'queued';
          final items = (kot['items'] as List? ?? const [])
              .map((raw) => Map<String, dynamic>.from(raw as Map))
              .toList();
          final elapsed =
              (kot['elapsed_minutes'] as num?)?.toInt() ??
              int.tryParse('${kot['elapsed_minutes']}') ??
              0;
          final isVoid = kind == 'void';
          final tableName = kot['table_name']?.toString().trim() ?? '';
          final orderType =
              kot['order_type']?.toString().replaceAll('_', ' ') ?? '';

          String modifiersText(Map<String, dynamic> item) {
            final modifiers = (item['modifiers'] as List? ?? const [])
                .map((raw) => Map<String, dynamic>.from(raw as Map))
                .map((modifier) => modifier['name']?.toString() ?? '')
                .where((name) => name.trim().isNotEmpty)
                .toList();
            return modifiers.join(', ');
          }

          Widget actionButton() {
            if (status == 'queued') {
              return FilledButton.icon(
                onPressed: () => _setKitchenKotStatus(kot, 'preparing'),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Start Preparing'),
              );
            }
            if (status == 'preparing') {
              return FilledButton.icon(
                onPressed: () => _setKitchenKotStatus(kot, 'ready'),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Mark Ready'),
              );
            }
            if (status == 'ready') {
              return FilledButton.icon(
                onPressed: () => _setKitchenKotStatus(kot, 'served'),
                icon: const Icon(Icons.room_service_outlined, size: 16),
                label: const Text('Mark Served'),
              );
            }
            return const SizedBox.shrink();
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isVoid
                              ? scheme.errorContainer
                              : scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isVoid ? 'VOID KOT' : kind.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: isVoid
                                ? scheme.onErrorContainer
                                : scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${kot['kot_number'] ?? 'KOT'} â€¢ '
                          '${kot['order_number'] ?? 'Order'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '$elapsed min',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: elapsed >= 20
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: elapsed >= 20
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      if (tableName.isNotEmpty) tableName,
                      if (orderType.isNotEmpty) orderType.toUpperCase(),
                      if ((kot['guest_count'] as num?) != null)
                        '${kot['guest_count']} guest(s)',
                    ].join(' â€¢ '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.8,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if ((kot['chef_note']?.toString().trim().isNotEmpty ??
                          false) ||
                      (kot['note']?.toString().trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: .45,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        [
                          if (kot['chef_note']?.toString().trim().isNotEmpty ??
                              false)
                            'Chef: ${kot['chef_note']}',
                          if (kot['note']?.toString().trim().isNotEmpty ??
                              false)
                            'KOT: ${kot['note']}',
                        ].join('\n'),
                        style: const TextStyle(fontSize: 9.8),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  ...items.map((item) {
                    final modifiers = modifiersText(item);
                    final itemNote = item['item_note']?.toString().trim() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 42,
                            child: Text(
                              '${item['quantity'] ?? 1} x',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['product_name']?.toString() ??
                                      item['variant_name']?.toString() ??
                                      item['sku']?.toString() ??
                                      'Item',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (modifiers.isNotEmpty)
                                  Text(
                                    '+ $modifiers',
                                    style: TextStyle(
                                      fontSize: 9.3,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                if (itemNote.isNotEmpty)
                                  Text(
                                    itemNote,
                                    style: TextStyle(
                                      fontSize: 9.3,
                                      fontStyle: FontStyle.italic,
                                      color: isVoid
                                          ? scheme.error
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        status.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: scheme.primary,
                        ),
                      ),
                      const Spacer(),
                      actionButton(),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        Widget column(String label, List<Map<String, dynamic>> columnRows) {
          return Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  color: scheme.surfaceContainerHighest.withValues(alpha: .45),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${columnRows.length}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: columnRows.isEmpty
                      ? Center(
                          child: Text(
                            'No ${label.toLowerCase()} KOTs',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(6),
                          itemCount: columnRows.length,
                          itemBuilder: (context, index) =>
                              kotCard(columnRows[index]),
                        ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Text(
                    '${rows.length} live kitchen ticket(s)',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Refresh Kitchen'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 820) {
                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        SizedBox(
                          height: 360,
                          child: column('QUEUED', groups['QUEUED']!),
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: 360,
                          child: column('PREPARING', groups['PREPARING']!),
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          height: 360,
                          child: column('READY', groups['READY']!),
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: column('QUEUED', groups['QUEUED']!)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: column('PREPARING', groups['PREPARING']!),
                      ),
                      const SizedBox(width: 5),
                      Expanded(child: column('READY', groups['READY']!)),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final scheme = Theme.of(context).colorScheme;
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
      length: 4,
      child: Padding(
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
                          'Restaurant Operations',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${_orders.length} live | '
                          '$occupied occupied | $ready ready',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.session.hasPermission('restaurant.manage'))
                    OutlinedButton.icon(
                      onPressed: _addTable,
                      icon: const Icon(
                        Icons.table_restaurant_outlined,
                        size: 15,
                      ),
                      label: const Text('Tables'),
                    ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _newOrder,
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('New Order'),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            _restaurantDashboardStrip(),
            if (_error != null) ...[
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 5),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: const TabBar(
                labelStyle: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
                tabs: [
                  Tab(
                    icon: Icon(Icons.table_restaurant_outlined, size: 15),
                    text: 'Floor',
                  ),
                  Tab(
                    icon: Icon(Icons.receipt_long_outlined, size: 15),
                    text: 'Orders',
                  ),
                  Tab(
                    icon: Icon(Icons.soup_kitchen_outlined, size: 15),
                    text: 'Kitchen',
                  ),
                  Tab(
                    icon: Icon(Icons.groups_2_outlined, size: 15),
                    text: 'Waitlist',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: TabBarView(
                children: [
                  _floorView(),
                  _ordersView(),
                  _kitchenView(),
                  _waitlistView(),
                ],
              ),
            ),
          ],
        ),
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
