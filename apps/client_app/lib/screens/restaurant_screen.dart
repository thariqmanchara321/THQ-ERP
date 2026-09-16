import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../services/customer_service.dart';
import '../services/commercial_pricing_service.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/restaurant_service.dart';
import '../widgets/searchable_select.dart';
import '../widgets/multi_payment_editor.dart';

class RestaurantScreen extends StatefulWidget {
  final ClientSession session;

  const RestaurantScreen({super.key, required this.session});

  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends State<RestaurantScreen> {
  final RestaurantService _restaurant = RestaurantService();
  final CommercialPricingService _commercial = CommercialPricingService();
  final InventoryService _inventory = InventoryService();
  final CustomerService _customers = CustomerService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _waiters = [];
  List<Map<String, dynamic>> _waitlist = [];
  List<Map<String, dynamic>> _kitchenQueue = [];
  List<InventoryProduct> _products = [];
  Timer? _syncTimer;
  List<Customer> _customerRows = [];
  DateTime _restaurantReportFrom = DateTime.now().subtract(
    const Duration(days: 30),
  );
  DateTime _restaurantReportTo = DateTime.now();
  Future<Map<String, dynamic>>? _restaurantAnalyticsFuture;

  String? get _readLocationId =>
      LocationScopeService.currentForRead(widget.session);
  String get _writeLocationId =>
      LocationScopeService.currentForCreate(widget.session);
  String get _operationLocationId => _readLocationId ?? _writeLocationId;
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
    _syncTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshLive(),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final locationId = _operationLocationId;
    final deviceId = _deviceId;
    if (deviceId == null) {
      setState(() {
        _loading = false;
        _error = 'This installation is not registered.';
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
        _inventory.getProducts(tenantId: widget.session.business.id),
        _customers.getCustomers(tenantId: widget.session.business.id),
        _restaurant.waitlist(
          tenantId: widget.session.business.id,
          locationId: locationId,
          deviceId: deviceId,
        ),
        _restaurant.kitchenQueue(
          tenantId: widget.session.business.id,
          locationId: locationId,
          deviceId: deviceId,
        ),
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
        _waitlist = results[5] as List<Map<String, dynamic>>;
        _kitchenQueue = results[6] as List<Map<String, dynamic>>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshLive() async {
    if (!mounted || _loading) return;
    final deviceId = _deviceId;
    if (deviceId == null) return;
    final locationId = _operationLocationId;

    try {
      final results = await Future.wait([
        _restaurant.orders(widget.session.business.id, locationId, deviceId),
        _restaurant.waitlist(
          tenantId: widget.session.business.id,
          locationId: locationId,
          deviceId: deviceId,
        ),
        _restaurant.kitchenQueue(
          tenantId: widget.session.business.id,
          locationId: locationId,
          deviceId: deviceId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0];
        _waitlist = results[1];
        _kitchenQueue = results[2];
      });
    } catch (_) {
      // Keep the live workspace usable if a background refresh fails.
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

  Future<Map<String, dynamic>> _fetchRestaurantAnalytics() {
    final deviceId = _deviceId;
    if (deviceId == null) {
      return Future<Map<String, dynamic>>.error(
        'This installation is not registered.',
      );
    }

    final from = DateTime(
      _restaurantReportFrom.year,
      _restaurantReportFrom.month,
      _restaurantReportFrom.day,
    );
    final to = DateTime(
      _restaurantReportTo.year,
      _restaurantReportTo.month,
      _restaurantReportTo.day,
      23,
      59,
      59,
      999,
    );

    return _restaurant.restaurantAnalytics(
      tenantId: widget.session.business.id,
      locationId: _operationLocationId,
      deviceId: deviceId,
      from: from,
      to: to,
      topLimit: 25,
    );
  }

  void _reloadRestaurantAnalytics() {
    setState(() {
      _restaurantAnalyticsFuture = _fetchRestaurantAnalytics();
    });
  }

  Future<void> _pickRestaurantReportRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: _restaurantReportFrom,
        end: _restaurantReportTo,
      ),
      helpText: 'Restaurant report date range',
    );
    if (picked == null || !mounted) return;

    setState(() {
      _restaurantReportFrom = picked.start;
      _restaurantReportTo = picked.end;
      _restaurantAnalyticsFuture = _fetchRestaurantAnalytics();
    });
  }

  Widget _restaurantAnalyticsView() {
    _restaurantAnalyticsFuture ??= _fetchRestaurantAnalytics();

    Map<String, dynamic> asMap(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

    List<Map<String, dynamic>> asRows(dynamic value) => value is List
        ? value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];

    num number(dynamic value) =>
        value is num ? value : num.tryParse('$value') ?? 0;

    String count(dynamic value) => number(value).toStringAsFixed(0);
    String oneDecimal(dynamic value) => number(value).toStringAsFixed(1);

    Widget metric(IconData icon, String label, String value, String detail) {
      return SizedBox(
        width: 205,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget ranking(
      String title,
      List<Map<String, dynamic>> rows,
      String Function(Map<String, dynamic>) label,
      String Function(Map<String, dynamic>) value, {
      String Function(Map<String, dynamic>)? subtitle,
      double width = 315,
    }) {
      final visible = rows.take(8).toList();

      return SizedBox(
        width: width,
        height: 265,
        child: Card(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No data for this period.',
                          style: TextStyle(fontSize: 10),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = visible[index];
                          final sub = subtitle?.call(row) ?? '';
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: CircleAvatar(
                              radius: 11,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(fontSize: 9),
                              ),
                            ),
                            title: Text(
                              label(row),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: sub.isEmpty
                                ? null
                                : Text(
                                    sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                            trailing: Text(
                              value(row),
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
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

    String reportDate(DateTime value) =>
        '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
          child: Row(
            children: [
              const Icon(Icons.assessment_outlined, size: 18),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Restaurant Reports & Analytics',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickRestaurantReportRange,
                icon: const Icon(Icons.date_range_outlined, size: 16),
                label: Text(
                  '${reportDate(_restaurantReportFrom)} - '
                  '${reportDate(_restaurantReportTo)}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              const SizedBox(width: 5),
              IconButton(
                tooltip: 'Refresh analytics',
                onPressed: _reloadRestaurantAnalytics,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _restaurantAnalyticsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final data = snapshot.data ?? const <String, dynamic>{};
              final sales = asMap(data['sales']);
              final orders = asMap(data['orders']);
              final kitchen = asMap(data['kitchen']);
              final audit = asMap(data['audit']);
              final topItems = asRows(data['top_items']);
              final tables = asRows(data['tables']);
              final waiters = asRows(data['waiters']);
              final orderTypes = asRows(data['order_types']);
              final daily = asRows(data['daily']);

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        metric(
                          Icons.payments_outlined,
                          'Sales',
                          _money(sales['sales']),
                          '${count(sales['bills'])} bills â€¢ '
                              'avg ${_money(sales['avg_ticket'])}',
                        ),
                        metric(
                          Icons.trending_up_outlined,
                          'Gross Profit',
                          _money(sales['gross_profit']),
                          'from billed restaurant sales',
                        ),
                        metric(
                          Icons.groups_outlined,
                          'Dine-in Guests',
                          count(sales['dine_in_guests']),
                          '${_money(sales['sales_per_dine_in_guest'])} / guest',
                        ),
                        metric(
                          Icons.receipt_long_outlined,
                          'Orders Opened',
                          count(orders['opened']),
                          '${count(orders['billed'])} billed â€¢ '
                              '${count(orders['cancelled'])} cancelled',
                        ),
                        metric(
                          Icons.merge_type_outlined,
                          'Merged Orders',
                          count(orders['merged']),
                          'avg cycle ${oneDecimal(orders['avg_order_cycle_minutes'])} min',
                        ),
                        metric(
                          Icons.soup_kitchen_outlined,
                          'Kitchen Tickets',
                          count(kitchen['kots']),
                          '${count(kitchen['void_kots'])} void KOTs',
                        ),
                        metric(
                          Icons.timer_outlined,
                          'Send â†’ Ready',
                          '${oneDecimal(kitchen['avg_send_to_ready_minutes'])} min',
                          '${oneDecimal(kitchen['ready_within_target_pct'])}% within target',
                        ),
                        metric(
                          Icons.hourglass_top_outlined,
                          'Queue â†’ Start',
                          '${oneDecimal(kitchen['avg_queue_to_start_minutes'])} min',
                          'Ready â†’ served ${oneDecimal(kitchen['avg_ready_to_served_minutes'])} min',
                        ),
                        metric(
                          Icons.cancel_outlined,
                          'Cancelled Orders',
                          count(audit['cancelled_orders']),
                          '${count(audit['cancelled_item_lines'])} item lines â€¢ '
                              '${number(audit['cancelled_quantity']).toStringAsFixed(3)} qty',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ranking(
                          'Top Items',
                          topItems,
                          (row) =>
                              row['product_name']?.toString() ??
                              row['sku']?.toString() ??
                              'Item',
                          (row) => _money(row['revenue']),
                          subtitle: (row) =>
                              '${number(row['quantity']).toStringAsFixed(3)} qty â€¢ '
                              'GP ${_money(row['gross_profit'])}',
                        ),
                        ranking(
                          'Table Performance',
                          tables,
                          (row) =>
                              row['table_name']?.toString() ?? 'Unknown table',
                          (row) => _money(row['sales']),
                          subtitle: (row) =>
                              '${count(row['bills'])} bills â€¢ '
                              '${count(row['guests'])} guests',
                        ),
                        ranking(
                          'Waiter Performance',
                          waiters,
                          (row) =>
                              row['waiter_name']?.toString() ?? 'Unassigned',
                          (row) => _money(row['sales']),
                          subtitle: (row) =>
                              '${count(row['bills'])} bills â€¢ '
                              'avg ${_money(row['avg_ticket'])}',
                        ),
                        ranking(
                          'Order Types',
                          orderTypes,
                          (row) => (row['order_type']?.toString() ?? 'order')
                              .replaceAll('_', ' ')
                              .toUpperCase(),
                          (row) => _money(row['sales']),
                          subtitle: (row) =>
                              '${count(row['bills'])} bills â€¢ '
                              'avg ${_money(row['avg_ticket'])}',
                        ),
                        ranking(
                          'Daily Performance',
                          daily.reversed.toList(),
                          (row) => row['date']?.toString() ?? 'Date',
                          (row) => _money(row['sales']),
                          subtitle: (row) =>
                              '${count(row['bills'])} bills â€¢ '
                              'GP ${_money(row['gross_profit'])}',
                          width: 315,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
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

  Widget _restaurantDashboardStrip() {
    final deviceId = _deviceId;
    if (deviceId == null) return const SizedBox.shrink();
    final locationId = _operationLocationId;
    final scheme = Theme.of(context).colorScheme;

    int asInt(dynamic value) =>
        (value as num?)?.toInt() ?? int.tryParse('$value') ?? 0;

    return FutureBuilder<Map<String, dynamic>>(
      future: _restaurant.dashboardSummary(
        tenantId: widget.session.business.id,
        locationId: locationId,
        deviceId: deviceId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const SizedBox(
            height: 54,
            child: Center(child: LinearProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Dashboard unavailable: ${snapshot.error}',
              style: TextStyle(color: scheme.error, fontSize: 12),
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
        final sales = Map<String, dynamic>.from(
          data['sales'] as Map? ?? const {},
        );

        Widget metric(
          IconData icon,
          String title,
          String value,
          String detail,
        ) {
          return SizedBox(
            width: 210,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            detail,
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
                  ],
                ),
              ),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            metric(
              Icons.table_restaurant_outlined,
              'TABLES',
              '${asInt(tables['available'])} free / ${asInt(tables['occupied'])} occupied',
              '${asInt(tables['reserved'])} reserved',
            ),
            metric(
              Icons.receipt_long_outlined,
              'LIVE ORDERS',
              '${asInt(orders['live'])} orders',
              '${asInt(orders['live_guests'])} guests',
            ),
            metric(
              Icons.soup_kitchen_outlined,
              'KITCHEN',
              '${asInt(kitchen['queued'])} queue / ${asInt(kitchen['preparing'])} preparing',
              '${asInt(kitchen['ready'])} ready',
            ),
            metric(
              Icons.groups_outlined,
              'WAITLIST',
              '${asInt(waitlist['waiting'])} waiting',
              '${asInt(waitlist['waiting_guests'])} guests',
            ),
            metric(
              Icons.payments_outlined,
              'TODAY',
              _money(sales['sales_today']),
              '${asInt(sales['bills_today'])} bills',
            ),
          ],
        );
      },
    );
  }

  Future<void> _addTable() async {
    if (!widget.session.hasPermission('restaurant.manage')) {
      _message('restaurant.manage permission required.');
      return;
    }
    final locationId = _writeLocationId;
    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system must be activated before restaurant setup.');
      return;
    }

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
                  deviceId: deviceId,
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
    final locationId = _writeLocationId;
    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system must be activated before restaurant ordering.');
      return;
    }
    if (_products.isEmpty) {
      _message('Add products/menu items first.');
      return;
    }

    String orderType = 'dine_in';
    final activeTables = _tables
        .where(
          (table) =>
              table['active'] != false &&
              table['location_id']?.toString() == locationId,
        )
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
                        child: SearchableSelect<String>(
                          value: customerId,
                          labelText: 'Customer',
                          allowClear: true,
                          hintText: 'Search customer name, ID, phone or GSTIN',
                          prefixIcon: Icons.person_search_outlined,
                          options: _customerRows
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
                          onChanged: (value) =>
                              setLocalState(() => customerId = value),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                      SizedBox(
                        width: 240,
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
                                      waiter['username']?.toString() ??
                                      waiter['user_name']?.toString() ??
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
                      SizedBox(
                        width: 360,
                        child: TextField(
                          controller: orderNote,
                          decoration: const InputDecoration(
                            labelText: 'Order note',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                            guestCount: (int.tryParse(guests.text) ?? 1) < 1
                                ? 1
                                : (int.tryParse(guests.text) ?? 1),
                            waiterUserId: waiterUserId.trim().isEmpty
                                ? null
                                : waiterUserId,
                            orderNote: orderNote.text,
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
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          _message(
                            '${result['order_number']} sent to kitchen.',
                          );
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

  Future<void> _setStatus(Map<String, dynamic> order, String status) async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      _message('This system is not registered.');
      return;
    }
    try {
      await _restaurant.setStatus(
        widget.session.business.id,
        order['id'].toString(),
        deviceId,
        status,
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<List<Map<String, dynamic>>?> _restaurantTrackingAssignments(
    List<Map<String, dynamic>> itemRows,
  ) async {
    final deviceId = _deviceId;
    if (deviceId == null) return null;
    final locationId = _operationLocationId;
    final assignments = <Map<String, dynamic>>[];

    for (final item in itemRows) {
      final variantId = item['variant_id']?.toString();
      if (variantId == null || variantId.isEmpty) continue;

      InventoryProduct? product;
      for (final row in _products) {
        if (row.variantId == variantId) {
          product = row;
          break;
        }
      }
      if (product == null || product.trackingMode != 'serial') continue;

      final quantity =
          (item['quantity'] as num?)?.toDouble() ??
          double.tryParse('${item['quantity']}') ??
          0;
      final cancelled =
          (item['cancelled_quantity'] as num?)?.toDouble() ??
          double.tryParse('${item['cancelled_quantity']}') ??
          0;
      final factor =
          (item['conversion_to_base'] as num?)?.toDouble() ??
          double.tryParse('${item['conversion_to_base']}') ??
          1;

      final requiredDouble =
          ((quantity - cancelled).clamp(0.0, double.infinity) * factor)
              .toDouble();

      if ((requiredDouble - requiredDouble.roundToDouble()).abs() > .000001) {
        _message(
          '${product.productName} is serial tracked and requires whole units.',
        );
        return null;
      }

      final required = requiredDouble.round();
      if (required <= 0) continue;

      final available = await _restaurant.availableSerials(
        tenantId: widget.session.business.id,
        locationId: locationId,
        deviceId: deviceId,
        variantId: variantId,
        limit: 500,
      );

      if (!mounted) return null;

      if (available.length < required) {
        _message(
          '${product.productName} requires $required serial number(s), '
          'but only ${available.length} are available at this store.',
        );
        return null;
      }

      final search = TextEditingController();
      final selected = <String>{};

      final chosen = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            final query = search.text.trim().toLowerCase();
            final visible = available.where((row) {
              final serial = row['serial_number']?.toString() ?? '';
              return query.isEmpty || serial.toLowerCase().contains(query);
            }).toList();

            return AlertDialog(
              title: Text('Select Serial Number${required == 1 ? '' : 's'}'),
              content: SizedBox(
                width: 650,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product!.productName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Select exactly $required available serial '
                      'number${required == 1 ? '' : 's'}.',
                    ),
                    const SizedBox(height: 9),
                    TextField(
                      controller: search,
                      onChanged: (_) => setLocalState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Search serial number',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final serial =
                              visible[index]['serial_number']?.toString() ?? '';
                          final checked = selected.contains(serial);
                          final blocked =
                              !checked && selected.length >= required;
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            onChanged: blocked
                                ? null
                                : (value) {
                                    setLocalState(() {
                                      if (value == true) {
                                        selected.add(serial);
                                      } else {
                                        selected.remove(serial);
                                      }
                                    });
                                  },
                            title: Text(serial),
                          );
                        },
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
                FilledButton(
                  onPressed: selected.length != required
                      ? null
                      : () => Navigator.pop(
                          dialogContext,
                          selected.toList(growable: false),
                        ),
                  child: Text('Use ${selected.length}/$required'),
                ),
              ],
            );
          },
        ),
      );

      search.dispose();
      if (chosen == null) return null;

      assignments.add({
        'order_item_id': item['id']?.toString(),
        'serial_numbers': chosen,
        'batches': const <Map<String, dynamic>>[],
      });
    }

    return assignments;
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
      final itemRows = (detail['items'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final activeItems = <Map<String, dynamic>>[];
      for (final item in itemRows) {
        final quantity =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            0;
        final cancelled =
            (item['cancelled_quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['cancelled_quantity']}') ??
            0;
        final activeQuantity = (quantity - cancelled)
            .clamp(0.0, double.infinity)
            .toDouble();
        if (activeQuantity <= .000001) continue;

        activeItems.add(<String, dynamic>{
          'variant_id': item['variant_id'],
          'quantity': activeQuantity,
          'unit_id': item['unit_id'],
          'unit_price':
              (item['unit_price'] as num?)?.toDouble() ??
              double.tryParse('${item['unit_price']}') ??
              0,
          'discount_amount':
              (item['discount_amount'] as num?)?.toDouble() ??
              double.tryParse('${item['discount_amount']}') ??
              0,
          'tax_rate':
              (item['tax_rate'] as num?)?.toDouble() ??
              double.tryParse('${item['tax_rate']}') ??
              0,
          'item_note': item['item_note']?.toString() ?? '',
        });
      }

      if (activeItems.isEmpty) {
        _message('This restaurant order has no active items to bill.');
        return;
      }

      final initialCustomerId =
          orderMap['customer_id']?.toString() ?? _walkIn?.id;
      if (initialCustomerId == null || initialCustomerId.isEmpty) {
        _message('Select or create a customer before billing.');
        return;
      }

      final choice = await _restaurantCommercialBillingDialog(
        orderNumber:
            orderMap['order_number']?.toString() ??
            order['order_number']?.toString() ??
            'Restaurant Order',
        orderType: orderMap['order_type']?.toString() ?? 'dine_in',
        commercialItems: activeItems,
        initialCustomerId: initialCustomerId,
        initialNote: orderMap['order_note']?.toString() ?? '',
      );
      if (choice == null || !mounted) return;

      final trackingAssignments = await _restaurantTrackingAssignments(
        itemRows,
      );
      if (trackingAssignments == null || !mounted) return;

      if (choice.customerId != initialCustomerId ||
          choice.note.trim() !=
              (orderMap['order_note']?.toString().trim() ?? '')) {
        await _restaurant.updateOrder(
          tenantId: widget.session.business.id,
          orderId: order['id'].toString(),
          deviceId: deviceId,
          customerId: choice.customerId,
          orderNote: choice.note.trim(),
        );
      }

      final sale = await _restaurant.billOrderCommercialV610(
        tenantId: widget.session.business.id,
        orderId: order['id'].toString(),
        deviceId: deviceId,
        customerId: choice.customerId,
        dueDate: choice.dueDate,
        paymentAllocations: choice.paymentAllocations,
        trackingAssignments: trackingAssignments,
        discountType: choice.discountType,
        discountValue: choice.discountValue,
        chargeSelections: choice.chargeSelections,
        notes: choice.note,
      );

      if (!mounted) return;
      _message(
        'Restaurant bill completed â€¢ '
        '${sale['invoice_number'] ?? sale['sale_number'] ?? 'Sales invoice created'}.',
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<_RestaurantCommercialChoice?> _restaurantCommercialBillingDialog({
    required String orderNumber,
    required String orderType,
    required List<Map<String, dynamic>> commercialItems,
    required String initialCustomerId,
    required String initialNote,
  }) async {
    final locationId = _operationLocationId;

    double number(dynamic value, [double fallback = 0]) =>
        (value as num?)?.toDouble() ?? double.tryParse('$value') ?? fallback;

    bool additionalChargesEnabled = false;
    List<Map<String, dynamic>> catalog = const [];

    try {
      additionalChargesEnabled = await _commercial.additionalChargesEnabled(
        tenantId: widget.session.business.id,
      );
      if (additionalChargesEnabled) {
        catalog = await _commercial.chargeCatalog(
          tenantId: widget.session.business.id,
          locationId: locationId,
          activeOnly: true,
        );
      }
    } catch (error) {
      if (mounted) {
        _message('Additional charges unavailable: $error');
      }
    }

    if (!mounted) return null;

    final noteController = TextEditingController(text: initialNote);
    final discountController = TextEditingController(text: '0.00');
    final chargeAmountController = TextEditingController(text: '0.00');

    String customerId = initialCustomerId;
    DateTime dueDate = DateTime.now().add(const Duration(days: 30));
    List<Map<String, dynamic>> allocations = const [];
    String discountType = 'none';
    List<Map<String, dynamic>> chargeSelections = const [];
    String? chargeToAdd = catalog.isNotEmpty
        ? catalog.first['id']?.toString()
        : null;

    if (catalog.isNotEmpty) {
      chargeAmountController.text = number(
        catalog.first['selling_price'],
      ).toStringAsFixed(2);
    }

    Map<String, dynamic>? quote;
    bool quoteBusy = false;
    String? quoteError;

    Future<Map<String, dynamic>> calculateQuote() => _commercial.quote(
      tenantId: widget.session.business.id,
      locationId: locationId,
      items: commercialItems,
      orderType: orderType,
      discountType: discountType,
      discountValue: double.tryParse(discountController.text.trim()) ?? 0.0,
      chargeSelections: chargeSelections,
    );

    try {
      quote = await calculateQuote();
    } catch (error) {
      quoteError = error.toString();
    }

    if (!mounted) {
      noteController.dispose();
      discountController.dispose();
      chargeAmountController.dispose();
      return null;
    }

    final result = await showDialog<_RestaurantCommercialChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refreshQuote() async {
            if (quoteBusy) return;
            setDialogState(() {
              quoteBusy = true;
              quoteError = null;
            });
            try {
              final next = await calculateQuote();
              if (!dialogContext.mounted) return;
              setDialogState(() {
                quote = next;
                allocations = const [];
              });
            } catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() => quoteError = error.toString());
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => quoteBusy = false);
              }
            }
          }

          final totalsRaw = quote?['totals'];
          final totals = totalsRaw is Map
              ? Map<String, dynamic>.from(totalsRaw)
              : const <String, dynamic>{};

          final fallbackSubtotal = commercialItems.fold<double>(
            0,
            (sum, row) =>
                sum +
                number(row['quantity']) * number(row['unit_price']) -
                number(row['discount_amount']),
          );
          final fallbackTax = commercialItems.fold<double>(0, (sum, row) {
            final taxable =
                number(row['quantity']) * number(row['unit_price']) -
                number(row['discount_amount']);
            return sum + taxable * number(row['tax_rate']) / 100.0;
          });
          final fallbackTotal = fallbackSubtotal + fallbackTax;

          final subtotal = number(totals['subtotal'], fallbackSubtotal);
          final discount = number(totals['discount']);
          final tax = number(totals['tax'], fallbackTax);
          final beforeRoundOff = number(
            totals['before_round_off'],
            fallbackTotal,
          );
          final roundOff = number(
            totals['automatic_round_off'],
            double.parse(
              (beforeRoundOff.roundToDouble() - beforeRoundOff).toStringAsFixed(
                2,
              ),
            ),
          );
          final finalTotal = number(
            totals['grand_total'],
            double.parse((beforeRoundOff + roundOff).toStringAsFixed(2)),
          );
          final classifiedCharges = number(quote?['classified_charge_total']);

          Customer? selectedCustomer;
          for (final customer in _customerRows) {
            if (customer.id == customerId) {
              selectedCustomer = customer;
              break;
            }
          }

          bool selectedCharge(String id) =>
              chargeSelections.any((row) => row['charge_id']?.toString() == id);

          void addSelectedCharge() {
            final id = chargeToAdd;
            if (id == null || id.isEmpty || selectedCharge(id)) return;

            final amount =
                double.tryParse(chargeAmountController.text.trim()) ?? -1;
            if (amount < 0) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Enter a valid non-negative additional charge amount.',
                  ),
                ),
              );
              return;
            }

            final next = chargeSelections
                .map((row) => Map<String, dynamic>.from(row))
                .toList();
            next.add(<String, dynamic>{
              'charge_id': id,
              'quantity': 1.0,
              'amount': amount,
            });
            setDialogState(() => chargeSelections = next);
            refreshQuote();
          }

          void removeCharge(String id) {
            setDialogState(() {
              chargeSelections = chargeSelections
                  .where((row) => row['charge_id']?.toString() != id)
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList(growable: false);
            });
            refreshQuote();
          }

          final paidOrTendered = allocations.fold<double>(
            0,
            (sum, row) => sum + number(row['tendered_amount']),
          );
          final creditAmount = allocations
              .where((row) => row['method_code']?.toString() == 'credit')
              .fold<double>(
                0,
                (sum, row) => sum + number(row['tendered_amount']),
              );

          return AlertDialog(
            title: Text('Bill & Pay â€¢ $orderNumber'),
            content: SizedBox(
              width: 900,
              height: 680,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: customerId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Billing customer',
                          ),
                          items: _customerRows
                              .map(
                                (customer) => DropdownMenuItem<String>(
                                  value: customer.id,
                                  child: Text(
                                    customer.isWalkIn
                                        ? '${customer.name} (Walk-in)'
                                        : customer.name,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: quoteBusy
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    customerId = value;
                                    allocations = const [];
                                  });
                                },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            SizedBox(
                              width: 150,
                              child: DropdownButtonFormField<String>(
                                initialValue: discountType,
                                decoration: const InputDecoration(
                                  labelText: 'Discount',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'none',
                                    child: Text('None'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'fixed',
                                    child: Text('Fixed'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'percent',
                                    child: Text('Percent'),
                                  ),
                                ],
                                onChanged: quoteBusy
                                    ? null
                                    : (value) {
                                        if (value == null) return;
                                        setDialogState(() {
                                          discountType = value;
                                          allocations = const [];
                                          if (value == 'none') {
                                            discountController.text = '0.00';
                                          }
                                        });
                                        refreshQuote();
                                      },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: discountController,
                                enabled: !quoteBusy && discountType != 'none',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: discountType == 'percent'
                                      ? 'Discount %'
                                      : 'Discount amount',
                                ),
                                onSubmitted: (_) => refreshQuote(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Recalculate',
                              onPressed: quoteBusy ? null : refreshQuote,
                              icon: const Icon(Icons.calculate_outlined),
                            ),
                          ],
                        ),
                        if (additionalChargesEnabled) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Additional Charges',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (catalog.isEmpty)
                            const Text(
                              'No active classified additional charges are configured.',
                            )
                          else ...[
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: chargeToAdd,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Charge',
                                    ),
                                    items: catalog
                                        .map(
                                          (charge) => DropdownMenuItem<String>(
                                            value: charge['id']?.toString(),
                                            child: Text(
                                              charge['name']?.toString() ??
                                                  charge['code']?.toString() ??
                                                  'Charge',
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: quoteBusy
                                        ? null
                                        : (value) {
                                            Map<String, dynamic>? charge;
                                            for (final row in catalog) {
                                              if (row['id']?.toString() ==
                                                  value) {
                                                charge = row;
                                                break;
                                              }
                                            }
                                            setDialogState(() {
                                              chargeToAdd = value;
                                              chargeAmountController.text =
                                                  charge == null
                                                  ? '0.00'
                                                  : number(
                                                      charge['selling_price'],
                                                    ).toStringAsFixed(2);
                                            });
                                          },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: chargeAmountController,
                                    enabled: !quoteBusy,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Amount',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonalIcon(
                                  onPressed: quoteBusy
                                      ? null
                                      : addSelectedCharge,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: chargeSelections.map((selection) {
                                final id =
                                    selection['charge_id']?.toString() ?? '';
                                Map<String, dynamic>? charge;
                                for (final row in catalog) {
                                  if (row['id']?.toString() == id) {
                                    charge = row;
                                    break;
                                  }
                                }
                                return InputChip(
                                  label: Text(
                                    '${charge?['name'] ?? charge?['code'] ?? 'Charge'} '
                                    '${_money(selection['amount'])}',
                                  ),
                                  onDeleted: quoteBusy
                                      ? null
                                      : () => removeCharge(id),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        if (quoteBusy) const LinearProgressIndicator(),
                        if (quoteError != null)
                          Text(
                            'Quote error: $quoteError',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 24,
                              runSpacing: 8,
                              children: [
                                Text('Subtotal ${_money(subtotal)}'),
                                Text('Discount ${_money(discount)}'),
                                Text(
                                  'Additional charges ${_money(classifiedCharges)}',
                                ),
                                Text('Tax ${_money(tax)}'),
                                Text('Round off ${_money(roundOff)}'),
                                Text(
                                  'TOTAL ${_money(finalTotal)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        MultiPaymentEditor(
                          key: ValueKey(
                            'restaurant-payment-$finalTotal-$customerId-'
                            '${discountType}_${discountController.text}_'
                            '${chargeSelections.length}',
                          ),
                          tenantId: widget.session.business.id,
                          total: finalTotal,
                          customerIsWalkIn: selectedCustomer?.isWalkIn ?? true,
                          customerName: selectedCustomer?.name ?? '',
                          initialAllocations: allocations,
                          onChanged: (value) => allocations = value,
                        ),
                        if (creditAmount > .005) ...[
                          const SizedBox(height: 10),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_outlined),
                            title: const Text('Credit due date'),
                            subtitle: Text(
                              '${dueDate.day.toString().padLeft(2, '0')}-'
                              '${dueDate.month.toString().padLeft(2, '0')}-'
                              '${dueDate.year}',
                            ),
                            trailing: const Icon(Icons.edit_calendar_outlined),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: dialogContext,
                                initialDate: dueDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 3650),
                                ),
                              );
                              if (picked != null && dialogContext.mounted) {
                                setDialogState(() => dueDate = picked);
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: noteController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Invoice / order note',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: quoteBusy
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: quoteBusy || quote == null
                    ? null
                    : () {
                        if (allocations.isEmpty) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Add at least one payment allocation.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (paidOrTendered + .005 < finalTotal) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Payment allocations are short by '
                                '${_money(finalTotal - paidOrTendered)}.',
                              ),
                            ),
                          );
                          return;
                        }

                        if (creditAmount > .005 &&
                            (selectedCustomer?.isWalkIn ?? true)) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Credit requires a named customer.',
                              ),
                            ),
                          );
                          return;
                        }

                        Navigator.pop(
                          dialogContext,
                          _RestaurantCommercialChoice(
                            customerId: customerId,
                            paymentAllocations: allocations,
                            dueDate: creditAmount > .005 ? dueDate : null,
                            note: noteController.text,
                            discountType: discountType,
                            discountValue:
                                double.tryParse(
                                  discountController.text.trim(),
                                ) ??
                                0,
                            chargeSelections: chargeSelections,
                          ),
                        );
                      },
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Create Sales Invoice'),
              ),
            ],
          );
        },
      ),
    );

    noteController.dispose();
    discountController.dispose();
    chargeAmountController.dispose();
    return result;
  }

  Future<void> _showRestaurantAnalytics() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    DateTime from = DateTime.now().subtract(const Duration(days: 30));
    DateTime to = DateTime.now();

    final range = await showDialog<List<DateTime>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Restaurant Reports / Analytics'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('From'),
                  subtitle: Text(
                    '${from.day.toString().padLeft(2, '0')}-'
                    '${from.month.toString().padLeft(2, '0')}-${from.year}',
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: from,
                      firstDate: DateTime(2020),
                      lastDate: to,
                    );
                    if (picked != null) {
                      setLocalState(() => from = picked);
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('To'),
                  subtitle: Text(
                    '${to.day.toString().padLeft(2, '0')}-'
                    '${to.month.toString().padLeft(2, '0')}-${to.year}',
                  ),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: to,
                      firstDate: from,
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setLocalState(() => to = picked);
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
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, [from, to]),
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Run Report'),
            ),
          ],
        ),
      ),
    );

    if (range == null || !mounted) return;

    try {
      final report = await _restaurant.restaurantAnalytics(
        tenantId: widget.session.business.id,
        locationId: _operationLocationId,
        deviceId: deviceId,
        from: range[0],
        to: DateTime(range[1].year, range[1].month, range[1].day, 23, 59, 59),
        topLimit: 15,
      );
      if (!mounted) return;

      String label(String value) {
        final cleaned = value.replaceAll('_', ' ');
        if (cleaned.isEmpty) return value;
        return cleaned
            .split(' ')
            .where((part) => part.isNotEmpty)
            .map(
              (part) =>
                  '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
            )
            .join(' ');
      }

      Widget valueWidget(dynamic value) {
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: map.entries
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text(label(entry.key))),
                        const SizedBox(width: 12),
                        Text(
                          entry.value is num
                              ? entry.value.toString()
                              : '${entry.value}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          );
        }
        if (value is List) {
          if (value.isEmpty) return const Text('No data');
          return Column(
            children: value.take(15).map((raw) {
              if (raw is Map) {
                final map = Map<String, dynamic>.from(raw);
                final title =
                    map['name'] ??
                    map['product_name'] ??
                    map['waiter_name'] ??
                    map['order_type'] ??
                    map['label'] ??
                    'Result';
                final detail = map.entries
                    .where(
                      (entry) => !const {
                        'name',
                        'product_name',
                        'waiter_name',
                        'order_type',
                        'label',
                      }.contains(entry.key),
                    )
                    .map((entry) => '${label(entry.key)}: ${entry.value}')
                    .join(' â€¢ ');
                return ListTile(
                  dense: true,
                  title: Text('$title'),
                  subtitle: detail.isEmpty ? null : Text(detail),
                );
              }
              return ListTile(dense: true, title: Text('$raw'));
            }).toList(),
          );
        }
        return Text('$value');
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restaurant Analytics'),
          content: SizedBox(
            width: 900,
            height: 650,
            child: ListView(
              children: report.entries.map((entry) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label(entry.key),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Divider(),
                        valueWidget(entry.value),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      _message(error.toString());
    }
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
                switch (value) {
                  case 'edit':
                    _editRestaurantOrder(order);
                    break;
                  case 'add_items':
                    _addItemsToRestaurantOrder(order);
                    break;
                  case 'move_table':
                    _transferRestaurantTable(order);
                    break;
                  case 'move_items':
                    _moveRestaurantItems(order);
                    break;
                  case 'split':
                    _splitRestaurantOrderClient(order);
                    break;
                  case 'merge':
                    _mergeRestaurantOrder(order);
                    break;
                  case 'void_item':
                    _voidRestaurantItem(order);
                    break;
                  case 'kot_history':
                    _showRestaurantKotHistory(order);
                    break;
                  case 'bill':
                    _bill(order);
                    break;
                  default:
                    _setStatus(order, value);
                }
              },
              itemBuilder: (_) => [
                if (status != 'billed' && status != 'cancelled')
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit Order Details'),
                  ),
                if (status != 'billed' && status != 'cancelled')
                  const PopupMenuItem(
                    value: 'add_items',
                    child: Text('Add Items / Re-KOT'),
                  ),
                if (status != 'billed' &&
                    status != 'cancelled' &&
                    order['order_type'] == 'dine_in')
                  const PopupMenuItem(
                    value: 'move_table',
                    child: Text('Move Table'),
                  ),
                if (status != 'billed' &&
                    status != 'cancelled' &&
                    order['order_type'] == 'dine_in')
                  const PopupMenuItem(
                    value: 'move_items',
                    child: Text('Move Selected Items'),
                  ),
                if (status != 'billed' &&
                    status != 'cancelled' &&
                    order['order_type'] == 'dine_in')
                  const PopupMenuItem(
                    value: 'split',
                    child: Text('Split to Another Table'),
                  ),
                if (status != 'billed' &&
                    status != 'cancelled' &&
                    order['order_type'] == 'dine_in')
                  const PopupMenuItem(
                    value: 'merge',
                    child: Text('Merge Table / Order'),
                  ),
                if (status != 'billed' && status != 'cancelled')
                  const PopupMenuItem(
                    value: 'void_item',
                    child: Text('Void / Cancel Item'),
                  ),
                const PopupMenuItem(
                  value: 'kot_history',
                  child: Text('KOT History'),
                ),
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
            onLongPress: () => _showRestaurantTableActions(table),
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

  Future<void> _editRestaurantOrder(Map<String, dynamic> order) async {
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
      String? tableId = orderMap['table_id']?.toString();
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

      final availableTables = _tables.where((table) {
        if (table['active'] == false) return false;
        final id = table['id']?.toString() ?? '';
        final liveOrder = _tableOrder(id);
        return liveOrder == null || id == tableId;
      }).toList();

      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: Text(
              'Edit ${orderMap['order_number'] ?? 'Restaurant Order'}',
            ),
            content: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (orderMap['order_type']?.toString() == 'dine_in')
                      DropdownButtonFormField<String?>(
                        initialValue: tableId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Table'),
                        items: availableTables
                            .map(
                              (table) => DropdownMenuItem<String?>(
                                value: table['id']?.toString(),
                                child: Text(
                                  '${table['table_code'] ?? ''} â€¢ ${table['name'] ?? ''}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setLocalState(() => tableId = value),
                      ),
                    if (orderMap['order_type']?.toString() == 'dine_in')
                      const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Customer'),
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
                                        waiter['username']?.toString() ??
                                        'Staff',
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
                    _message('Guest count must be between 1 and 999.');
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
                    if (dialogContext.mounted) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
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

  Future<void> _addItemsToRestaurantOrder(Map<String, dynamic> order) async {
    final deviceId = _deviceId;
    if (deviceId == null || _products.isEmpty) return;

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
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
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
                            order['id'].toString(),
                            deviceId,
                            'Additional items',
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            ThqNotify.showSnackBar(
                              dialogContext,
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: const Text('Add + Send KOT'),
              ),
            ],
          );
        },
      ),
    );

    search.dispose();
    if (added == true) {
      _message('Items added and KOT updated.');
      await _load();
    }
  }

  Future<void> _moveRestaurantItems(Map<String, dynamic> order) async {
    if (order['order_type']?.toString() != 'dine_in') {
      _message('Only dine-in orders can move items between tables.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) return;

    final sourceOrderId = order['id']?.toString();
    if (sourceOrderId == null || sourceOrderId.isEmpty) return;

    final targets = _orders.where((candidate) {
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

    if (targets.isEmpty) {
      _message('No other live dine-in order can receive items.');
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
            final qty =
                (item['quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['quantity']}') ??
                0;
            final cancelled =
                (item['cancelled_quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['cancelled_quantity']}') ??
                0;
            return qty - cancelled > 0.000001;
          })
          .toList();

      if (activeItems.isEmpty) {
        _message('This order has no active items to move.');
        return;
      }

      double activeQty(Map<String, dynamic> item) {
        final qty =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            0;
        final cancelled =
            (item['cancelled_quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['cancelled_quantity']}') ??
            0;
        return (qty - cancelled).clamp(0, double.infinity).toDouble();
      }

      String itemName(Map<String, dynamic> item) =>
          item['product_name']?.toString() ??
          item['variant_name']?.toString() ??
          item['sku']?.toString() ??
          'Item';

      final qtyControllers = <String, TextEditingController>{
        for (final item in activeItems)
          item['id'].toString(): TextEditingController(text: '0'),
      };

      String targetOrderId = targets.first['id'].toString();
      final note = TextEditingController();
      Map<String, dynamic>? moveResult;

      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: const Text('Move Selected Items'),
            content: SizedBox(
              width: 760,
              height: 580,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: targetOrderId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Destination table / order',
                    ),
                    items: targets
                        .map(
                          (target) => DropdownMenuItem<String>(
                            value: target['id'].toString(),
                            child: Text(
                              '${target['table_name'] ?? 'Table'} â€¢ '
                              '${target['order_number'] ?? 'Order'}',
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
                  const SizedBox(height: 10),
                  const Text(
                    'Move quantities',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.separated(
                      itemCount: activeItems.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = activeItems[index];
                        final id = item['id'].toString();
                        final available = activeQty(item);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${itemName(item)} â€¢ available '
                                  '${available.toStringAsFixed(2)}',
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  controller: qtyControllers[id],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Move qty',
                                    isDense: true,
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
                    decoration: const InputDecoration(labelText: 'Move note'),
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
                  var sourceTotal = 0.0;
                  var moveTotal = 0.0;

                  for (final item in activeItems) {
                    final available = activeQty(item);
                    sourceTotal += available;
                    final id = item['id'].toString();
                    final qty =
                        double.tryParse(qtyControllers[id]!.text.trim()) ?? 0;

                    if (qty < 0 || qty > available + 0.000001) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(
                          content: Text(
                            '${itemName(item)} quantity must be between 0 and '
                            '${available.toStringAsFixed(2)}.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (qty > 0.000001) {
                      items.add({'order_item_id': id, 'quantity': qty});
                      moveTotal += qty;
                    }
                  }

                  if (items.isEmpty) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      const SnackBar(
                        content: Text('Choose at least one item quantity.'),
                      ),
                    );
                    return;
                  }

                  if (moveTotal >= sourceTotal - 0.000001) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      const SnackBar(
                        content: Text(
                          'This would empty the source order. Use Merge instead.',
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
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.compare_arrows_rounded),
                label: const Text('Move Items'),
              ),
            ],
          ),
        ),
      );

      for (final controller in qtyControllers.values) {
        controller.dispose();
      }
      note.dispose();

      if (saved == true) {
        try {
          await _restaurant.sendKot(
            widget.session.business.id,
            targetOrderId,
            deviceId,
            'Items moved from ${order['order_number'] ?? 'restaurant order'}',
          );
        } catch (error) {
          _message('Items moved, but destination KOT needs attention: $error');
          await _load();
          return;
        }

        _message(
          'Items moved to '
          '${moveResult?['target_table_name'] ?? 'destination table'} '
          'and destination KOT refreshed.',
        );
        await _load();
      }
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _splitRestaurantOrderClient(Map<String, dynamic> order) async {
    if (order['order_type']?.toString() != 'dine_in') {
      _message('Only dine-in orders can be split.');
      return;
    }

    final sourceGuests =
        (order['guest_count'] as num?)?.toInt() ??
        int.tryParse('${order['guest_count']}') ??
        1;

    if (sourceGuests <= 1) {
      _message('At least 2 guests are required to split an order.');
      return;
    }

    final deviceId = _deviceId;
    if (deviceId == null) return;

    final sourceTableId = order['table_id']?.toString();

    final availableTables = _tables.where((table) {
      final id = table['id']?.toString() ?? '';
      return table['active'] != false &&
          id.isNotEmpty &&
          id != sourceTableId &&
          (table['operational_status']?.toString() ?? 'available') ==
              'available' &&
          _tableOrder(id) == null;
    }).toList();

    if (availableTables.isEmpty) {
      _message('No free destination table is available.');
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
            final qty =
                (item['quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['quantity']}') ??
                0;
            final cancelled =
                (item['cancelled_quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['cancelled_quantity']}') ??
                0;
            return qty - cancelled > 0.000001;
          })
          .toList();

      if (activeItems.isEmpty) {
        _message('This order has no active items to split.');
        return;
      }

      double activeQty(Map<String, dynamic> item) {
        final qty =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            0;
        final cancelled =
            (item['cancelled_quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['cancelled_quantity']}') ??
            0;
        return (qty - cancelled).clamp(0, double.infinity).toDouble();
      }

      String itemName(Map<String, dynamic> item) =>
          item['product_name']?.toString() ??
          item['variant_name']?.toString() ??
          item['sku']?.toString() ??
          'Item';

      final qtyControllers = <String, TextEditingController>{
        for (final item in activeItems)
          item['id'].toString(): TextEditingController(text: '0'),
      };

      String destinationTableId = availableTables.first['id'].toString();
      int movingGuests = 1;
      final note = TextEditingController();
      Map<String, dynamic>? splitResult;

      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            title: Text('Split ${order['order_number'] ?? 'Restaurant Order'}'),
            content: SizedBox(
              width: 780,
              height: 610,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                                    '${table['table_code'] ?? ''} â€¢ '
                                    '${table['name'] ?? ''} â€¢ '
                                    '${table['capacity'] ?? 0} seats',
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
                            for (var i = 1; i < sourceGuests; i++)
                              DropdownMenuItem(value: i, child: Text('$i')),
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
                  const SizedBox(height: 10),
                  const Text(
                    'Items to move to the new table',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.separated(
                      itemCount: activeItems.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = activeItems[index];
                        final id = item['id'].toString();
                        final available = activeQty(item);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${itemName(item)} â€¢ available '
                                  '${available.toStringAsFixed(2)}',
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: TextField(
                                  controller: qtyControllers[id],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Move qty',
                                    isDense: true,
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
                    decoration: const InputDecoration(labelText: 'Split note'),
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
                  );
                  final capacity =
                      (selectedTable['capacity'] as num?)?.toInt() ??
                      int.tryParse('${selectedTable['capacity']}') ??
                      0;

                  if (capacity < movingGuests) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      SnackBar(
                        content: Text(
                          'Destination table has only $capacity seats.',
                        ),
                      ),
                    );
                    return;
                  }

                  final items = <Map<String, dynamic>>[];
                  var sourceTotal = 0.0;
                  var movedTotal = 0.0;

                  for (final item in activeItems) {
                    final available = activeQty(item);
                    sourceTotal += available;
                    final id = item['id'].toString();
                    final qty =
                        double.tryParse(qtyControllers[id]!.text.trim()) ?? 0;

                    if (qty < 0 || qty > available + 0.000001) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(
                          content: Text(
                            '${itemName(item)} quantity must be between 0 and '
                            '${available.toStringAsFixed(2)}.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (qty > 0.000001) {
                      items.add({'order_item_id': id, 'quantity': qty});
                      movedTotal += qty;
                    }
                  }

                  if (items.isEmpty) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      const SnackBar(
                        content: Text('Choose at least one item quantity.'),
                      ),
                    );
                    return;
                  }

                  if (movedTotal >= sourceTotal - 0.000001) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      const SnackBar(
                        content: Text(
                          'A split must leave at least one active item on '
                          'the source table.',
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
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ThqNotify.showSnackBar(
                        dialogContext,
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.call_split_rounded),
                label: const Text('Split to Table'),
              ),
            ],
          ),
        ),
      );

      for (final controller in qtyControllers.values) {
        controller.dispose();
      }
      note.dispose();

      if (saved == true) {
        final targetOrderId = splitResult?['target_order_id']?.toString();
        final targetOrderNumber =
            splitResult?['target_order_number']?.toString() ?? 'New order';
        final targetTableName =
            splitResult?['target_table_name']?.toString() ??
            'destination table';

        if (targetOrderId != null && targetOrderId.isNotEmpty) {
          try {
            await _restaurant.sendKot(
              widget.session.business.id,
              targetOrderId,
              deviceId,
              'Split from ${order['order_number'] ?? 'restaurant order'}',
            );
          } catch (error) {
            _message(
              'Split saved: $targetOrderNumber to $targetTableName, '
              'but KOT needs attention: $error',
            );
            await _load();
            return;
          }
        }

        _message('Split complete: $targetOrderNumber to $targetTableName.');
        await _load();
      }
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _transferRestaurantTable(Map<String, dynamic> order) async {
    if (order['order_type']?.toString() != 'dine_in') {
      _message('Only dine-in orders can move tables.');
      return;
    }
    final deviceId = _deviceId;
    if (deviceId == null) return;

    final currentTableId = order['table_id']?.toString();
    final available = _tables.where((table) {
      final id = table['id']?.toString() ?? '';
      return table['active'] != false &&
          id.isNotEmpty &&
          id != currentTableId &&
          (table['operational_status']?.toString() ?? 'available') ==
              'available' &&
          _tableOrder(id) == null;
    }).toList();

    if (available.isEmpty) {
      _message('No free destination table is available.');
      return;
    }

    String tableId = available.first['id'].toString();
    final note = TextEditingController();

    final moved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Move ${order['order_number'] ?? 'Order'}'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: tableId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Destination table',
                  ),
                  items: available
                      .map(
                        (table) => DropdownMenuItem<String>(
                          value: table['id'].toString(),
                          child: Text(
                            '${table['table_code'] ?? ''} â€¢ ${table['name'] ?? ''}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setLocalState(() => tableId = value);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Transfer note'),
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
                try {
                  await _restaurant.transferTable(
                    tenantId: widget.session.business.id,
                    orderId: order['id'].toString(),
                    deviceId: deviceId,
                    toTableId: tableId,
                    note: note.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      SnackBar(content: Text(error.toString())),
                    );
                  }
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
    if (moved == true) {
      _message('Restaurant order moved to the new table.');
      await _load();
    }
  }

  Future<void> _mergeRestaurantOrder(Map<String, dynamic> target) async {
    if (target['order_type']?.toString() != 'dine_in') {
      _message('Only dine-in orders can be merged.');
      return;
    }
    final deviceId = _deviceId;
    if (deviceId == null) return;

    final targetId = target['id'].toString();
    final candidates = _orders.where((order) {
      final id = order['id']?.toString();
      final status = order['status']?.toString() ?? '';
      return id != null &&
          id != targetId &&
          order['order_type']?.toString() == 'dine_in' &&
          status != 'billed' &&
          status != 'cancelled';
    }).toList();

    if (candidates.isEmpty) {
      _message('No other live dine-in order is available to merge.');
      return;
    }

    String sourceId = candidates.first['id'].toString();
    final note = TextEditingController();

    final merged = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Merge Restaurant Orders'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Keep target: ${target['table_name'] ?? 'Table'} â€¢ '
                    '${target['order_number'] ?? 'Order'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: sourceId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Merge this order into target',
                  ),
                  items: candidates
                      .map(
                        (order) => DropdownMenuItem<String>(
                          value: order['id'].toString(),
                          child: Text(
                            '${order['table_name'] ?? 'Table'} â€¢ '
                            '${order['order_number'] ?? 'Order'} â€¢ '
                            '${_money(order['total'])}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setLocalState(() => sourceId = value);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Merge note'),
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
                try {
                  await _restaurant.mergeOrders(
                    tenantId: widget.session.business.id,
                    targetOrderId: targetId,
                    sourceOrderId: sourceId,
                    deviceId: deviceId,
                    note: note.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                }
              },
              icon: const Icon(Icons.merge_type),
              label: const Text('Merge'),
            ),
          ],
        ),
      ),
    );

    note.dispose();
    if (merged == true) {
      _message('Restaurant orders merged.');
      await _load();
    }
  }

  Future<void> _voidRestaurantItem(Map<String, dynamic> order) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    try {
      final detail = await _restaurant.detail(
        widget.session.business.id,
        order['id'].toString(),
        deviceId,
      );
      if (!mounted) return;

      final items = (detail['items'] as List? ?? const [])
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .where((item) {
            final qty =
                (item['quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['quantity']}') ??
                0;
            final cancelled =
                (item['cancelled_quantity'] as num?)?.toDouble() ??
                double.tryParse('${item['cancelled_quantity']}') ??
                0;
            return qty - cancelled > 0.000001;
          })
          .toList();

      if (items.isEmpty) {
        _message('No active item quantity is available to cancel.');
        return;
      }

      String itemId = items.first['id'].toString();
      final quantity = TextEditingController(text: '1');
      final reason = TextEditingController();

      double remaining(Map<String, dynamic> item) {
        final qty =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            0;
        final cancelled =
            (item['cancelled_quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['cancelled_quantity']}') ??
            0;
        return (qty - cancelled).clamp(0, double.infinity).toDouble();
      }

      final done = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setLocalState) {
            final selected = items.firstWhere(
              (item) => item['id'].toString() == itemId,
            );
            final maxQty = remaining(selected);
            return AlertDialog(
              title: const Text('Void / Cancel Restaurant Item'),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: itemId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Order item',
                      ),
                      items: items
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['id'].toString(),
                              child: Text(
                                '${item['product_name'] ?? item['variant_name'] ?? item['sku'] ?? 'Item'} '
                                'â€¢ Remaining ${remaining(item).toStringAsFixed(2)}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() {
                            itemId = value;
                            final next = items.firstWhere(
                              (item) => item['id'].toString() == itemId,
                            );
                            quantity.text = remaining(
                              next,
                            ).clamp(0, 1).toString();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Cancel quantity',
                        helperText: 'Maximum ${maxQty.toStringAsFixed(2)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reason,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Cancellation / void reason',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final cancelQty =
                        double.tryParse(quantity.text.trim()) ?? 0;
                    if (cancelQty <= 0 || cancelQty > maxQty) {
                      _message(
                        'Cancel quantity must be between 0 and '
                        '${maxQty.toStringAsFixed(2)}.',
                      );
                      return;
                    }
                    if (reason.text.trim().isEmpty) {
                      _message('Cancellation reason is required.');
                      return;
                    }
                    try {
                      await _restaurant.cancelItem(
                        tenantId: widget.session.business.id,
                        orderId: order['id'].toString(),
                        orderItemId: itemId,
                        deviceId: deviceId,
                        cancelQuantity: cancelQty,
                        reason: reason.text,
                      );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (error) {
                      if (dialogContext.mounted) {
                        ThqNotify.showSnackBar(
                          dialogContext,
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.remove_shopping_cart_outlined),
                  label: const Text('Void / Cancel'),
                ),
              ],
            );
          },
        ),
      );

      quantity.dispose();
      reason.dispose();
      if (done == true) {
        _message('Restaurant item cancellation recorded.');
        await _load();
      }
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _showRestaurantKotHistory(Map<String, dynamic> order) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    try {
      final rows = await _restaurant.kotHistory(
        tenantId: widget.session.business.id,
        locationId: _operationLocationId,
        deviceId: deviceId,
        orderId: order['id'].toString(),
        limit: 200,
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'KOT History â€¢ ${order['order_number'] ?? 'Restaurant Order'}',
          ),
          content: SizedBox(
            width: 760,
            height: 520,
            child: rows.isEmpty
                ? const Center(child: Text('No KOT history found.'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(
                          row['kot_number']?.toString() ?? 'KOT',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          [
                            row['status']?.toString(),
                            row['kind']?.toString(),
                            row['created_at']?.toString(),
                            if ((row['note'] ?? '').toString().isNotEmpty)
                              row['note'].toString(),
                          ].whereType<String>().join(' â€¢ '),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _setRestaurantTableStatus(
    Map<String, dynamic> table,
    String status,
  ) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      await _restaurant.setTableOperationalStatus(
        tenantId: widget.session.business.id,
        tableId: table['id'].toString(),
        deviceId: deviceId,
        status: status,
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _reserveRestaurantTable(Map<String, dynamic> table) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    final name = TextEditingController(
      text: table['reservation_name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: table['reservation_phone']?.toString() ?? '',
    );
    final note = TextEditingController(
      text: table['reservation_note']?.toString() ?? '',
    );
    DateTime when =
        DateTime.tryParse(
          table['reservation_at']?.toString() ?? '',
        )?.toLocal() ??
        DateTime.now().add(const Duration(hours: 1));

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            'Reserve ${table['name'] ?? table['table_code'] ?? 'Table'}',
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Guest name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reservation time'),
                  subtitle: Text(when.toString()),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: dialogContext,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 1),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: when,
                    );
                    if (date == null || !dialogContext.mounted) return;
                    final time = await showTimePicker(
                      context: dialogContext,
                      initialTime: TimeOfDay.fromDateTime(when),
                    );
                    if (time == null) return;
                    setLocalState(() {
                      when = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  },
                ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Reservation note',
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
                  _message('Reservation guest name is required.');
                  return;
                }
                try {
                  await _restaurant.reserveTable(
                    tenantId: widget.session.business.id,
                    tableId: table['id'].toString(),
                    deviceId: deviceId,
                    reservationName: name.text,
                    reservationPhone: phone.text,
                    reservationAt: when,
                    reservationNote: note.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                }
              },
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('Reserve'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    phone.dispose();
    note.dispose();
    if (saved == true) await _load();
  }

  Future<void> _clearRestaurantReservation(Map<String, dynamic> table) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      await _restaurant.clearTableReservation(
        tenantId: widget.session.business.id,
        tableId: table['id'].toString(),
        deviceId: deviceId,
      );
      await _load();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _editAdvancedRestaurantTable(Map<String, dynamic> table) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    final code = TextEditingController(
      text: table['table_code']?.toString() ?? '',
    );
    final name = TextEditingController(text: table['name']?.toString() ?? '');
    final capacity = TextEditingController(text: '${table['capacity'] ?? 4}');
    final area = TextEditingController(text: table['area']?.toString() ?? '');
    final floor = TextEditingController(
      text: table['floor_name']?.toString() ?? '',
    );
    final width = TextEditingController(
      text: '${table['width_percent'] ?? 18}',
    );
    final height = TextEditingController(
      text: '${table['height_percent'] ?? 18}',
    );
    final rotation = TextEditingController(
      text: '${table['rotation_degrees'] ?? 0}',
    );
    final layoutNote = TextEditingController(
      text: table['layout_note']?.toString() ?? '',
    );

    String shape = table['shape']?.toString() ?? 'rectangle';
    String status = table['operational_status']?.toString() ?? 'available';
    bool locked = table['layout_locked'] == true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Advanced Restaurant Table'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: code,
                          decoration: const InputDecoration(labelText: 'Code'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: name,
                          decoration: const InputDecoration(labelText: 'Name'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: capacity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Capacity',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: area,
                          decoration: const InputDecoration(labelText: 'Area'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: floor,
                          decoration: const InputDecoration(
                            labelText: 'Floor name',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: shape,
                          decoration: const InputDecoration(labelText: 'Shape'),
                          items: const [
                            DropdownMenuItem(
                              value: 'rectangle',
                              child: Text('Rectangle'),
                            ),
                            DropdownMenuItem(
                              value: 'round',
                              child: Text('Round'),
                            ),
                            DropdownMenuItem(
                              value: 'square',
                              child: Text('Square'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setLocalState(() => shape = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Operational status',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'available',
                              child: Text('Available'),
                            ),
                            DropdownMenuItem(
                              value: 'reserved',
                              child: Text('Reserved'),
                            ),
                            DropdownMenuItem(
                              value: 'cleaning',
                              child: Text('Cleaning'),
                            ),
                            DropdownMenuItem(
                              value: 'out_of_service',
                              child: Text('Out of service'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setLocalState(() => status = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: width,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Width %',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: height,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Height %',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: rotation,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Rotation Â°',
                          ),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: locked,
                    title: const Text('Lock table layout position'),
                    onChanged: (value) => setLocalState(() => locked = value),
                  ),
                  TextField(
                    controller: layoutNote,
                    decoration: const InputDecoration(labelText: 'Layout note'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await _restaurant.saveAdvancedTable(
                    tenantId: widget.session.business.id,
                    tableId: table['id'].toString(),
                    locationId: _operationLocationId,
                    deviceId: deviceId,
                    code: code.text,
                    name: name.text,
                    capacity: int.tryParse(capacity.text) ?? 4,
                    area: area.text,
                    floorName: floor.text,
                    operationalStatus: status,
                    shape: shape,
                    positionX: (table['position_x'] as num?)?.toDouble(),
                    positionY: (table['position_y'] as num?)?.toDouble(),
                    widthPercent: double.tryParse(width.text) ?? 18,
                    heightPercent: double.tryParse(height.text) ?? 18,
                    rotationDegrees: double.tryParse(rotation.text) ?? 0,
                    layoutLocked: locked,
                    layoutNote: layoutNote.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ThqNotify.showSnackBar(
                      dialogContext,
                      SnackBar(content: Text(error.toString())),
                    );
                  }
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    code.dispose();
    name.dispose();
    capacity.dispose();
    area.dispose();
    floor.dispose();
    width.dispose();
    height.dispose();
    rotation.dispose();
    layoutNote.dispose();

    if (saved == true) await _load();
  }

  Future<void> _showRestaurantTableActions(Map<String, dynamic> table) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Advanced Table Settings'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editAdvancedRestaurantTable(table);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Reserve Table'),
              onTap: () {
                Navigator.pop(sheetContext);
                _reserveRestaurantTable(table);
              },
            ),
            if ((table['reservation_name'] ?? '').toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: const Text('Clear Reservation'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _clearRestaurantReservation(table);
                },
              ),
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
        ),
      ),
    );
  }

  Future<void> _showRestaurantTableManager() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Restaurant Table Manager'),
          content: SizedBox(
            width: 820,
            height: 560,
            child: _tables.isEmpty
                ? const Center(child: Text('No tables configured.'))
                : ListView.separated(
                    itemCount: _tables.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final table = _tables[index];
                      final active = table['active'] != false;
                      return ListTile(
                        leading: Icon(
                          active
                              ? Icons.table_restaurant_outlined
                              : Icons.block_outlined,
                        ),
                        title: Text(
                          '${table['table_code'] ?? ''} â€¢ ${table['name'] ?? ''}',
                        ),
                        subtitle: Text(
                          '${table['floor_name'] ?? table['area'] ?? 'Main'} â€¢ '
                          '${table['capacity'] ?? 0} seats â€¢ '
                          '${table['operational_status'] ?? 'available'}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () async {
                                Navigator.pop(dialogContext);
                                await _editAdvancedRestaurantTable(table);
                                if (mounted) {
                                  await _showRestaurantTableManager();
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Duplicate',
                              onPressed: () async {
                                final deviceId = _deviceId;
                                if (deviceId == null) return;
                                try {
                                  await _restaurant.duplicateTable(
                                    tenantId: widget.session.business.id,
                                    tableId: table['id'].toString(),
                                    deviceId: deviceId,
                                    newCode:
                                        '${table['table_code'] ?? 'T'}-COPY',
                                    newName: '${table['name'] ?? 'Table'} Copy',
                                  );
                                  await _load();
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                  if (mounted) {
                                    await _showRestaurantTableManager();
                                  }
                                } catch (error) {
                                  _message(error.toString());
                                }
                              },
                              icon: const Icon(Icons.copy_outlined),
                            ),
                            IconButton(
                              tooltip: active ? 'Deactivate' : 'Reactivate',
                              onPressed: () async {
                                final deviceId = _deviceId;
                                if (deviceId == null) return;
                                try {
                                  if (active) {
                                    await _restaurant.deactivateTable(
                                      tenantId: widget.session.business.id,
                                      tableId: table['id'].toString(),
                                      deviceId: deviceId,
                                      reason:
                                          'Deactivated from Client table manager',
                                    );
                                  } else {
                                    await _restaurant.reactivateTable(
                                      tenantId: widget.session.business.id,
                                      tableId: table['id'].toString(),
                                      deviceId: deviceId,
                                    );
                                  }
                                  await _load();
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                  if (mounted) {
                                    await _showRestaurantTableManager();
                                  }
                                } catch (error) {
                                  _message(error.toString());
                                }
                              },
                              icon: Icon(
                                active
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _addTable();
                if (mounted) await _showRestaurantTableManager();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Table'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setKotStatus(Map<String, dynamic> kot, String status) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      await _restaurant.setKotStatus(
        tenantId: widget.session.business.id,
        kotId: kot['id'].toString(),
        deviceId: deviceId,
        status: status,
      );
      await _refreshLive();
    } catch (error) {
      _message(error.toString());
    }
  }

  Widget _kitchenView() {
    final groups = <String, List<Map<String, dynamic>>>{
      'QUEUE': _kitchenQueue
          .where(
            (row) => const {
              'queued',
              'sent_to_kitchen',
              'open',
            }.contains((row['status'] ?? '').toString()),
          )
          .toList(),
      'PREPARING': _kitchenQueue
          .where((row) => row['status']?.toString() == 'preparing')
          .toList(),
      'READY': _kitchenQueue
          .where((row) => row['status']?.toString() == 'ready')
          .toList(),
    };

    Widget kotCard(Map<String, dynamic> kot) {
      final status = (kot['status'] ?? 'queued').toString();
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${kot['kot_number'] ?? 'KOT'} â€¢ ${kot['order_number'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Chip(label: Text(status.replaceAll('_', ' ').toUpperCase())),
                ],
              ),
              Text(
                '${kot['table_name'] ?? kot['order_type'] ?? ''}'
                '${kot['waiter_name'] == null ? '' : ' â€¢ ${kot['waiter_name']}'}',
              ),
              if ((kot['note'] ?? '').toString().trim().isNotEmpty)
                Text(
                  'Note: ${kot['note']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  if (const {
                    'queued',
                    'sent_to_kitchen',
                    'open',
                  }.contains(status))
                    FilledButton.tonal(
                      onPressed: () => _setKotStatus(kot, 'preparing'),
                      child: const Text('Start'),
                    ),
                  if (status == 'preparing')
                    FilledButton.tonal(
                      onPressed: () => _setKotStatus(kot, 'ready'),
                      child: const Text('Ready'),
                    ),
                  if (status == 'ready')
                    FilledButton.tonal(
                      onPressed: () => _setKotStatus(kot, 'served'),
                      child: const Text('Served'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

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
                                  'No ${entry.key.toLowerCase()} KOTs',
                                ),
                              )
                            : ListView(
                                children: entry.value.map(kotCard).toList(),
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
            children: [
              for (final column in columns)
                SizedBox(height: 330, child: column),
            ],
          );
        }
        return Row(
          children: columns.map((column) => Expanded(child: column)).toList(),
        );
      },
    );
  }

  Future<void> _addWaitlistGuest() async {
    final deviceId = _deviceId;
    if (deviceId == null) return;

    final guestName = TextEditingController();
    final phone = TextEditingController();
    final guestCount = TextEditingController(text: '2');
    final waitMinutes = TextEditingController(text: '15');
    final area = TextEditingController();
    final note = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Waitlist Guest'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: guestName,
                decoration: const InputDecoration(labelText: 'Guest name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
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
                        labelText: 'Estimated wait (min)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: area,
                decoration: const InputDecoration(
                  labelText: 'Preferred area (optional)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (guestName.text.trim().isEmpty) {
                _message('Guest name is required.');
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _restaurant.addWaitlistGuest(
          tenantId: widget.session.business.id,
          locationId: _operationLocationId,
          deviceId: deviceId,
          guestName: guestName.text,
          phone: phone.text,
          guestCount: int.tryParse(guestCount.text) ?? 1,
          estimatedWaitMinutes: int.tryParse(waitMinutes.text) ?? 15,
          preferredArea: area.text,
          note: note.text,
        );
        await _refreshLive();
      } catch (error) {
        _message(error.toString());
      }
    }

    guestName.dispose();
    phone.dispose();
    guestCount.dispose();
    waitMinutes.dispose();
    area.dispose();
    note.dispose();
  }

  Future<void> _setWaitlistStatus(
    Map<String, dynamic> row,
    String status, {
    String? tableId,
  }) async {
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      await _restaurant.setWaitlistStatus(
        tenantId: widget.session.business.id,
        waitlistId: row['id'].toString(),
        deviceId: deviceId,
        status: status,
        tableId: tableId,
      );
      await _refreshLive();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _seatWaitlistGuest(Map<String, dynamic> row) async {
    final availableTables = _tables.where((table) {
      final id = table['id']?.toString() ?? '';
      final operational = (table['operational_status'] ?? 'available')
          .toString();
      return table['active'] != false &&
          _tableOrder(id) == null &&
          operational != 'out_of_service' &&
          operational != 'cleaning';
    }).toList();

    if (availableTables.isEmpty) {
      _message('No available table is ready for seating.');
      return;
    }

    String tableId = availableTables.first['id'].toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Seat ${row['guest_name'] ?? 'Guest'}'),
          content: DropdownButtonFormField<String>(
            initialValue: tableId,
            decoration: const InputDecoration(labelText: 'Table'),
            items: availableTables
                .map(
                  (table) => DropdownMenuItem<String>(
                    value: table['id'].toString(),
                    child: Text(
                      '${table['table_code'] ?? ''} â€¢ ${table['name'] ?? ''}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setLocalState(() => tableId = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Seat'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _setWaitlistStatus(row, 'seated', tableId: tableId);
    }
  }

  Widget _waitlistView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_waitlist.length} live waitlist entries',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: _addWaitlistGuest,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add Guest'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _waitlist.isEmpty
              ? const Center(child: Text('No guests are currently waiting.'))
              : RefreshIndicator(
                  onRefresh: _refreshLive,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _waitlist.length,
                    itemBuilder: (context, index) {
                      final row = _waitlist[index];
                      final status = (row['status'] ?? 'waiting').toString();
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${row['guest_count'] ?? 1}'),
                          ),
                          title: Text(row['guest_name']?.toString() ?? 'Guest'),
                          subtitle: Text(
                            [
                              if ((row['phone'] ?? '').toString().isNotEmpty)
                                row['phone'].toString(),
                              '${row['estimated_wait_minutes'] ?? 0} min',
                              if ((row['preferred_area'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                row['preferred_area'].toString(),
                            ].join(' â€¢ '),
                          ),
                          trailing: Wrap(
                            spacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                label: Text(
                                  status.replaceAll('_', ' ').toUpperCase(),
                                ),
                              ),
                              if (status == 'waiting')
                                IconButton(
                                  tooltip: 'Mark notified',
                                  onPressed: () =>
                                      _setWaitlistStatus(row, 'notified'),
                                  icon: const Icon(Icons.notifications_active),
                                ),
                              if (status == 'waiting' || status == 'notified')
                                IconButton(
                                  tooltip: 'Seat guest',
                                  onPressed: () => _seatWaitlistGuest(row),
                                  icon: const Icon(Icons.event_seat_outlined),
                                ),
                              if (status == 'waiting' || status == 'notified')
                                IconButton(
                                  tooltip: 'Cancel waitlist entry',
                                  onPressed: () =>
                                      _setWaitlistStatus(row, 'cancelled'),
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
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
      length: 5,
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
                    onPressed: _showRestaurantTableManager,
                    icon: const Icon(Icons.table_restaurant_outlined),
                    label: const Text('Tables'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showRestaurantAnalytics,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Reports'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: _restaurantDashboardStrip(),
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
              Tab(icon: Icon(Icons.groups_outlined), text: 'Waitlist'),
              Tab(
                icon: Icon(Icons.assessment_outlined, size: 15),
                text: 'Reports',
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _floorView(),
                _ordersView(),
                _kitchenView(),
                _waitlistView(),
                _restaurantAnalyticsView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantCommercialChoice {
  final String customerId;
  final List<Map<String, dynamic>> paymentAllocations;
  final DateTime? dueDate;
  final String note;
  final String discountType;
  final double discountValue;
  final List<Map<String, dynamic>> chargeSelections;

  const _RestaurantCommercialChoice({
    required this.customerId,
    required this.paymentAllocations,
    required this.dueDate,
    required this.note,
    required this.discountType,
    required this.discountValue,
    required this.chargeSelections,
  });
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
