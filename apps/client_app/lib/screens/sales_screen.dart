import 'dart:async';

import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
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
import '../services/tracking_service.dart';
import '../services/transaction_print_service.dart';
import 'sale_detail_screen.dart';
import '../widgets/searchable_select.dart';
import '../widgets/multi_payment_editor.dart';

class SalesScreen extends StatefulWidget {
  final ClientSession session;
  final bool startInCreate;
  final bool historyOnly;
  final String? titleOverride;

  const SalesScreen({
    super.key,
    required this.session,
    this.startInCreate = false,
    this.historyOnly = false,
    this.titleOverride,
  });

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final SalesService _service = SalesService();

  late Future<List<Sale>> _salesFuture;

  bool _creating = false;
  int _saleGeneration = 0;

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
      ThqNotify.showSnackBar(
        context,
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
      if (created) {
        _load();
        _saleGeneration++;
        _creating =
            widget.startInCreate &&
            _canManage &&
            LocationScopeService.selectedLocationId.value != null;
      } else {
        _creating = false;
      }
    });
    if (created) {
      ThqNotify.success(context, 'Sale completed');
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
        key: ValueKey(_saleGeneration),
        session: widget.session,
        locationId: LocationScopeService.currentForCreate(widget.session),
        embedded: true,
        onFinished: _finishNewSale,
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 26,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.titleOverride ??
                            (widget.historyOnly ? 'Sales Details' : 'Sales'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Invoices, customer balances and payment status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh sales',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
                if (_canManage && !widget.historyOnly) ...[
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: _newSale,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('New Sale'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
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
                        const Icon(Icons.error_outline, size: 42),
                        const SizedBox(height: 10),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final sales = snapshot.data ?? const <Sale>[];
                if (sales.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.point_of_sale_outlined, size: 52),
                        const SizedBox(height: 8),
                        const Text(
                          'No sales yet',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_canManage && !widget.historyOnly) ...[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _newSale,
                            icon: const Icon(Icons.add),
                            label: const Text('Create Sale'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 900;
                    final veryCompact = constraints.maxWidth < 720;
                    return Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            color: scheme.surfaceContainerHighest,
                            child: _salesRegisterHeader(
                              compact: compact,
                              veryCompact: veryCompact,
                            ),
                          ),
                          Divider(height: 1, color: scheme.outlineVariant),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _refresh,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemCount: sales.length,
                                itemBuilder: (context, index) =>
                                    _salesRegisterRow(
                                      sales[index],
                                      compact: compact,
                                      veryCompact: veryCompact,
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesRegisterHeader({
    required bool compact,
    required bool veryCompact,
  }) {
    Widget cell(String value, int flex, {TextAlign align = TextAlign.left}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              value,
              textAlign: align,
              maxLines: 1,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        );

    return Row(
      children: [
        cell('Invoice', 2),
        if (!veryCompact) cell('Date', 2),
        cell('Customer', 4),
        cell('Total', 2, align: TextAlign.right),
        cell('Balance', 2, align: TextAlign.right),
        if (!compact) cell('Gross Profit', 2, align: TextAlign.right),
        const SizedBox(width: 12),
        const SizedBox(
          width: 104,
          child: Text(
            'Status',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 28),
      ],
    );
  }

  Widget _salesRegisterRow(
    Sale sale, {
    required bool compact,
    required bool veryCompact,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(
      Widget child,
      int flex, {
      Alignment alignment = Alignment.centerLeft,
    }) => Expanded(
      flex: flex,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: child,
        ),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSale(sale),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              cell(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (veryCompact)
                      Text(
                        _date(sale.saleDate),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                2,
              ),
              if (!veryCompact)
                cell(
                  Text(
                    _date(sale.saleDate),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  2,
                ),
              cell(
                Text(
                  sale.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                4,
              ),
              cell(
                Text(
                  _money(sale.grandTotal),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                2,
                alignment: Alignment.centerRight,
              ),
              cell(
                Text(
                  _money(sale.balanceDue),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: sale.balanceDue > 0.005
                        ? scheme.error
                        : scheme.onSurface,
                  ),
                ),
                2,
                alignment: Alignment.centerRight,
              ),
              if (!compact)
                cell(
                  Text(
                    _money(sale.grossProfit),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  2,
                  alignment: Alignment.centerRight,
                ),
              const SizedBox(width: 12),
              SizedBox(
                width: 104,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _SalePaymentBadge(status: sale.paymentStatus),
                ),
              ),
              const SizedBox(
                width: 28,
                child: Icon(Icons.chevron_right, size: 18),
              ),
            ],
          ),
        ),
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
  final TransactionPrintService _printService = TransactionPrintService();

  final TextEditingController _notesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String? _error;

  List<Customer> _customers = [];

  List<InventoryProduct> _products = [];
  Map<String, Customer> _customerById = const {};
  List<SearchableSelectOption<String>> _customerOptions = const [];

  String? _customerId;

  DateTime _saleDate = DateTime.now();

  DateTime? _dueDate;

  List<Map<String, dynamic>> _paymentAllocations = const [];

  final List<_SaleLine> _lines = [];

  Customer? get _selectedCustomer {
    final id = _customerId;
    return id == null ? null : _customerById[id];
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

      final customerById = <String, Customer>{
        for (final customer in activeCustomers) customer.id: customer,
      };
      final customerOptions = activeCustomers
          .map(
            (entry) => SearchableSelectOption<String>(
              value: entry.id,
              label: entry.isWalkIn
                  ? '${entry.name} \u2014 Counter Sale'
                  : entry.name,
              subtitle: [entry.publicId, entry.phone, entry.taxNumber]
                  .where((value) => value?.trim().isNotEmpty == true)
                  .join(' \u2022 '),
              searchText:
                  '${entry.name} ${entry.publicId} ${entry.phone ?? ''} '
                  '${entry.email ?? ''} ${entry.taxNumber ?? ''}',
            ),
          )
          .toList(growable: false);

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
        _customerById = Map<String, Customer>.unmodifiable(customerById);
        _customerOptions = List<SearchableSelectOption<String>>.unmodifiable(
          customerOptions,
        );

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

  // ignore: unused_element
  double _number(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  double get _subtotal =>
      _lines.fold(0, (total, line) => total + line.subtotal);

  double get _discount =>
      _lines.fold(0, (total, line) => total + line.discount);

  double get _tax => _lines.fold(0, (total, line) => total + line.tax);

  double get _beforeRoundOff => _subtotal - _discount + _tax;

  double get _roundOff {
    final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;
    return delta.abs() < 0.000001 ? 0 : delta;
  }

  double get _grandTotal => _beforeRoundOff + _roundOff;

  double get _allocatedTotal {
    var remaining = _grandTotal;
    var allocated = 0.0;
    for (final allocation in _paymentAllocations) {
      if (remaining <= 0) break;
      final amount =
          (allocation['tendered_amount'] as num?)?.toDouble() ??
          double.tryParse('${allocation['tendered_amount']}') ??
          0;
      if (amount <= 0) continue;
      final used = amount > remaining ? remaining : amount;
      allocated += used;
      remaining -= used;
    }
    return allocated;
  }

  double get _settledPayment {
    var remaining = _grandTotal;
    var settled = 0.0;
    for (final allocation in _paymentAllocations) {
      if (remaining <= 0) break;
      final amount =
          (allocation['tendered_amount'] as num?)?.toDouble() ??
          double.tryParse('${allocation['tendered_amount']}') ??
          0;
      if (amount <= 0) continue;
      final used = amount > remaining ? remaining : amount;
      if (allocation['method_code']?.toString() != 'credit') {
        settled += used;
      }
      remaining -= used;
    }
    return settled;
  }

  bool get _hasCredit => _paymentAllocations.any(
    (entry) =>
        entry['method_code']?.toString() == 'credit' &&
        (((entry['tendered_amount'] as num?)?.toDouble() ??
                double.tryParse('${entry['tendered_amount']}') ??
                0) >
            0),
  );

  double get _balanceDue =>
      (_grandTotal - _settledPayment).clamp(0.0, _grandTotal);

  bool get _requiresDueDate =>
      _selectedCustomer?.isWalkIn == false &&
      _paymentAllocations.isNotEmpty &&
      _balanceDue > 0.005;

  double get _taxableAmount => _subtotal - _discount;

  String get _placeOfSupply {
    final value = _selectedCustomer?.state?.trim() ?? '';
    return value.isEmpty ? 'Not configured' : value;
  }

  bool? get _interstatePreview {
    final origin =
        widget.session.settings['business.state']
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    final destination = _selectedCustomer?.state?.trim().toLowerCase() ?? '';
    if (origin.isEmpty || destination.isEmpty) return null;
    return origin != destination;
  }

  double get _cgstPreview => _interstatePreview == false ? _tax / 2 : 0;
  double get _sgstPreview => _interstatePreview == false ? _tax / 2 : 0;
  double get _igstPreview => _interstatePreview == true ? _tax : 0;

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
    return line.copyWith(
      unitPrice: price.unitPrice,
      pricingSource: price.sourceLabel,
    );
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
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('Could not refresh customer pricing: $error')),
      );
    }
  }

  Future<void> _addLine() async {
    final usedVariants = _lines.map((line) => line.product.variantId).toSet();
    final available = _products
        .where((product) => !usedVariants.contains(product.variantId))
        .toList();

    if (available.isEmpty) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('No more products available to add.')),
      );

      return;
    }

    final line = await showDialog<_SaleLine>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddSaleItemDialog(
        products: available,
        tenantId: widget.session.business.id,
        locationId: widget.locationId,
      ),
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
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('Could not resolve selling price: $error')),
      );
    }
  }

  Future<void> _addCharge() async {
    final usedVariants = _lines.map((line) => line.product.variantId).toSet();
    final available = _products
        .where(
          (product) =>
              product.itemType != 'stock' &&
              !usedVariants.contains(product.variantId),
        )
        .toList();

    if (available.isEmpty) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(
          content: Text(
            'No Service products are available for Add Charge. Create a product '
            'with item type Service, then configure its SAC/GST profile under '
            'GST & Compliance > Products.',
          ),
        ),
      );
      return;
    }

    final line = await showDialog<_SaleLine>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddSaleItemDialog(
        products: available,
        tenantId: widget.session.business.id,
        locationId: widget.locationId,
      ),
    );

    if (line == null || !mounted) {
      return;
    }

    try {
      final pricedLine = await _resolvedLine(line);
      if (!mounted) {
        return;
      }

      setState(() {
        _lines.add(pricedLine);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('Could not add service charge: $error')),
      );
    }
  }

  String _friendlyPostError(Object error) {
    final message = error.toString();
    final productMatch = RegExp(
      r'Product\s+([^\s\]]+)\s+GST profile requires review',
      caseSensitive: false,
    ).firstMatch(message);
    if (productMatch != null) {
      return 'Cannot confirm this GST sale. Review and validate the GST profile '
          'for product ${productMatch.group(1)}, then retry this unchanged invoice.';
    }
    if (message.contains('GST Sale is not compliance-ready')) {
      return 'Cannot confirm this GST sale because one or more GST profiles are '
          'not compliance-ready. Review them in GST & Compliance, then retry '
          'this unchanged invoice.';
    }
    return message;
  }

  Future<void> _post({bool printAfter = false}) async {
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

    if (_paymentAllocations.isEmpty) {
      setState(() {
        _error = 'Allocate the invoice total to at least one payment method.';
      });
      return;
    }
    if ((_grandTotal - _allocatedTotal).abs() > 0.005) {
      setState(() {
        _error = 'Payment allocations must cover the invoice total.';
      });
      return;
    }
    if (customer.isWalkIn && _hasCredit) {
      setState(() {
        _error = 'Credit requires a named customer.';
      });
      return;
    }
    if (customer.isWalkIn && _balanceDue > 0.005) {
      setState(() {
        _error = 'Walk-in Customer sales must be fully settled.';
      });
      return;
    }
    if (_requiresDueDate && _dueDate == null) {
      setState(() {
        _error =
            'Choose a due date because this invoice has an unpaid / credit balance.';
      });
      return;
    }

    // Keep the backend writer contract unchanged. For walk-in or fully
    // settled sales the Due Date UI is hidden, but the persisted technical
    // due date remains the sale date.
    if (!_requiresDueDate) {
      _dueDate = _saleDate;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await _salesService.createSale(
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

        paymentAllocations: _paymentAllocations,

        notes: _notesController.text,
        locationId: widget.locationId,
      );

      String? printWarning;
      if (printAfter) {
        try {
          final rawId =
              result['sale_id'] ??
              result['id'] ??
              (result['result'] is Map
                  ? (result['result'] as Map)['sale_id']
                  : null) ??
              (result['result'] is Map
                  ? (result['result'] as Map)['id']
                  : null);
          final saleId = rawId?.toString() ?? '';
          if (saleId.isEmpty) {
            throw StateError(
              'Sale is confirmed, but the response did not contain a sale ID.',
            );
          }
          final detail = await _salesService.getSaleDetail(
            tenantId: widget.session.business.id,
            saleId: saleId,
          );
          await _printService.printSale(session: widget.session, sale: detail);
        } catch (error) {
          printWarning =
              'Sale confirmed successfully, but printing failed: $error';
        }
      }

      if (!mounted) {
        return;
      }

      if (printWarning != null) {
        ThqNotify.showSnackBar(context, SnackBar(content: Text(printWarning)));
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
        _error = _friendlyPostError(error);
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
    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _customers.isEmpty
        ? const Center(child: Text('No active customers available.'))
        : LayoutBuilder(
            builder: (context, constraints) {
              final desktopWorkspace =
                  constraints.maxWidth >= 1080 && constraints.maxHeight >= 650;

              if (desktopWorkspace) {
                return _desktopSaleWorkspace(constraints);
              }

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth < 720 ? 10 : 18,
                  12,
                  constraints.maxWidth < 720 ? 10 : 18,
                  24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Column(
                      children: [
                        _documentHeader(),
                        const SizedBox(height: 12),
                        _customerCard(),
                        const SizedBox(height: 12),
                        _itemsCard(),
                        const SizedBox(height: 12),
                        _paymentCard(),
                      ],
                    ),
                  ),
                ),
              );
            },
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

  Widget _desktopSaleWorkspace(BoxConstraints constraints) {
    final summaryWidth = constraints.maxWidth >= 1320 ? 372.0 : 344.0;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          _desktopDocumentBar(),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _desktopInvoicePanel(),
                      const SizedBox(height: 8),
                      Expanded(child: _desktopItemsPanel()),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: summaryWidth, child: _desktopSettlementPanel()),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _desktopActionBar(),
        ],
      ),
    );
  }

  Widget _desktopDocumentBar() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          if (widget.embedded) ...[
            IconButton(
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              onPressed: _saving ? null : () => widget.onFinished?.call(false),
              icon: const Icon(Icons.arrow_back, size: 19),
            ),
            const SizedBox(width: 4),
          ],
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 19,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New Sales Invoice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Fast entry | GST-aware | inventory linked',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'INVOICE NO.',
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
                ),
                Text(
                  'AUTO ON CONFIRM',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopInvoicePanel() {
    final customer = _selectedCustomer;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 5,
                child: SearchableSelect<String>(
                  value: _customerId,
                  labelText: 'Customer',
                  isRequired: true,
                  enabled: !_saving,
                  hintText: 'Search name, ID, phone or GSTIN',
                  prefixIcon: Icons.person_search_outlined,
                  options: _customerOptions,
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
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _desktopDateButton(
                  icon: Icons.calendar_month_outlined,
                  label: 'Invoice Date',
                  value: _date(_saleDate),
                  onPressed: _saving ? null : _chooseSaleDate,
                ),
              ),
              if (_requiresDueDate) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _desktopDateButton(
                    icon: Icons.event_outlined,
                    label: 'Due Date',
                    value: _dueDate == null ? 'Required' : _date(_dueDate!),
                    onPressed: _saving ? null : _chooseDueDate,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _desktopInfoPill(
                  icon: Icons.receipt_long_outlined,
                  label: 'GSTIN',
                  value: customer?.taxNumber?.trim().isNotEmpty == true
                      ? customer!.taxNumber!
                      : 'Not registered',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _desktopInfoPill(
                  icon: Icons.place_outlined,
                  label: 'Place of Supply',
                  value: _placeOfSupply,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _desktopInfoPill(
                  icon: customer?.isWalkIn == true
                      ? Icons.point_of_sale_outlined
                      : Icons.account_circle_outlined,
                  label: 'Customer Type',
                  value: customer?.isWalkIn == true
                      ? 'Walk-in | full payment required'
                      : 'Named customer',
                  warning: customer?.isWalkIn == true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _desktopDateButton({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 9.5)),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopInfoPill({
    required IconData icon,
    required String label,
    required String value,
    bool warning = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = warning ? scheme.tertiary : scheme.onSurfaceVariant;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: warning
            ? scheme.tertiaryContainer.withValues(alpha: .55)
            : scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopItemsPanel() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 17),
                  const SizedBox(width: 7),
                  Text(
                    'Items (${_lines.length})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _addCharge,
                    icon: const Icon(Icons.add_card_outlined, size: 16),
                    label: const Text('Charge'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _saving ? null : _addLine,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Product'),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: _lines.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.playlist_add_outlined,
                          size: 34,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'Add or scan a product to start the invoice.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Rows scroll vertically. All columns and remove stay visible.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        color: scheme.surfaceContainerHighest,
                        child: Row(
                          children: [
                            _saleHeaderCell('#', 1),
                            _saleHeaderCell('SKU', 2),
                            _saleHeaderCell('Product', 4),
                            _saleHeaderCell('Qty', 2),
                            _saleHeaderCell('Rate', 2),
                            _saleHeaderCell('Disc.', 2),
                            _saleHeaderCell('GST', 1),
                            _saleHeaderCell('Amount', 2),
                            const SizedBox(width: 42),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: _lines.length,
                          itemBuilder: (context, index) => _SaleLineRow(
                            index: index + 1,
                            line: _lines[index],
                            money: _money,
                            onDelete: _saving
                                ? null
                                : () => setState(() => _lines.removeAt(index)),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _desktopSettlementPanel() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: scheme.surfaceContainerHighest.withValues(alpha: .55),
            child: const Row(
              children: [
                Icon(Icons.payments_outlined, size: 17),
                SizedBox(width: 7),
                Text(
                  'Totals & Payment',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              children: [
                _desktopTotalRow('Subtotal', _money(_subtotal)),
                _desktopTotalRow('Discount', '- ${_money(_discount)}'),
                _desktopTotalRow('Taxable', _money(_taxableAmount)),
                if (_interstatePreview == false) ...[
                  _desktopTotalRow('CGST', _money(_cgstPreview)),
                  _desktopTotalRow('SGST', _money(_sgstPreview)),
                ] else if (_interstatePreview == true)
                  _desktopTotalRow('IGST', _money(_igstPreview))
                else
                  _desktopTotalRow('GST / Tax', _money(_tax)),
                _desktopTotalRow('Round Off', _money(_roundOff)),
                const Divider(height: 12),
                _desktopTotalRow(
                  'GRAND TOTAL',
                  _money(_grandTotal),
                  strong: true,
                ),
                _desktopTotalRow('Settled', _money(_settledPayment)),
                _desktopTotalRow(
                  'Receivable',
                  _money(_balanceDue),
                  strong: _balanceDue > 0.005,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MultiPaymentEditor(
                    tenantId: widget.session.business.id,
                    total: _grandTotal,
                    customerIsWalkIn: _selectedCustomer?.isWalkIn ?? true,
                    customerName: _selectedCustomer?.name ?? '',
                    enabled: !_saving,
                    onChanged: (value) {
                      setState(() {
                        _paymentAllocations = value;
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    enabled: !_saving,
                    minLines: 1,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.notes_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .045),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Round-off is automatic. Freight, cutting, installation '
                      'and similar charges must use GST-classified Service products.',
                      style: TextStyle(fontSize: 9.5),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopTotalRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 11 : 10,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 12 : 10.5,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopActionBar() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            _error == null
                ? Icons.verified_outlined
                : Icons.error_outline_rounded,
            size: 17,
            color: _error == null ? scheme.primary : scheme.error,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _error ??
                  '${_lines.length} item${_lines.length == 1 ? '' : 's'} | '
                      '${_money(_grandTotal)} | '
                      '${_balanceDue > 0.005 ? '${_money(_balanceDue)} receivable' : 'fully allocated'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: _error == null ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _saving
                ? null
                : () {
                    if (widget.embedded) {
                      widget.onFinished?.call(false);
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _post(printAfter: false),
            icon: const Icon(Icons.check_circle_outline, size: 17),
            label: const Text('Confirm'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: _saving ? null : () => _post(printAfter: true),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined, size: 17),
            label: Text(_saving ? 'Confirming...' : 'Print & Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _documentHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      child: Row(
        children: [
          if (widget.embedded) ...[
            IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: _saving ? null : () => widget.onFinished?.call(false),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 12),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEW SALES INVOICE',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text('Sales Invoice', style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('INVOICE NO.', style: TextStyle(fontSize: 11)),
              SizedBox(height: 3),
              Text(
                'AUTO ON CONFIRM',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _customerCard() {
    final customer = _selectedCustomer;

    return _SaleCard(
      title: 'Invoice Details',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final gap = compact ? 10.0 : 12.0;
          final fieldWidth = compact
              ? constraints.maxWidth
              : (constraints.maxWidth - gap * 2) / 3;

          return Wrap(
            spacing: gap,
            runSpacing: 12,
            children: [
              SizedBox(
                width: compact ? constraints.maxWidth : fieldWidth * 2 + gap,
                child: SearchableSelect<String>(
                  value: _customerId,
                  labelText: 'Customer',
                  isRequired: true,
                  enabled: !_saving,
                  hintText: 'Search customer name, ID, phone or email',
                  prefixIcon: Icons.person_search_outlined,
                  options: _customerOptions,
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
              SizedBox(
                width: fieldWidth,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: _saving ? null : _chooseSaleDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Invoice Date  ${_date(_saleDate)}'),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _invoiceReadOnlyField(
                  label: 'GSTIN',
                  value: customer?.taxNumber?.trim().isNotEmpty == true
                      ? customer!.taxNumber!
                      : 'Not registered',
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _invoiceReadOnlyField(
                  label: 'Place of Supply',
                  value: _placeOfSupply,
                  icon: Icons.place_outlined,
                ),
              ),
              if (_requiresDueDate)
                SizedBox(
                  width: fieldWidth,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: _saving ? null : _chooseDueDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _dueDate == null
                          ? 'Due Date  Required'
                          : 'Due Date  ${_date(_dueDate!)}',
                    ),
                  ),
                ),
              if (customer?.isWalkIn == true)
                SizedBox(
                  width: compact ? constraints.maxWidth : fieldWidth * 2 + gap,
                  child: const Text(
                    'Walk-in sales must be fully paid before confirmation.',
                    style: TextStyle(color: Colors.deepOrange),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _invoiceReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _itemsCard() {
    return _SaleCard(
      title: 'ADD PRODUCTS / CHARGES',
      trailing: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _saving ? null : _addCharge,
            icon: const Icon(Icons.add_card_outlined),
            label: const Text('Add Charge'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _addLine,
            icon: const Icon(Icons.add),
            label: const Text('Add Product'),
          ),
        ],
      ),
      child: _lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: Text('Search or scan a product to start this invoice.'),
              ),
            )
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  color: const Color(0xFFF1F4F8),
                  child: Row(
                    children: [
                      _saleHeaderCell('#', 1),
                      _saleHeaderCell('SKU', 2),
                      _saleHeaderCell('Product', 4),
                      _saleHeaderCell('Qty', 2),
                      _saleHeaderCell('Rate', 2),
                      _saleHeaderCell('Disc.', 2),
                      _saleHeaderCell('GST', 1),
                      _saleHeaderCell('Amount', 2),
                      const SizedBox(width: 42),
                    ],
                  ),
                ),
                for (var i = 0; i < _lines.length; i++)
                  _SaleLineRow(
                    index: i + 1,
                    line: _lines[i],
                    money: _money,
                    onDelete: _saving
                        ? null
                        : () => setState(() => _lines.removeAt(i)),
                  ),
              ],
            ),
    );
  }

  Widget _saleHeaderCell(String label, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _paymentCard() {
    final taxSummary = Column(
      children: [
        _SaleTotalRow(label: 'Subtotal', value: _money(_subtotal)),
        _SaleTotalRow(label: 'Discount', value: '- ${_money(_discount)}'),
        _SaleTotalRow(label: 'Taxable Amount', value: _money(_taxableAmount)),
        if (_interstatePreview == false) ...[
          _SaleTotalRow(label: 'CGST', value: _money(_cgstPreview)),
          _SaleTotalRow(label: 'SGST', value: _money(_sgstPreview)),
        ] else if (_interstatePreview == true)
          _SaleTotalRow(label: 'IGST', value: _money(_igstPreview))
        else
          _SaleTotalRow(label: 'GST / Tax', value: _money(_tax)),
        _SaleTotalRow(label: 'Round Off', value: _money(_roundOff)),
        const Divider(height: 24),
        _SaleTotalRow(
          label: 'GRAND TOTAL',
          value: _money(_grandTotal),
          bold: true,
        ),
        _SaleTotalRow(label: 'Settled', value: _money(_settledPayment)),
        _SaleTotalRow(
          label: 'Accounts Receivable',
          value: _money(_balanceDue),
          bold: true,
        ),
      ],
    );

    return _SaleCard(
      title: 'TOTALS & PAYMENT',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final payment = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MultiPaymentEditor(
                    tenantId: widget.session.business.id,
                    total: _grandTotal,
                    customerIsWalkIn: _selectedCustomer?.isWalkIn ?? true,
                    customerName: _selectedCustomer?.name ?? '',
                    enabled: !_saving,
                    onChanged: (value) {
                      setState(() {
                        _paymentAllocations = value;
                        _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Round-off is automatic. Freight, cutting, installation '
                      'and other charges must be GST-classified Service products.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    enabled: !_saving,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 860) {
                return Column(
                  children: [payment, const SizedBox(height: 22), taxSummary],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: payment),
                  const SizedBox(width: 36),
                  Expanded(flex: 2, child: taxSummary),
                ],
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
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
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () {
                          if (widget.embedded) {
                            widget.onFinished?.call(false);
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                  child: const Text('Cancel'),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _post(printAfter: false),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Just Confirm'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _post(printAfter: true),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: Text(_saving ? 'Confirming...' : 'Print & Confirm'),
                ),
              ],
            ),
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
  final List<String> serialNumbers;

  const _SaleLine({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    required this.cuttingChargeApplied,
    this.pricingSource,
    this.serialNumbers = const [],
  });

  String get unitCode => unit?.code ?? product.baseUnitCode;
  double get baseQuantity => quantity * (unit?.conversionToBase ?? 1);
  double get subtotal => quantity * unitPrice;

  double get taxable => subtotal - discount;

  double get tax => taxable * taxRate / 100;

  double get cuttingCharge => 0;

  double get total => taxable + tax;

  _SaleLine copyWith({double? unitPrice, String? pricingSource}) => _SaleLine(
    product: product,
    unit: unit,
    quantity: quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    discount: discount,
    taxRate: taxRate,
    cuttingChargeApplied: cuttingChargeApplied,
    pricingSource: pricingSource ?? this.pricingSource,
    serialNumbers: serialNumbers,
  );
}

class _AddSaleItemDialog extends StatefulWidget {
  final List<InventoryProduct> products;
  final String tenantId;
  final String locationId;

  const _AddSaleItemDialog({
    required this.products,
    required this.tenantId,
    required this.locationId,
  });

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
  final TextEditingController _serialsController = TextEditingController();
  final TrackingService _trackingService = TrackingService();
  List<Map<String, dynamic>> _serialOptions = const [];
  final Set<String> _selectedSerials = <String>{};
  bool _loadingSerials = false;

  String? _error;
  late final Map<String, InventoryProduct> _productByVariantId;
  late final Map<String, String> _productSearchText;
  late final Map<String, List<String>> _productPrefixTokens;

  @override
  void initState() {
    super.initState();
    final byVariant = <String, InventoryProduct>{};
    final searchText = <String, String>{};
    final prefixTokens = <String, List<String>>{};

    for (final product in widget.products) {
      final name = product.productName.toLowerCase();
      final sku = product.sku.toLowerCase();
      final part = (product.partNumber ?? '').toLowerCase();
      final barcode = (product.barcode ?? '').toLowerCase();
      final codes = product.searchCodes.toLowerCase();

      byVariant[product.variantId] = product;
      searchText[product.variantId] = [
        name,
        sku,
        part,
        barcode,
        codes,
      ].join('\u0001');
      prefixTokens[product.variantId] = <String>[
        name,
        sku,
        part,
        barcode,
        ...codes.split(RegExp(r'\s+')).where((value) => value.isNotEmpty),
      ];
    }

    _productByVariantId = Map<String, InventoryProduct>.unmodifiable(byVariant);
    _productSearchText = Map<String, String>.unmodifiable(searchText);
    _productPrefixTokens = Map<String, List<String>>.unmodifiable(prefixTokens);
  }

  Iterable<InventoryProduct> _searchProducts(String query, int limit) {
    if (query.isEmpty) return widget.products.take(limit);

    final starts = <InventoryProduct>[];
    final contains = <InventoryProduct>[];
    for (final product in widget.products) {
      final tokens =
          _productPrefixTokens[product.variantId] ?? const <String>[];
      if (tokens.any((token) => token.startsWith(query))) {
        if (starts.length < limit) starts.add(product);
      } else if ((_productSearchText[product.variantId] ?? '').contains(
        query,
      )) {
        if (contains.length < limit) contains.add(product);
      }
    }

    return <InventoryProduct>[...starts, ...contains].take(limit);
  }

  InventoryProduct? get _product {
    final id = _variantId;

    if (id == null) {
      return null;
    }

    return _productByVariantId[id];
  }

  ProductUnitOption? get _selectedUnit {
    final product = _product;
    if (product == null) return null;
    for (final unit in product.saleUnits) {
      if (unit.unitId == _unitId) return unit;
    }
    return product.defaultSaleUnit;
  }

  Future<void> _selectProduct(String? value) async {
    setState(() {
      _variantId = value;
      _serialsController.clear();
      _serialOptions = const [];
      _selectedSerials.clear();
      _loadingSerials = false;

      final product = _product;
      if (product != null) {
        final unit = product.defaultSaleUnit;
        _unitId = unit?.unitId;
        _cuttingChargeApplied = false;
        _priceController.text =
            (unit?.salePriceFor(product.sellingPrice) ?? product.sellingPrice)
                .toStringAsFixed(2);
        _taxController.text = product.taxRate.toStringAsFixed(2);
        _error = null;
        _loadingSerials = product.trackingMode == 'serial';
      }
    });

    final product = _product;
    if (product == null || product.trackingMode != 'serial') return;

    try {
      final rows = await _trackingService.searchSerials(
        tenantId: widget.tenantId,
        locationId: widget.locationId,
        limit: 500,
      );
      if (!mounted || _product?.variantId != product.variantId) return;
      setState(() {
        _serialOptions = rows
            .where(
              (row) =>
                  row['variant_id']?.toString() == product.variantId &&
                  row['status']?.toString() == 'in_stock',
            )
            .toList();
        _loadingSerials = false;
      });
    } catch (error) {
      if (!mounted || _product?.variantId != product.variantId) return;
      setState(() {
        _loadingSerials = false;
        _error =
            'Could not load available serials. You can still scan/type them manually. $error';
      });
    }
  }

  String _stockText(InventoryProduct product) {
    if (product.itemType != 'stock') {
      return product.itemType == 'service' ? 'Service' : 'Non-stock';
    }

    return 'Stock: '
        '${product.stockQuantity.toStringAsFixed(2)} '
        '${product.baseUnitCode}';
  }

  List<String> _serialValues() {
    final values = <String>{..._selectedSerials};
    values.addAll(
      _serialsController.text
          .split(RegExp(r'[\n,;]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty),
    );
    return values.toList();
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
        cuttingChargeApplied: _cuttingChargeApplied,
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
            Autocomplete<InventoryProduct>(
              displayStringForOption: (p) => '${p.productName} — ${p.sku}',
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                return _searchProducts(q, 30);
              },
              onSelected: (p) => unawaited(_selectProduct(p.variantId)),
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
                    _cuttingChargeApplied = false;
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

            if ((_selectedUnit?.cuttingAllowed ?? false) &&
                (_selectedUnit?.cuttingCharge ?? 0) > 0) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _cuttingChargeApplied,
                onChanged: (value) =>
                    setState(() => _cuttingChargeApplied = value),
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
                      helperText:
                          'THQ pricing is resolved again for the selected customer and quantity.',
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
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select available serial numbers',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (_loadingSerials)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (!_loadingSerials)
                      Text(
                        '${_serialOptions.length} available',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (!_loadingSerials && _serialOptions.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No selectable serials were returned. You can still scan or enter a serial manually.',
                  ),
                ),
              if (_serialOptions.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _serialOptions.map((row) {
                        final serial = row['serial_number']?.toString() ?? '';
                        final selected = _selectedSerials.contains(serial);
                        return FilterChip(
                          label: Text(serial),
                          selected: selected,
                          onSelected: (value) => setState(() {
                            if (value) {
                              _selectedSerials.add(serial);
                            } else {
                              _selectedSerials.remove(serial);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _serialsController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Manual / scanned serial numbers',
                  hintText: 'Optional: scan or enter one serial per base unit',
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
  final int index;
  final _SaleLine line;
  final String Function(double) money;
  final VoidCallback? onDelete;

  const _SaleLineRow({
    required this.index,
    required this.line,
    required this.money,
    required this.onDelete,
  });

  String _quantity(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget child, int flex) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          cell(Text('$index'), 1),
          cell(
            Text(
              line.product.sku,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            2,
          ),
          cell(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if ((line.product.partNumber ?? '').isNotEmpty)
                  Text(
                    line.product.partNumber!,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                if (line.cuttingCharge > 0)
                  Text(
                    'Cutting ${money(line.cuttingCharge)}',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
              ],
            ),
            4,
          ),
          cell(Text('${_quantity(line.quantity)} ${line.unitCode}'), 2),
          cell(Text(money(line.unitPrice)), 2),
          cell(Text(money(line.discount)), 2),
          cell(Text('${line.taxRate.toStringAsFixed(0)}%'), 1),
          cell(
            Text(
              money(line.total),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            2,
          ),
          SizedBox(
            width: 44,
            child: IconButton(
              tooltip: 'Remove product',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
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

          const SizedBox(height: 10),

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
