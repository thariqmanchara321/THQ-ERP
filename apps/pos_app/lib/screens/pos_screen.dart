import 'dart:async';

import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';
import 'package:uuid/uuid.dart';

import '../models/client_session.dart';
import '../models/customer.dart';
import '../models/inventory_product.dart';
import '../models/sale_detail.dart';
import '../services/cashier_shift_service.dart';
import '../services/pricing_service.dart';
import '../services/sales_service.dart';
import '../services/tracking_service.dart';
import '../services/pos_completion_service.dart';
import '../services/pos_hardware_service.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_template_service.dart';
import '../services/offline_pos_service.dart';
import '../services/offline_pos_sync_service.dart';
import '../services/offline_receipt_service.dart';
import '../ui/v43_theme.dart';
import '../widgets/customer_account_dialog.dart';
import '../widgets/multi_payment_editor.dart';

class PosScreen extends StatefulWidget {
  final ClientSession session;

  const PosScreen({super.key, required this.session});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

enum _PosWorkspace { products, hold, heldInvoices, quantity }

class _PosScreenState extends State<PosScreen> {
  final PricingService _pricing = PricingService();
  final CashierShiftService _shiftService = CashierShiftService();
  final SalesService _sales = SalesService();
  final TrackingService _tracking = TrackingService();
  final PosCompletionService _completion = PosCompletionService();
  final PosHardwareService _hardware = PosHardwareService();
  final InvoicePdfService _invoicePdf = InvoicePdfService();
  final InvoiceTemplateService _invoiceTemplates = InvoiceTemplateService();
  final OfflinePosService _offlineLocal = OfflinePosService.instance;
  final OfflinePosSyncService _offlineSync = OfflinePosSyncService();
  final OfflineReceiptService _offlineReceipt = OfflineReceiptService();
  final TextEditingController _search = TextEditingController();
  final TextEditingController _tendered = TextEditingController();
  final TextEditingController _paymentReference = TextEditingController();
  final TextEditingController _orderDiscount = TextEditingController(
    text: '0.00',
  );
  final TextEditingController _roundOff = TextEditingController(text: '0.00');
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _holdLabel = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final List<_PosLine> _cart = [];
  String? _checkoutRequestId;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<InventoryProduct> _products = const [];
  List<Customer> _customers = const [];
  List<Map<String, dynamic>> _heldSales = const [];
  bool _heldLoading = false;
  _PosWorkspace _workspace = _PosWorkspace.products;
  String? _customerId;
  InventoryProduct? _selectedProduct;
  _PosLine? _editingLine;
  String _category = 'All';
  String _sort = 'name';
  String _paymentMethod = 'cash';
  List<Map<String, dynamic>> _paymentAllocations = const [];
  String _orderMode = 'counter';
  int _step = 0;
  Timer? _searchDebounce;
  Timer? _offlineSyncTimer;
  bool _offlineMode = false;
  bool _offlineHeartbeatBusy = false;

  Map<String, Customer> _customerById = const {};
  Map<String, InventoryProduct> _productByVariantId = const {};
  Map<String, InventoryProduct> _exactProductIndex = const {};
  Map<String, String> _productSearchIndex = const {};
  List<String> _categoryCache = const ['All'];
  String? _filteredProductsCacheKey;
  List<InventoryProduct> _filteredProductsCache = const [];
  final Map<_PosLine, Timer> _priceDebounce = <_PosLine, Timer>{};
  int _totalsRevision = 0;
  int _totalsCacheRevision = -1;
  _PosTotalsSnapshot? _totalsCache;

  bool get _canUse =>
      widget.session.hasPermission('pos.use') ||
      widget.session.hasPermission('sales.manage') ||
      widget.session.hasRole('owner');

  bool get _restaurantAvailable =>
      widget.session.hasModule('restaurant') &&
      (widget.session.device?.allowedModules.contains('restaurant') ?? false);

  Customer? get _customer {
    final id = _customerId;
    return id == null ? null : _customerById[id];
  }

  double _lineGross(_PosLine line) => line.quantity * line.unitPrice;

  void _invalidateTotals() {
    _totalsRevision++;
  }

  _PosTotalsSnapshot get _totalsSnapshot {
    final cached = _totalsCache;
    if (cached != null && _totalsCacheRevision == _totalsRevision) {
      return cached;
    }

    var subtotal = 0.0;
    for (final line in _cart) {
      subtotal += _lineGross(line);
    }

    final requestedDiscount =
        double.tryParse(_orderDiscount.text.trim()) ?? 0.0;
    final manualOrderDiscount = requestedDiscount
        .clamp(0.0, subtotal)
        .toDouble();

    var discount = 0.0;
    var tax = 0.0;
    for (final line in _cart) {
      final gross = _lineGross(line);
      final allocated = subtotal <= 0
          ? 0.0
          : manualOrderDiscount * (gross / subtotal);
      final effectiveDiscount = (line.discount + allocated)
          .clamp(0.0, gross)
          .toDouble();
      discount += effectiveDiscount;
      final taxable = gross - effectiveDiscount;
      tax += taxable * line.product.taxRate / 100.0;
    }

    final beforeRoundOff = subtotal - discount + tax + _cuttingCharges;
    final delta = beforeRoundOff.roundToDouble() - beforeRoundOff;
    final roundOffAmount = delta.abs() < 0.000001 ? 0.0 : delta;
    final snapshot = _PosTotalsSnapshot(
      subtotal: subtotal,
      manualOrderDiscount: manualOrderDiscount,
      discount: discount,
      tax: tax,
      beforeRoundOff: beforeRoundOff,
      roundOffAmount: roundOffAmount,
      total: beforeRoundOff + roundOffAmount,
    );
    _totalsCache = snapshot;
    _totalsCacheRevision = _totalsRevision;
    return snapshot;
  }

  double get _subtotal => _totalsSnapshot.subtotal;

  double get _cuttingCharges => 0.0;

  double _effectiveLineDiscount(_PosLine line) {
    final totals = _totalsSnapshot;
    if (totals.subtotal <= 0) return line.discount;
    final gross = _lineGross(line);
    final allocated = totals.manualOrderDiscount * (gross / totals.subtotal);
    return (line.discount + allocated).clamp(0.0, gross).toDouble();
  }

  double get _discount => _totalsSnapshot.discount;

  double get _tax => _totalsSnapshot.tax;

  double get _roundOffAmount => _totalsSnapshot.roundOffAmount;

  double get _beforeRoundOff => _totalsSnapshot.beforeRoundOff;

  double get _total => _totalsSnapshot.total;

  // ignore: unused_element
  void _applyRoundOff() {
    final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;
    setState(() {
      _roundOff.text = delta.abs() < 0.000001
          ? '0.00'
          : delta.toStringAsFixed(2);
      _syncTendered();
    });
  }

  double get _tenderedAmount {
    if (_paymentAllocations.isEmpty) return 0;
    final first = _paymentAllocations.first;
    return (first['tendered_amount'] as num?)?.toDouble() ??
        double.tryParse('${first['tendered_amount']}') ??
        0;
  }

  // ignore: unused_element
  double get _allocatedTotal {
    var remaining = _total;
    var allocated = 0.0;
    for (final allocation in _paymentAllocations) {
      if (remaining <= 0) break;
      final amount =
          (allocation['tendered_amount'] as num?)?.toDouble() ??
          double.tryParse('${allocation['tendered_amount']}') ??
          0;
      if (amount <= 0) continue;
      final use = amount > remaining ? remaining : amount;
      allocated += use;
      remaining -= use;
    }
    return allocated;
  }

  double get _appliedPayment {
    var remaining = _total;
    var settled = 0.0;
    for (final allocation in _paymentAllocations) {
      if (remaining <= 0) break;
      final amount =
          (allocation['tendered_amount'] as num?)?.toDouble() ??
          double.tryParse('${allocation['tendered_amount']}') ??
          0;
      if (amount <= 0) continue;
      final use = amount > remaining ? remaining : amount;
      if (allocation['method_code']?.toString() != 'credit') {
        settled += use;
      }
      remaining -= use;
    }
    return settled;
  }

  double get _accountBalance =>
      (_total - _appliedPayment).clamp(0.0, _total).toDouble();

  double get _change {
    var remaining = _total;
    var change = 0.0;
    for (final allocation in _paymentAllocations) {
      final amount =
          (allocation['tendered_amount'] as num?)?.toDouble() ??
          double.tryParse('${allocation['tendered_amount']}') ??
          0;
      if (amount <= 0) continue;
      final use = remaining <= 0
          ? 0.0
          : (amount > remaining ? remaining : amount);
      if (allocation['method_code']?.toString() == 'cash' && amount > use) {
        change += amount - use;
      }
      remaining = (remaining - use).clamp(0.0, _total).toDouble();
    }
    return change;
  }

  List<String> get _categories => _categoryCache;

  void _invalidateProductFilter() {
    _filteredProductsCacheKey = null;
    _filteredProductsCache = const [];
  }

  void _rebuildCatalogueCaches(
    List<InventoryProduct> products,
    List<Customer> customers,
  ) {
    final customerById = <String, Customer>{};
    for (final customer in customers) {
      customerById[customer.id] = customer;
    }

    final productByVariantId = <String, InventoryProduct>{};
    final exactProductIndex = <String, InventoryProduct>{};
    final productSearchIndex = <String, String>{};
    final categorySet = <String>{};

    for (final product in products) {
      productByVariantId[product.variantId] = product;

      void addExact(String? value) {
        final normalized = value?.trim().toLowerCase() ?? '';
        if (normalized.isEmpty) return;
        exactProductIndex.putIfAbsent(normalized, () => product);
      }

      addExact(product.sku);
      addExact(product.barcode);
      addExact(product.partNumber);
      for (final identifier in product.identifiers) {
        if (identifier.active) addExact(identifier.code);
      }

      final category = product.categoryName?.trim() ?? '';
      if (category.isNotEmpty) categorySet.add(category);

      productSearchIndex[product.variantId] = [
        product.productName,
        product.sku,
        product.barcode ?? '',
        product.partNumber ?? '',
        product.searchCodes,
        product.brandName ?? '',
        product.categoryName ?? '',
      ].join('\u0001').toLowerCase();
    }

    final categories = categorySet.toList()..sort();
    _customerById = Map<String, Customer>.unmodifiable(customerById);
    _productByVariantId = Map<String, InventoryProduct>.unmodifiable(
      productByVariantId,
    );
    _exactProductIndex = Map<String, InventoryProduct>.unmodifiable(
      exactProductIndex,
    );
    _productSearchIndex = Map<String, String>.unmodifiable(productSearchIndex);
    _categoryCache = List<String>.unmodifiable(['All', ...categories]);
    _invalidateProductFilter();
  }

  List<InventoryProduct> get _filteredProducts {
    final query = _search.text.trim().toLowerCase();
    final cacheKey = '$query\u0001$_category\u0001$_sort';
    if (_filteredProductsCacheKey == cacheKey) {
      return _filteredProductsCache;
    }

    final rows = _products.where((product) {
      final categoryMatch =
          _category == 'All' || product.categoryName == _category;
      if (!categoryMatch) return false;
      if (query.isEmpty) return true;
      return (_productSearchIndex[product.variantId] ?? '').contains(query);
    }).toList();

    switch (_sort) {
      case 'price_low':
        rows.sort((a, b) => a.sellingPrice.compareTo(b.sellingPrice));
        break;
      case 'price_high':
        rows.sort((a, b) => b.sellingPrice.compareTo(a.sellingPrice));
        break;
      case 'stock_high':
        rows.sort((a, b) => b.stockQuantity.compareTo(a.stockQuantity));
        break;
      case 'category':
        rows.sort(
          (a, b) => (a.categoryName ?? '').compareTo(b.categoryName ?? ''),
        );
        break;
      default:
        rows.sort((a, b) => a.productName.compareTo(b.productName));
    }

    _filteredProductsCacheKey = cacheKey;
    _filteredProductsCache = List<InventoryProduct>.unmodifiable(rows);
    return _filteredProductsCache;
  }

  @override
  void initState() {
    super.initState();
    _paymentMethod =
        widget.session
            .setting('pos.default_payment_method', 'cash')
            ?.toString() ??
        'cash';
    unawaited(_offlineLocal.initialize());
    _load();
    _offlineSyncTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_offlineHeartbeat()),
    );
  }

  @override
  void dispose() {
    _offlineSyncTimer?.cancel();
    _searchDebounce?.cancel();
    for (final timer in _priceDebounce.values) {
      timer.cancel();
    }
    _priceDebounce.clear();
    _search.dispose();
    _tendered.dispose();
    _paymentReference.dispose();
    _orderDiscount.dispose();
    _roundOff.dispose();
    _notes.dispose();
    _holdLabel.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _offlineLocal.initialize();
      OfflineCatalogue catalogue;
      var offline = false;
      try {
        catalogue = await _offlineSync.refreshCatalogue(widget.session);
      } catch (onlineError) {
        offline = true;
        catalogue = await _offlineSync.cachedCatalogue(widget.session);
        if (catalogue.products.isEmpty || catalogue.customers.isEmpty) {
          throw StateError(
            'POS is offline and no local product/customer cache is available yet. Connect once and refresh the POS before using offline billing. $onlineError',
          );
        }
      }
      final products = catalogue.products
          .where(
            (product) =>
                product.productStatus == 'active' &&
                product.variantStatus == 'active',
          )
          .toList();
      final customers = catalogue.customers
          .where((customer) => customer.isActive)
          .toList();
      String? selectedCustomer = _customerId;
      if (selectedCustomer == null ||
          !customers.any((customer) => customer.id == selectedCustomer)) {
        for (final customer in customers) {
          if (customer.isWalkIn) {
            selectedCustomer = customer.id;
            break;
          }
        }
        selectedCustomer ??= customers.isEmpty ? null : customers.first.id;
      }
      if (!mounted) return;
      _rebuildCatalogueCaches(products, customers);
      setState(() {
        _products = products;
        _customers = customers;
        _customerId = selectedCustomer;
        _offlineMode = offline;
        if (!_categories.contains(_category)) _category = 'All';
      });
      if (!offline) {
        try {
          await _refreshHeldSales(silent: true);
        } catch (_) {}
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _offlineHeartbeat() async {
    if (_offlineHeartbeatBusy ||
        _saving ||
        !mounted ||
        widget.session.device == null) {
      return;
    }
    _offlineHeartbeatBusy = true;
    try {
      final result = await _offlineSync.syncPending(widget.session);
      if (result.synced > 0 || _offlineMode) {
        final catalogue = await _offlineSync.refreshCatalogue(widget.session);
        if (!mounted) return;
        final products = catalogue.products
            .where(
              (p) => p.productStatus == 'active' && p.variantStatus == 'active',
            )
            .toList();
        final customers = catalogue.customers.where((c) => c.isActive).toList();
        _rebuildCatalogueCaches(products, customers);
        setState(() {
          _products = products;
          _customers = customers;
          _offlineMode = false;
        });
      }
    } catch (_) {
      if (mounted && !_offlineMode) setState(() => _offlineMode = true);
    } finally {
      _offlineHeartbeatBusy = false;
    }
  }

  String _money(double value) => widget.session.currencyCode == 'INR'
      ? '₹${value.toStringAsFixed(2)}'
      : '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';

  void _add(InventoryProduct product) {
    if (product.trackingMode == 'serial') {
      unawaited(_promptSerial(product));
      return;
    }
    if (product.itemType == 'stock' && product.stockQuantity <= 0) {
      _message('${product.productName} is out of stock.');
      return;
    }
    final index = _cart.indexWhere(
      (line) => line.product.variantId == product.variantId,
    );
    _PosLine? changedLine;
    setState(() {
      _selectedProduct = product;
      if (index >= 0) {
        final line = _cart[index];
        final next = line.quantity + line.quantityStep;
        if (product.itemType != 'stock' ||
            next * line.conversionToBase <= product.stockQuantity + 0.000001) {
          line.quantity = next;
          line.resolvedUnitPrice = null;
          changedLine = line;
        } else {
          _message(
            'Only ${_formatStock(product.stockQuantity, product.baseUnitCode)} available.',
          );
        }
      } else {
        final line = _PosLine(product: product);
        if (product.itemType != 'stock' ||
            line.baseQuantity <= product.stockQuantity + 0.000001) {
          _cart.add(line);
          changedLine = line;
        } else {
          _message(
            'Only ${_formatStock(product.stockQuantity, product.baseUnitCode)} available.',
          );
        }
      }
      _syncTendered();
    });
    if (changedLine != null) _scheduleLinePrice(changedLine!);
    _searchFocus.requestFocus();
  }

  Future<void> _promptSerial(InventoryProduct product) async {
    if (product.stockQuantity <= 0) {
      _message('${product.productName} is out of stock.');
      return;
    }

    final controller = TextEditingController();
    final device = widget.session.device;
    var available = <Map<String, dynamic>>[];

    if (!_offlineMode && device != null) {
      try {
        final rows = await _tracking.searchSerials(
          tenantId: widget.session.business.id,
          locationId: device.locationId,
          limit: 500,
        );
        available = rows
            .where(
              (row) =>
                  row['variant_id']?.toString() == product.variantId &&
                  row['status']?.toString() == 'in_stock',
            )
            .toList();
      } catch (_) {
        // Manual scanner/entry remains available even if the list cannot load.
      }
    }

    if (!mounted) {
      controller.dispose();
      return;
    }

    String? selected;
    final serial = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Serial • ${product.productName}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (available.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Select available serial',
                      prefixIcon: Icon(Icons.fact_check_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: available
                        .map(
                          (row) => DropdownMenuItem<String>(
                            value: row['serial_number']?.toString(),
                            child: Text(
                              row['serial_number']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      selected = value;
                      if (value != null) controller.text = value;
                    }),
                  ),
                  const SizedBox(height: 12),
                ] else if (_offlineMode) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Offline mode: scan or enter a cached serial number.',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: controller,
                  autofocus: available.isEmpty,
                  onSubmitted: (value) =>
                      Navigator.of(dialogContext).pop(value.trim()),
                  decoration: const InputDecoration(
                    labelText: 'Scan / enter serial number',
                    prefixIcon: Icon(Icons.qr_code_scanner_outlined),
                    border: OutlineInputBorder(),
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
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Add Serial'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (serial == null || serial.trim().isEmpty || !mounted) return;
    await _addSerialByCode(product, serial.trim());
  }

  Future<void> _addSerialByCode(
    InventoryProduct product,
    String serialNumber,
  ) async {
    final device = widget.session.device;
    if (device == null) {
      _message('POS device context is unavailable.');
      return;
    }
    try {
      Map<String, dynamic>? resolved = await _offlineLocal.findAvailableSerial(
        tenantId: widget.session.business.id,
        locationId: device.locationId,
        serialNumber: serialNumber,
      );
      if (resolved == null && !_offlineMode) {
        resolved = await _tracking.resolveSerial(
          tenantId: widget.session.business.id,
          serialNumber: serialNumber,
        );
      }
      if (resolved == null || resolved['status']?.toString() != 'in_stock') {
        _message(
          'Serial $serialNumber is not available at this POS store or offline cache.',
        );
        return;
      }
      if (resolved['variant_id']?.toString() != product.variantId) {
        _message('Serial $serialNumber belongs to a different product.');
        return;
      }
      _addResolvedSerial(
        product,
        resolved['serial_number']?.toString() ?? serialNumber,
      );
    } catch (error) {
      _message(error.toString());
    }
  }

  void _addResolvedSerial(InventoryProduct product, String serialNumber) {
    final normalized = serialNumber.trim().toLowerCase();
    if (_cart.any(
      (line) => line.serialNumbers.any(
        (value) => value.trim().toLowerCase() == normalized,
      ),
    )) {
      _message('Serial $serialNumber is already in this invoice.');
      return;
    }
    var index = _cart.indexWhere(
      (line) => line.product.variantId == product.variantId,
    );
    _PosLine line;
    setState(() {
      _selectedProduct = product;
      if (index < 0) {
        line = _PosLine(product: product);
        _cart.add(line);
        index = _cart.length - 1;
      }
      line = _cart[index];
      line.serialNumbers.add(serialNumber.trim());
      line.quantity = line.serialNumbers.length.toDouble();
      line.resolvedUnitPrice = null;
      _syncTendered();
    });
    _scheduleLinePrice(_cart[index]);
    _searchFocus.requestFocus();
  }

  String _formatStock(double value, String unitCode) =>
      '${value.toStringAsFixed(value % 1 == 0 ? 0 : 3)} $unitCode';

  void _changeQuantity(_PosLine line, double delta) {
    if (line.product.trackingMode == 'serial') {
      _message(
        'Serial-tracked quantity is controlled by scanned serial numbers. Remove the line and rescan if needed.',
      );
      return;
    }
    setState(() {
      final next = line.quantity + delta;
      if (next <= 0.000001) {
        if (identical(_editingLine, line)) {
          _editingLine = null;
          _workspace = _PosWorkspace.products;
        }
        _cart.remove(line);
      } else if (line.product.itemType != 'stock' ||
          next * line.conversionToBase <=
              line.product.stockQuantity + 0.000001) {
        line.quantity = next;
        line.resolvedUnitPrice = null;
      } else {
        _message(
          'Only ${_formatStock(line.product.stockQuantity, line.product.baseUnitCode)} available.',
        );
      }
      _syncTendered();
    });
    if (_cart.contains(line)) _scheduleLinePrice(line);
  }

  void _openQuantityEditor(_PosLine line) {
    if (_saving) return;
    if (line.product.trackingMode == 'serial') {
      _message(
        'Serial-tracked quantity is controlled by scanned serial numbers.',
      );
      return;
    }
    setState(() {
      _editingLine = line;
      _workspace = _PosWorkspace.quantity;
      _error = null;
    });
  }

  void _setLineUnit(_PosLine line, ProductUnitOption unit) {
    if (line.product.trackingMode == 'serial' && !unit.isBase) {
      _message('Serial-tracked POS lines use the base unit.');
      return;
    }
    var nextQuantity = line.quantity;
    if (!unit.acceptsQuantity(nextQuantity)) {
      nextQuantity = unit.quantityStep > 1 ? unit.quantityStep : 1.0;
    }
    final newBase = nextQuantity * unit.conversionToBase;
    if (line.product.itemType == 'stock' &&
        newBase > line.product.stockQuantity + 0.000001) {
      _message(
        'Only ${_formatStock(line.product.stockQuantity, line.product.baseUnitCode)} available.',
      );
      return;
    }
    final quantityReset = (nextQuantity - line.quantity).abs() > 0.000001;
    setState(() {
      line.unit = unit;
      line.quantity = nextQuantity;
      line.resolvedUnitPrice = null;
      line.pricingSource = null;
      line.priceListId = null;
      line.cuttingChargeApplied = false;
      _syncTendered();
    });
    if (quantityReset) {
      _message(
        'Quantity reset to ${line.displayQuantity} ${unit.code} for this unit.',
      );
    }
    _scheduleLinePrice(line);
  }

  void _scheduleLinePrice(_PosLine line) {
    _priceDebounce.remove(line)?.cancel();
    _priceDebounce[line] = Timer(const Duration(milliseconds: 120), () {
      _priceDebounce.remove(line);
      if (!mounted || !_cart.contains(line)) return;
      unawaited(_resolveLinePrice(line));
    });
  }

  Future<void> _resolveLinePrice(_PosLine line) async {
    if (!_cart.contains(line)) return;
    if (_offlineMode) {
      line.resolvedUnitPrice = null;
      line.pricingSource = 'Offline cached price';
      line.priceListId = null;
      return;
    }
    final customerId = _customerId;
    final unitId = line.unit?.unitId;
    final quantity = line.quantity;
    try {
      final price = await _pricing.resolve(
        tenantId: widget.session.business.id,
        variantId: line.product.variantId,
        customerId: customerId,
        unitId: unitId,
        quantity: quantity,
        locationId: widget.session.device?.locationId,
      );
      if (!mounted || !_cart.contains(line)) return;
      if (_customerId != customerId ||
          line.unit?.unitId != unitId ||
          (line.quantity - quantity).abs() > 0.000001) {
        return;
      }
      setState(() {
        line.resolvedUnitPrice = price.unitPrice;
        line.pricingSource = price.sourceLabel;
        line.priceListId = price.priceListId;
        _syncTendered();
      });
    } catch (error) {
      if (!mounted) return;
      line.resolvedUnitPrice = null;
      line.pricingSource = null;
      line.priceListId = null;
      _message(
        'Pricing refresh failed for ${line.product.productName}: $error',
      );
    }
  }

  Future<void> _resolveAllPrices() async {
    final lines = List<_PosLine>.from(_cart);
    await Future.wait(lines.map(_resolveLinePrice));
  }

  void _searchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _searchSubmitted(String value) async {
    final raw = value.trim();
    final query = raw.toLowerCase();
    if (query.isEmpty) return;
    final exact = _exactProductIndex[query];
    if (exact != null) {
      _add(exact);
      _search.clear();
      if (mounted) setState(() {});
      return;
    }
    try {
      final device = widget.session.device;
      Map<String, dynamic>? serial;
      if (device != null) {
        serial = await _offlineLocal.findAvailableSerial(
          tenantId: widget.session.business.id,
          locationId: device.locationId,
          serialNumber: raw,
        );
      }
      if (serial == null && !_offlineMode) {
        serial = await _tracking.resolveSerial(
          tenantId: widget.session.business.id,
          serialNumber: raw,
        );
      }
      if (serial != null && serial['status']?.toString() == 'in_stock') {
        final variantId = serial['variant_id']?.toString();
        final product = variantId == null
            ? null
            : _productByVariantId[variantId];
        if (product != null) {
          _addResolvedSerial(
            product,
            serial['serial_number']?.toString() ?? raw,
          );
          _search.clear();
          if (mounted) setState(() {});
          return;
        }
      }
    } catch (_) {}
    _message('No product or available serial found for "$raw".');
  }

  Future<void> _chooseCustomer() async {
    final query = TextEditingController();
    Customer? selected;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final q = query.text.trim().toLowerCase();
          final rows = _customers.where((customer) {
            if (q.isEmpty) return true;
            return customer.name.toLowerCase().contains(q) ||
                customer.publicId.toLowerCase().contains(q) ||
                (customer.phone ?? '').toLowerCase().contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Select customer'),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    controller: query,
                    autofocus: true,
                    onChanged: (_) => setLocalState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search customer ID, name or phone…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = rows[index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              customer.isWalkIn
                                  ? Icons.directions_walk
                                  : Icons.person_outline,
                            ),
                          ),
                          title: Text(customer.name),
                          subtitle: Text(
                            [
                              if (customer.publicId.isNotEmpty)
                                customer.publicId,
                              if ((customer.phone ?? '').isNotEmpty)
                                customer.phone!,
                            ].join(' • '),
                          ),
                          trailing: customer.id == _customerId
                              ? const Icon(Icons.check_circle)
                              : null,
                          onTap: () {
                            selected = customer;
                            Navigator.pop(dialogContext);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    query.dispose();
    if (selected != null && mounted) {
      setState(() {
        _customerId = selected!.id;
        for (final line in _cart) {
          line.resolvedUnitPrice = null;
          line.pricingSource = null;
          line.priceListId = null;
        }
      });
      unawaited(_resolveAllPrices());
    }
  }

  void _syncTendered() {
    _invalidateTotals();
    if (_paymentMethod != 'cash') {
      _tendered.text = _paymentMethod == 'credit'
          ? '0.00'
          : _total.toStringAsFixed(2);
    }
  }

  // ignore: unused_element
  void _cashExact() =>
      setState(() => _tendered.text = _total.toStringAsFixed(2));

  // ignore: unused_element
  void _addCash(double amount) {
    setState(() {
      _tendered.text = (_tenderedAmount + amount).toStringAsFixed(2);
    });
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _validateCart() {
    if (!_canUse) {
      _error = 'You do not have POS permission.';
      return false;
    }
    if (_cart.isEmpty) {
      _error = 'Add at least one product.';
      return false;
    }
    if (_customer == null) {
      _error = 'Choose a customer.';
      return false;
    }
    for (final line in _cart) {
      if (line.product.trackingMode == 'serial' &&
          (line.baseQuantity - line.serialNumbers.length).abs() > 0.000001) {
        _error =
            '${line.product.productName}: scan exactly ${line.baseQuantity.toStringAsFixed(0)} serial number(s).';
        return false;
      }
    }
    return true;
  }

  bool _validatePayment() {
    final customer = _customer;
    if (customer == null) return false;
    if (_paymentAllocations.isEmpty) {
      _error = 'Allocate the invoice total to at least one payment method.';
      return false;
    }

    var remaining = _total;
    for (final allocation in _paymentAllocations) {
      final method = allocation['method_code']?.toString() ?? '';
      final amount =
          (allocation['tendered_amount'] as num?)?.toDouble() ??
          double.tryParse('${allocation['tendered_amount']}') ??
          0;
      if (amount < -0.0001) {
        _error = 'Payment amount cannot be negative.';
        return false;
      }
      if (method == 'credit' && customer.isWalkIn && amount > 0) {
        _error = 'Credit requires a named customer.';
        return false;
      }
      if (method != 'cash' && amount > remaining + 0.005) {
        _error = 'Only Cash may exceed the remaining invoice amount.';
        return false;
      }
      final used = amount > remaining ? remaining : amount;
      remaining = (remaining - used).clamp(0.0, _total).toDouble();
    }

    if (remaining > 0.005) {
      _error = 'Payment allocations must cover the invoice total.';
      return false;
    }
    if (customer.isWalkIn && _accountBalance > 0.005) {
      _error = 'Walk-in sales must be fully settled.';
      return false;
    }
    return true;
  }

  void _next() {
    setState(() {
      _error = null;
      if (_step == 0) {
        if (_validateCart()) {
          _step = 1;
          _syncTendered();
        }
      } else if (_step == 1) {
        if (_validatePayment()) _step = 2;
      }
    });
  }

  void _back() {
    if (_step > 0) setState(() => _step -= 1);
  }

  Map<String, dynamic> _heldState() => <String, dynamic>{
    'customer_id': _customerId,
    'order_mode': _orderMode,
    'order_discount': _orderDiscount.text,
    'round_off': _roundOff.text,
    'notes': _notes.text,
    'payment_method': _paymentMethod,
    'tendered': _tendered.text,
    'payment_reference': _paymentReference.text,
    'payment_allocations': _paymentAllocations,
    'items': _cart
        .map(
          (line) => <String, dynamic>{
            'variant_id': line.product.variantId,
            'quantity': line.quantity,
            'unit_id': line.unit?.unitId,
            'cutting_charge_applied': line.cuttingChargeApplied,
            'discount': line.discount,
            if (line.serialNumbers.isNotEmpty)
              'serial_numbers': line.serialNumbers,
          },
        )
        .toList(),
    'total': _total,
  };

  void _openHoldEditor() {
    if (_saving) return;
    if (!_validateCart()) {
      setState(() {});
      return;
    }
    _holdLabel.text = _customer?.isWalkIn == false
        ? (_customer?.name ?? '')
        : '';
    setState(() {
      _workspace = _PosWorkspace.hold;
      _step = 0;
      _error = null;
    });
  }

  void _closeHoldEditor() {
    if (_saving) return;
    setState(() {
      _workspace = _PosWorkspace.products;
      _error = null;
    });
    _searchFocus.requestFocus();
  }

  Future<void> _holdSale() async {
    final deviceId = widget.session.device?.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _message('This POS is not activated to a terminal.');
      return;
    }
    if (!_validateCart()) {
      setState(() {});
      return;
    }

    final label = _holdLabel.text.trim();
    setState(() => _saving = true);
    try {
      final result = await _completion.holdSale(
        tenantId: widget.session.business.id,
        deviceId: deviceId,
        customerId: _customerId,
        label: label,
        state: _heldState(),
      );
      if (!mounted) return;
      final code = result['hold_code']?.toString() ?? '';
      _resetSale();
      _holdLabel.clear();
      await _refreshHeldSales(silent: true);
      if (mounted) {
        setState(() => _workspace = _PosWorkspace.products);
      }
      _message(code.isEmpty ? 'Sale held.' : 'Sale held as $code.');
      _searchFocus.requestFocus();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        _message(error.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshHeldSales({bool silent = false}) async {
    final deviceId = widget.session.device?.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    if (mounted) setState(() => _heldLoading = true);
    try {
      final rows = await _completion.heldSales(
        tenantId: widget.session.business.id,
        deviceId: deviceId,
      );
      if (mounted) setState(() => _heldSales = rows);
    } catch (error) {
      if (!silent) _message(error.toString());
    } finally {
      if (mounted) setState(() => _heldLoading = false);
    }
  }

  Future<void> _resumeSale() async {
    if (_cart.isNotEmpty) {
      _message(
        'Hold or clear the current sale before resuming another invoice.',
      );
      return;
    }
    setState(() {
      _workspace = _PosWorkspace.heldInvoices;
      _step = 0;
      _error = null;
    });
    await _refreshHeldSales();
  }

  Future<void> _restoreHeldSale(Map<String, dynamic> selected) async {
    final deviceId = widget.session.device?.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    final holdId = selected['id']?.toString() ?? '';
    if (holdId.isEmpty) return;
    try {
      Map<String, dynamic> state = selected['state'] is Map
          ? Map<String, dynamic>.from(selected['state'] as Map)
          : <String, dynamic>{};
      if (state.isEmpty) {
        final held = await _completion.getHeldSale(
          tenantId: widget.session.business.id,
          deviceId: deviceId,
          holdId: holdId,
        );
        state = held['state'] is Map
            ? Map<String, dynamic>.from(held['state'] as Map)
            : <String, dynamic>{};
      }
      final itemRows = (state['items'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final restored = <_PosLine>[];
      final missing = <String>[];
      for (final item in itemRows) {
        final variantId = item['variant_id']?.toString() ?? '';
        final product = _productByVariantId[variantId];
        if (product == null) {
          missing.add(variantId);
          continue;
        }
        final line = _PosLine(product: product);
        line.quantity =
            (item['quantity'] as num?)?.toDouble() ??
            double.tryParse('${item['quantity']}') ??
            1.0;
        final heldUnitId = item['unit_id']?.toString();
        if (heldUnitId != null && heldUnitId.isNotEmpty) {
          for (final option in product.saleUnits) {
            if (option.unitId == heldUnitId) {
              line.unit = option;
              break;
            }
          }
        }
        line.cuttingChargeApplied = item['cutting_charge_applied'] == true;
        line.discount =
            (item['discount'] as num?)?.toDouble() ??
            double.tryParse('${item['discount']}') ??
            0.0;
        if (item['serial_numbers'] is List) {
          line.serialNumbers
            ..clear()
            ..addAll((item['serial_numbers'] as List).map((e) => e.toString()));
          if (product.trackingMode == 'serial') {
            line.quantity = line.serialNumbers.length.toDouble();
          }
        }
        restored.add(line);
      }
      if (restored.isEmpty) {
        throw Exception(
          'Held sale could not be restored because its products are no longer available.',
        );
      }
      if (!mounted) return;
      setState(() {
        _cart
          ..clear()
          ..addAll(restored);
        _invalidateTotals();
        final customerId = state['customer_id']?.toString();
        if (customerId != null &&
            _customers.any((row) => row.id == customerId)) {
          _customerId = customerId;
        }
        _orderMode = state['order_mode']?.toString() ?? 'counter';
        _orderDiscount.text = state['order_discount']?.toString() ?? '0.00';
        _roundOff.text = state['round_off']?.toString() ?? '0.00';
        _notes.text = state['notes']?.toString() ?? '';
        _paymentMethod = state['payment_method']?.toString() ?? 'cash';
        _tendered.text = state['tendered']?.toString() ?? '';
        _paymentReference.text = state['payment_reference']?.toString() ?? '';
        _paymentAllocations =
            (state['payment_allocations'] as List? ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        _selectedProduct = restored.first.product;
        _step = 0;
        _error = null;
        _workspace = _PosWorkspace.products;
        _checkoutRequestId = null;
      });
      if (_tendered.text.trim().isEmpty) _syncTendered();
      await _completion.deleteHeldSale(
        tenantId: widget.session.business.id,
        deviceId: deviceId,
        holdId: holdId,
      );
      await _refreshHeldSales(silent: true);
      _message(
        missing.isEmpty
            ? 'Held sale restored. Continue billing normally.'
            : 'Sale restored. ${missing.length} unavailable item(s) were skipped.',
      );
      _searchFocus.requestFocus();
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _openCustomerAccount() async {
    if (_customer == null || _customer!.isWalkIn) {
      await _chooseCustomer();
    }
    final customer = _customer;
    if (!mounted || customer == null || customer.isWalkIn) {
      _message('Choose a named customer to receive an account payment.');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerAccountDialog(
        tenantId: widget.session.business.id,
        customerId: customer.id,
        customerName: customer.name,
        currencyCode: widget.session.currencyCode,
        locationId: widget.session.device?.locationId,
        deviceId: widget.session.device?.deviceId,
        canReceive:
            widget.session.hasRole('owner') ||
            widget.session.hasPermission('payments.receive') ||
            widget.session.hasPermission('sales.manage'),
      ),
    );
  }

  Future<void> _autoPrintCompletedSale({
    required String saleId,
    required SaleDetail detail,
    required bool cashPayment,
    bool forcePrint = false,
  }) async {
    final deviceId = widget.session.device?.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    final profiles = await _completion.printerProfiles(
      tenantId: widget.session.business.id,
      deviceId: deviceId,
    );
    Map<String, dynamic>? profile;
    for (final row in profiles) {
      if (row['purpose']?.toString() == 'invoice' &&
          row['active'] != false &&
          (forcePrint || row['auto_print'] == true) &&
          row['is_default'] == true) {
        profile = row;
        break;
      }
    }
    if (profile == null) {
      for (final row in profiles) {
        if (row['purpose']?.toString() == 'invoice' &&
            row['active'] != false &&
            (forcePrint || row['auto_print'] == true)) {
          profile = row;
          break;
        }
      }
    }
    if (profile == null) return;
    final printerName = profile['printer_name']?.toString().trim() ?? '';
    if (printerName.isEmpty) return;
    final paper = profile['paper_size']?.toString().toLowerCase() ?? '80mm';
    final templatePaper = paper == 'a4' ? 'a4' : '80mm';
    final template = await _invoiceTemplates.getTemplate(
      tenantId: widget.session.business.id,
      paperType: templatePaper,
      locationId: widget.session.device?.locationId,
      deviceId: deviceId,
    );
    final origin = await _invoiceTemplates.getSaleOrigin(
      tenantId: widget.session.business.id,
      saleId: saleId,
    );
    final bytes = await _invoicePdf.build(
      session: widget.session,
      sale: detail,
      paperType: paper,
      template: template,
      origin: origin,
    );
    final copies = ((profile['copies'] as num?)?.toInt() ?? 1).clamp(1, 10);
    for (var i = 0; i < copies; i++) {
      await _hardware.directPrintPdfBytes(
        printerName: printerName,
        bytes: bytes,
        jobName: 'Invoice ${detail.saleNumber}',
      );
    }
    try {
      await _invoiceTemplates.logEvent(
        tenantId: widget.session.business.id,
        saleId: saleId,
        invoiceNumber:
            origin['invoice_number']?.toString() ?? detail.saleNumber,
        templateId: template['id']?.toString(),
        action: 'print',
        deviceId: deviceId,
      );
    } catch (_) {}
    if (cashPayment && profile['cash_drawer_enabled'] == true) {
      await _hardware.openCashDrawer(
        printerName: printerName,
        command: profile['cash_drawer_command']?.toString() ?? 'standard',
      );
    }
  }

  Future<void> _checkout({bool printAfter = false}) async {
    if (!_validateCart() || !_validatePayment()) {
      setState(() {});
      return;
    }
    final customer = _customer!;
    final device = widget.session.device;
    if (device == null) {
      setState(() => _error = 'POS device context is required for billing.');
      return;
    }
    if (device.allowedModules.contains('cashier_shifts') &&
        widget.session.hasModule('cashier_shifts')) {
      var hasShift = false;
      try {
        final shift = await _shiftService.current(
          tenantId: widget.session.business.id,
          deviceId: device.deviceId,
        );
        hasShift = shift != null && shift.isNotEmpty;
        if (hasShift) {
          await _offlineLocal.setMeta(
            'shift:${widget.session.business.id}:${device.deviceId}',
            shift,
          );
        }
      } catch (_) {
        hasShift = await _offlineSync.hasVerifiedOpenShift(widget.session);
      }
      if (!hasShift) {
        setState(
          () => _error =
              'Cashier Shift is enabled. Start a shift while online before offline billing.',
        );
        return;
      }
    }

    // ignore: unused_local_variable
    final payment = _appliedPayment;
    final outstanding = _accountBalance;
    final now = DateTime.now();
    final due = outstanding > 0.005 ? now.add(const Duration(days: 30)) : null;
    final change = _change;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _checkoutRequestId ??= const Uuid().v4();
      final requestId = _checkoutRequestId!;
      final payload = <String, dynamic>{
        'customer_id': customer.id,
        'customer_name': customer.name,
        'sale_date': now.toIso8601String().split('T').first,
        'sale_time': now.toUtc().toIso8601String(),
        'due_date': due?.toIso8601String().split('T').first,
        'items': _cart
            .map(
              (line) => <String, dynamic>{
                'variant_id': line.product.variantId,
                'product_name': line.product.productName,
                'sku': line.product.sku,
                'quantity': line.quantity,
                'unit_id': line.unit?.unitId,
                'unit_code': line.unitCode,
                'unit_price': line.unitPrice,
                'discount_amount': _effectiveLineDiscount(line),
                'tax_rate': line.product.taxRate,
                'conversion_to_base': line.conversionToBase,
                'base_quantity': line.baseQuantity,
                if (line.serialNumbers.isNotEmpty)
                  'serial_numbers': List<String>.from(line.serialNumbers),
              },
            )
            .toList(),
        'payment_allocations': _paymentAllocations,
        'notes': [
          'POS • ${_orderMode.replaceAll('_', ' ')}',
          if (_notes.text.trim().isNotEmpty) _notes.text.trim(),
        ].join(' • '),
        'total': _total,
        'outstanding': outstanding,
      };

      final localNumber = await _offlineLocal.queueSale(
        requestId: requestId,
        tenantId: widget.session.business.id,
        locationId: device.locationId,
        deviceId: device.deviceId,
        payload: payload,
        printRequested: printAfter,
      );

      try {
        await _offlineSync.syncPending(
          widget.session,
          onlyRequestId: requestId,
        );
      } catch (_) {
        // The durable local queue is the source of truth during a network outage.
      }
      final record = await _offlineLocal.invoice(requestId);
      if (record == null) {
        throw StateError('Offline invoice queue record could not be reloaded.');
      }

      String? printWarning;
      String completedNumber = localNumber;
      if (record.status == 'synced') {
        _offlineMode = false;
        final result = record.serverResponse ?? const <String, dynamic>{};
        final saleNumber =
            result['sale_number']?.toString() ??
            result['number']?.toString() ??
            '';
        completedNumber = saleNumber.isEmpty ? localNumber : saleNumber;
        String? saleId = result['sale_id']?.toString();
        if ((saleId == null || saleId.isEmpty) && saleNumber.isNotEmpty) {
          try {
            saleId = await _sales.resolveSaleId(
              tenantId: widget.session.business.id,
              saleNumber: saleNumber,
            );
          } catch (_) {}
        }
        SaleDetail? detail;
        if (saleId != null && saleId.isNotEmpty) {
          try {
            detail = await _sales.getSaleDetail(
              tenantId: widget.session.business.id,
              saleId: saleId,
            );
          } catch (_) {}
        }
        if (printAfter &&
            saleId != null &&
            saleId.isNotEmpty &&
            detail != null) {
          try {
            await _autoPrintCompletedSale(
              saleId: saleId,
              detail: detail,
              cashPayment: _paymentAllocations.any(
                (entry) => entry['method_code']?.toString() == 'cash',
              ),
              forcePrint: true,
            );
          } catch (error) {
            printWarning = error.toString();
          }
        }
      } else if (record.status == 'pending' || record.status == 'error') {
        _offlineMode = true;
        if (printAfter) {
          try {
            printWarning = await _offlineReceipt.printQueuedReceipt(
              session: widget.session,
              localInvoiceNumber: localNumber,
              payload: record.payload,
            );
          } catch (error) {
            printWarning = error.toString();
          }
        }
      }

      if (!mounted) return;
      final status = record.status;
      _resetSale();
      if (status == 'synced') {
        _message(
          '$completedNumber synchronized${printWarning != null ? ' • Print: $printWarning' : ''}${change > 0 ? ' • Change ${_money(change)}' : ''}${outstanding > 0.005 ? ' • ${_money(outstanding)} added to ${customer.name} account' : ''}.',
        );
        try {
          await _load();
        } catch (_) {}
      } else if (status == 'conflict') {
        _message(
          '$localNumber saved locally but needs attention: ${record.conflictCode ?? 'CONFLICT'} • ${record.conflictMessage ?? 'Open Offline Sync.'}',
        );
        final catalogue = await _offlineSync.cachedCatalogue(widget.session);
        if (mounted) {
          _rebuildCatalogueCaches(catalogue.products, catalogue.customers);
          setState(() {
            _products = catalogue.products;
            _customers = catalogue.customers;
          });
        }
      } else {
        _message(
          '$localNumber saved offline and queued for automatic sync${printWarning != null ? ' • Print: $printWarning' : ''}.',
        );
        final catalogue = await _offlineSync.cachedCatalogue(widget.session);
        if (mounted) {
          _rebuildCatalogueCaches(catalogue.products, catalogue.customers);
          setState(() {
            _products = catalogue.products;
            _customers = catalogue.customers;
          });
        }
      }
      _searchFocus.requestFocus();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetSale() {
    setState(() {
      _cart.clear();
      _invalidateTotals();
      _checkoutRequestId = null;
      _selectedProduct = null;
      _search.clear();
      _category = 'All';
      _sort = 'name';
      _step = 0;
      _paymentReference.clear();
      _orderDiscount.text = '0.00';
      _roundOff.text = '0.00';
      _notes.clear();
      _tendered.clear();
      _paymentMethod =
          widget.session
              .setting('pos.default_payment_method', 'cash')
              ?.toString() ??
          'cash';
      for (final customer in _customers) {
        if (customer.isWalkIn) {
          _customerId = customer.id;
          break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          _header(),
          if (_error != null) ...[
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 34),
              padding: const EdgeInsets.fromLTRB(9, 4, 4, 4),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.error.withValues(alpha: .18)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _error = null),
                    icon: const Icon(Icons.close, size: 15),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 5),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              child: switch (_step) {
                0 => _productStep(),
                1 => _paymentStep(),
                _ => _reviewStep(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final veryCompact = constraints.maxWidth < 700;

          return Row(
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
              SizedBox(
                width: veryCompact ? 125 : 205,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Billing',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${widget.session.device?.locationCode ?? ''} | '
                      '${widget.session.device?.deviceCode ?? ''} | '
                      '${widget.session.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.6,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (!veryCompact) ...[
                _StepBadge(
                  number: 1,
                  label: compact ? '' : 'Products',
                  active: _step >= 0,
                ),
                const _StepLine(),
                _StepBadge(
                  number: 2,
                  label: compact ? '' : 'Pay',
                  active: _step >= 1,
                ),
                const _StepLine(),
                _StepBadge(
                  number: 3,
                  label: compact ? '' : 'Confirm',
                  active: _step >= 2,
                ),
              ],
              const Spacer(),
              _billingStatusPill(),
              if (_step == 0) ...[
                const SizedBox(width: 4),
                if (compact)
                  IconButton(
                    tooltip: 'Hold invoice',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        _cart.isEmpty ||
                            _saving ||
                            _workspace == _PosWorkspace.hold
                        ? null
                        : _openHoldEditor,
                    icon: const Icon(Icons.pause_circle_outline, size: 17),
                  )
                else
                  OutlinedButton.icon(
                    onPressed:
                        _cart.isEmpty ||
                            _saving ||
                            _workspace == _PosWorkspace.hold
                        ? null
                        : _openHoldEditor,
                    icon: const Icon(Icons.pause_circle_outline, size: 15),
                    label: const Text('Hold'),
                  ),
                const SizedBox(width: 3),
                if (compact)
                  IconButton(
                    tooltip: 'Resume held invoice',
                    visualDensity: VisualDensity.compact,
                    onPressed: _saving ? null : _resumeSale,
                    icon: const Icon(Icons.play_circle_outline, size: 17),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _resumeSale,
                    icon: const Icon(Icons.play_circle_outline, size: 15),
                    label: const Text('Resume'),
                  ),
              ],
              IconButton(
                tooltip: 'Focus barcode / product search',
                visualDensity: VisualDensity.compact,
                onPressed: () => _searchFocus.requestFocus(),
                icon: const Icon(Icons.qr_code_scanner, size: 17),
              ),
              IconButton(
                tooltip: 'Reload products and customers',
                visualDensity: VisualDensity.compact,
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 17),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _billingStatusPill() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: _offlineMode
            ? scheme.errorContainer.withValues(alpha: .55)
            : scheme.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _offlineMode ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
            size: 13,
            color: _offlineMode
                ? scheme.onErrorContainer
                : scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            _offlineMode ? 'OFFLINE' : 'ONLINE',
            style: TextStyle(
              fontSize: 9.1,
              fontWeight: FontWeight.w900,
              color: _offlineMode
                  ? scheme.onErrorContainer
                  : scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _productWorkspace() {
    // POS sub-workflows stay inside the center workspace so the shell and cart
    // remain mounted. Future billing editors should follow this pattern.
    return switch (_workspace) {
      _PosWorkspace.hold => _holdSalePage(),
      _PosWorkspace.heldInvoices => _heldSalesPage(),
      _PosWorkspace.quantity => _quantityEditorPage(),
      _PosWorkspace.products => _catalog(),
    };
  }

  Widget _productStep() {
    return LayoutBuilder(
      key: const ValueKey('products'),
      builder: (context, constraints) {
        final design = UiDesignScope.of(context, appKey: 'pos');
        final stacked = constraints.maxWidth < 900;

        if (stacked) {
          final cartHeight = constraints.maxHeight < 560 ? 250.0 : 285.0;
          return Column(
            children: [
              Expanded(child: _productWorkspace()),
              const SizedBox(height: 5),
              SizedBox(height: cartHeight, child: _cartPanel()),
            ],
          );
        }

        final cartWidth = design.posCartWidth.clamp(380.0, 455.0).toDouble();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _productWorkspace()),
            const SizedBox(width: 5),
            SizedBox(width: cartWidth, child: _cartPanel()),
          ],
        );
      },
    );
  }

  Widget _holdSalePage() {
    return Padding(
      key: const ValueKey('hold-sale'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Back to products',
                onPressed: _saving ? null : _closeHoldEditor,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hold Current Invoice',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Save this cart temporarily and return to Products.',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.pause_circle_outline),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                '${_cart.length} item(s) • ${_money(_total)}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _customer?.isWalkIn == false
                              ? 'Customer: ${_customer?.name ?? ''}'
                              : 'Walk-in customer',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _holdLabel,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_saving) _holdSale();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Reference / customer name (optional)',
                            hintText: 'Example: Counter 2 / Mr. Ali',
                            helperText:
                                'References may repeat. THQ generates a unique hold number.',
                          ),
                        ),
                        if (_error != null && _error!.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _saving ? null : _holdSale,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.pause_circle_outline),
                              label: Text(
                                _saving ? 'Holding…' : 'Hold Invoice',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _saving ? null : _closeHoldEditor,
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantityEditorPage() {
    final line = _editingLine;
    if (line == null || !_cart.contains(line)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _workspace = _PosWorkspace.products);
      });
      return const SizedBox.shrink();
    }
    final units = line.product.saleUnits.isEmpty
        ? <ProductUnitOption>[]
        : line.product.saleUnits.where((u) => u.allowSale && u.active).toList();
    return Padding(
      key: const ValueKey('quantity-editor'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Back to products',
                onPressed: () => setState(() {
                  _editingLine = null;
                  _workspace = _PosWorkspace.products;
                }),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.product.productName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Quantity & unit • Stock ${_formatStock(line.product.stockQuantity, line.product.baseUnitCode)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (units.length > 1) ...[
                        const Text(
                          'Sale Unit',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: units
                              .map(
                                (u) => ChoiceChip(
                                  label: Text('${u.name} (${u.code})'),
                                  selected: line.unit?.unitId == u.unitId,
                                  onSelected: (_) => _setLineUnit(line, u),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 18),
                      ],
                      Text(
                        'Quantity in ${line.unitCode}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filledTonal(
                            onPressed: () =>
                                _changeQuantity(line, -line.quantityStep),
                            icon: const Icon(Icons.remove),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 160,
                            child: TextFormField(
                              key: ValueKey(
                                'qty-${line.product.variantId}-${line.unitCode}-${line.quantity}',
                              ),
                              initialValue: line.displayQuantity,
                              textAlign: TextAlign.center,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                suffixText: line.unitCode,
                              ),
                              onFieldSubmitted: (value) {
                                final parsed = double.tryParse(value.trim());
                                if (parsed == null || parsed <= 0) {
                                  _message(
                                    'Enter a quantity greater than zero.',
                                  );
                                  return;
                                }
                                final unit = line.unit;
                                if (unit != null &&
                                    !unit.acceptsQuantity(parsed)) {
                                  _message(
                                    unit.allowFractional
                                        ? '${line.unitCode} quantity must use increments of ${unit.quantityStep}.'
                                        : '${line.unitCode} only allows whole quantities in increments of ${unit.quantityStep}.',
                                  );
                                  return;
                                }
                                if (line.product.itemType == 'stock' &&
                                    parsed * line.conversionToBase >
                                        line.product.stockQuantity + 0.000001) {
                                  _message(
                                    'Only ${_formatStock(line.product.stockQuantity, line.product.baseUnitCode)} available.',
                                  );
                                  return;
                                }
                                setState(() {
                                  line.quantity = parsed;
                                  _syncTendered();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filledTonal(
                            onPressed: () =>
                                _changeQuantity(line, line.quantityStep),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Base stock impact: ${_formatStock(line.baseQuantity, line.product.baseUnitCode)}',
                      ),
                      Text('Unit price: ${_money(line.unitPrice)}'),
                      if ((line.unit?.cuttingAllowed ?? false) &&
                          (line.unit?.cuttingCharge ?? 0) > 0) ...[
                        const SizedBox(height: 12),
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.info_outline),
                          title: Text(
                            'Use a GST-classified Service product for cutting charges',
                          ),
                          subtitle: Text(
                            'Build 30 no longer posts unclassified line charges.',
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: () => setState(() {
                              _editingLine = null;
                              _workspace = _PosWorkspace.products;
                            }),
                            icon: const Icon(Icons.check),
                            label: const Text('Done'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _changeQuantity(line, -line.quantity),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Remove Item'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heldSalesPage() {
    return Padding(
      key: const ValueKey('held-invoices'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Back to products',
                onPressed: () {
                  setState(() => _workspace = _PosWorkspace.products);
                  _searchFocus.requestFocus();
                },
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Held Invoices (${_heldSales.length})',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select an invoice to restore it and continue billing.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _heldLoading ? null : () => _refreshHeldSales(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 6),
              FilledButton.tonalIcon(
                onPressed: () {
                  setState(() => _workspace = _PosWorkspace.products);
                  _searchFocus.requestFocus();
                },
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Products'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_heldLoading) const LinearProgressIndicator(),
          if (_heldLoading) const SizedBox(height: 10),
          Expanded(
            child: _heldLoading && _heldSales.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _heldSales.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pause_circle_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No held invoices',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Hold a sale first, then use Resume to continue it here.',
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1250
                          ? 5
                          : constraints.maxWidth >= 980
                          ? 4
                          : constraints.maxWidth >= 700
                          ? 3
                          : constraints.maxWidth >= 460
                          ? 2
                          : 1;
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: columns == 1 ? 2.9 : 1.65,
                        ),
                        itemCount: _heldSales.length,
                        itemBuilder: (context, index) {
                          final row = _heldSales[index];
                          final total =
                              (row['total'] as num?)?.toDouble() ??
                              double.tryParse('${row['total']}') ??
                              0.0;
                          final created = DateTime.tryParse(
                            '${row['created_at']}',
                          )?.toLocal();
                          final createdLabel = created == null
                              ? ''
                              : '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
                          final code =
                              row['hold_code']?.toString().trim() ?? '';
                          final label = row['label']?.toString().trim() ?? '';
                          final customer =
                              row['customer_name']?.toString().trim() ?? '';
                          return Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _restoreHeldSale(row),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.pause_circle_filled_outlined,
                                          size: 19,
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Text(
                                            code.isEmpty
                                                ? 'Held Invoice'
                                                : code,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        if (createdLabel.isNotEmpty)
                                          Text(
                                            createdLabel,
                                            style: const TextStyle(
                                              fontSize: 11.8,
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (label.isNotEmpty) ...[
                                      const SizedBox(height: 7),
                                      Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 5),
                                    Text(
                                      customer.isEmpty
                                          ? 'Walk-in customer'
                                          : customer,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        Text(
                                          '${row['item_count'] ?? 0} item(s)',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _money(total),
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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

  Widget _catalog() {
    final products = _filteredProducts;
    final scheme = Theme.of(context).colorScheme;
    final design = UiDesignScope.of(context, appKey: 'pos');

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 0, 0),
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 760;

                final search = TextField(
                  controller: _search,
                  focusNode: _searchFocus,
                  autofocus: true,
                  onChanged: _searchChanged,
                  onSubmitted: _searchSubmitted,
                  decoration: const InputDecoration(
                    hintText: 'Product, SKU, barcode, QR or code...',
                    prefixIcon: Icon(Icons.search, size: 17),
                  ),
                );

                final category = DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _category = value);
                    }
                  },
                );

                final sort = DropdownButtonFormField<String>(
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sort'),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Name A-Z')),
                    DropdownMenuItem(
                      value: 'category',
                      child: Text('Category'),
                    ),
                    DropdownMenuItem(
                      value: 'price_low',
                      child: Text('Price low-high'),
                    ),
                    DropdownMenuItem(
                      value: 'price_high',
                      child: Text('Price high-low'),
                    ),
                    DropdownMenuItem(
                      value: 'stock_high',
                      child: Text('Stock high-low'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _sort = value);
                    }
                  },
                );

                final customer = InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _chooseCustomer,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _customer?.name ?? 'Customer',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Icon(Icons.expand_more, size: 15),
                      ],
                    ),
                  ),
                );

                if (narrow) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: search),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'Customer account',
                            visualDensity: VisualDensity.compact,
                            onPressed: _openCustomerAccount,
                            icon: const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(child: category),
                          const SizedBox(width: 4),
                          Expanded(child: sort),
                          const SizedBox(width: 4),
                          Expanded(flex: 2, child: customer),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 5, child: search),
                    const SizedBox(width: 4),
                    SizedBox(width: 145, child: category),
                    const SizedBox(width: 4),
                    SizedBox(width: 145, child: sort),
                    const SizedBox(width: 4),
                    SizedBox(width: 185, child: customer),
                    const SizedBox(width: 3),
                    IconButton.filledTonal(
                      tooltip: 'Customer balance / receive payment',
                      visualDensity: VisualDensity.compact,
                      onPressed: _openCustomerAccount,
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 16,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_restaurantAvailable) ...[
            const SizedBox(height: 4),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Text(
                    'Order',
                    style: TextStyle(
                      fontSize: 9.8,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  for (final mode in const [
                    'counter',
                    'takeaway',
                    'delivery',
                  ]) ...[
                    ChoiceChip(
                      selected: _orderMode == mode,
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        mode[0].toUpperCase() + mode.substring(1),
                        style: const TextStyle(fontSize: 8.5),
                      ),
                      onSelected: (_) => setState(() => _orderMode = mode),
                    ),
                    const SizedBox(width: 4),
                  ],
                  const Spacer(),
                  Text(
                    'Dine-in / KOT: Restaurant',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_selectedProduct != null) ...[
            const SizedBox(height: 4),
            _selectedProductStrip(_selectedProduct!),
          ],
          const SizedBox(height: 4),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('No products match this search.'))
                : GridView.builder(
                    padding: const EdgeInsets.only(right: 2),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: design.posLayout == 'compact_grid'
                          ? 165
                          : design.posLayout == 'touch_grid'
                          ? 235
                          : 205,
                      mainAxisExtent: design.posLayout == 'compact_grid'
                          ? 98
                          : design.posLayout == 'touch_grid'
                          ? 136
                          : 118,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) =>
                        _productCard(products[index], design),
                  ),
          ),
          SizedBox(
            height: 20,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${products.length} matching products',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedProductStrip(InventoryProduct product) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${product.productName} | SKU ${product.sku}'
              '${(product.partNumber ?? '').isNotEmpty ? ' | Part ${product.partNumber}' : ''}'
              '${(product.brandName ?? '').isNotEmpty ? ' | ${product.brandName}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Stock ${_formatStock(product.stockQuantity, product.baseUnitCode)}',
            style: const TextStyle(fontSize: 8.5),
          ),
          const SizedBox(width: 8),
          Text(
            _money(product.sellingPrice),
            style: const TextStyle(fontSize: 10.3, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _productCard(InventoryProduct product, UiDesignProfile design) {
    final scheme = Theme.of(context).colorScheme;
    final outOfStock =
        product.itemType == 'stock' && product.stockQuantity <= 0;

    return Material(
      color: design.surface,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: outOfStock ? null : () => _add(product),
        onLongPress: () => setState(() => _selectedProduct = product),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            border: Border.all(color: design.border),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.categoryName ?? 'Product',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.1,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    product.itemType == 'stock'
                        ? _formatStock(
                            product.stockQuantity,
                            product.baseUnitCode,
                          )
                        : product.itemType,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.1,
                      fontWeight: FontWeight.w700,
                      color: outOfStock ? scheme.error : scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                product.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
              const Spacer(),
              Text(
                'SKU ${product.sku}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 8.9, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _money(product.sellingPrice),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    outOfStock ? Icons.block : Icons.add_circle,
                    size: 17,
                    color: outOfStock ? scheme.error : scheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartPanel() {
    final design = UiDesignScope.of(context, appKey: 'pos');
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: design.surface,
        border: Border.all(color: design.border),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.fromLTRB(9, 0, 4, 0),
            color: scheme.surfaceContainerHighest.withValues(alpha: .42),
            child: Row(
              children: [
                const Icon(Icons.shopping_basket_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Cart | ${_cart.length} ${_cart.length == 1 ? 'item' : 'items'}',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (_cart.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear cart',
                    visualDensity: VisualDensity.compact,
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _cart.clear();
                            _syncTendered();
                          }),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_basket_outlined,
                          size: 30,
                          color: scheme.outline,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Scan, search or tap a product',
                          style: TextStyle(
                            fontSize: 10.3,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    itemCount: _cart.length,
                    itemBuilder: (context, index) => _cartLine(_cart[index]),
                  ),
          ),
          _totals(),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 5, 7, 7),
            child: SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton.icon(
                onPressed: _cart.isEmpty || _saving ? null : _next,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text('Payment  ${_money(_total)}', maxLines: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartLine(_PosLine line) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${line.product.sku} | '
                  '${_money(line.unitPrice)}/${line.unitCode}'
                  '${line.pricingSource == null ? '' : ' | ${line.pricingSource}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Decrease quantity',
            constraints: const BoxConstraints.tightFor(width: 27, height: 27),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: _saving
                ? null
                : () => _changeQuantity(line, -line.quantityStep),
            icon: const Icon(Icons.remove_circle_outline, size: 16),
          ),
          SizedBox(
            width: 50,
            child: TextButton(
              onPressed: _saving ? null : () => _openQuantityEditor(line),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
              ),
              child: Text(
                '${line.displayQuantity} ${line.unitCode}',
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 9.8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase quantity',
            constraints: const BoxConstraints.tightFor(width: 27, height: 27),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: _saving
                ? null
                : () => _changeQuantity(line, line.quantityStep),
            icon: const Icon(Icons.add_circle_outline, size: 16),
          ),
          SizedBox(
            width: 72,
            child: Text(
              _money(_lineGross(line)),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove item',
            constraints: const BoxConstraints.tightFor(width: 27, height: 27),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: _saving
                ? null
                : () => _changeQuantity(line, -line.quantity),
            icon: const Icon(Icons.close, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _totals() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .20),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          _totalRow('Subtotal', _subtotal),
          if (_discount > 0) _totalRow('Discount', -_discount),
          _totalRow('Tax', _tax),
          if (_roundOffAmount.abs() > 0.000001)
            _totalRow('Round Off', _roundOffAmount),
          const SizedBox(height: 2),
          _totalRow('Total', _total, strong: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool strong = false}) {
    return SizedBox(
      height: strong ? 25 : 19,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 10 : 8.5,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            _money(value),
            maxLines: 1,
            style: TextStyle(
              fontSize: strong ? 13 : 9,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentStep() {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      key: const ValueKey('payment'),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;

          final controls = Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: _paymentControls(),
            ),
          );

          final details = Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: _paymentDetails(),
          );

          return Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to products',
                      visualDensity: VisualDensity.compact,
                      onPressed: _saving ? null : _back,
                      icon: const Icon(Icons.arrow_back, size: 16),
                    ),
                    const SizedBox(width: 3),
                    const Expanded(
                      child: Text(
                        'Payment',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${_cart.length} items',
                      style: TextStyle(
                        fontSize: 9.8,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _money(_total),
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Expanded(
                child: stacked
                    ? Column(
                        children: [
                          Expanded(child: controls),
                          const SizedBox(height: 5),
                          Expanded(child: details),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 6, child: controls),
                          const SizedBox(width: 5),
                          Expanded(flex: 4, child: details),
                        ],
                      ),
              ),
              const SizedBox(height: 5),
              _paymentActionBar(),
            ],
          );
        },
      ),
    );
  }

  Widget _paymentActionBar() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 650;

          if (narrow) {
            return Row(
              children: [
                IconButton(
                  tooltip: 'Products',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving ? null : _back,
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                ),
                IconButton(
                  tooltip: 'Review invoice',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving
                      ? null
                      : () {
                          if (_validateCart() && _validatePayment()) {
                            setState(() {
                              _error = null;
                              _step = 2;
                            });
                          } else {
                            setState(() {});
                          }
                        },
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: _saving
                      ? null
                      : () => _checkout(printAfter: false),
                  child: const Text('Confirm'),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _checkout(printAfter: true),
                  icon: const Icon(Icons.print_outlined, size: 15),
                  label: const Text('Print'),
                ),
              ],
            );
          }

          return Row(
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _back,
                icon: const Icon(Icons.inventory_2_outlined, size: 15),
                label: const Text('Products'),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        if (_validateCart() && _validatePayment()) {
                          setState(() {
                            _error = null;
                            _step = 2;
                          });
                        } else {
                          setState(() {});
                        }
                      },
                icon: const Icon(Icons.visibility_outlined, size: 15),
                label: const Text('View Invoice'),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : () => _checkout(printAfter: false),
                icon: const Icon(Icons.check_circle_outline, size: 15),
                label: const Text('Just Confirm'),
              ),
              const SizedBox(width: 5),
              FilledButton.icon(
                onPressed: _saving ? null : () => _checkout(printAfter: true),
                icon: const Icon(Icons.print_outlined, size: 15),
                label: const Text('Print & Confirm'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _paymentControls() {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.payments_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            const Text(
              'Payment Allocation',
              style: TextStyle(fontSize: 11.8, fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            Text(
              _customer?.name ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.8, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _orderDiscount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Invoice Discount',
            prefixIcon: Icon(Icons.discount_outlined, size: 17),
          ),
          onChanged: (_) => setState(_syncTendered),
        ),
        const SizedBox(height: 7),
        MultiPaymentEditor(
          tenantId: widget.session.business.id,
          total: _total,
          customerIsWalkIn: _customer?.isWalkIn ?? true,
          customerName: _customer?.name ?? '',
          initialAllocations: _paymentAllocations,
          enabled: !_saving,
          onChanged: (value) {
            setState(() {
              _paymentAllocations = value;
              if (value.isNotEmpty) {
                _paymentMethod =
                    value.first['method_code']?.toString() ?? 'cash';
                _tendered.text = '${value.first['tendered_amount'] ?? ''}';
                _paymentReference.text =
                    value.first['reference_number']?.toString() ?? '';
              }
              _error = null;
            });
          },
        ),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: .50),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            'Round-off is automatic. GST-classified services must be used for freight, cutting, installation and other charges.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Billing Note (optional)',
            prefixIcon: Icon(Icons.notes_outlined, size: 17),
          ),
        ),
      ],
    );
  }

  Widget _paymentDetails() {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          color: scheme.surfaceContainerHighest.withValues(alpha: .45),
          child: Row(
            children: [
              const Text(
                'SALE SUMMARY',
                style: TextStyle(
                  fontSize: 10.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .35,
                ),
              ),
              const Spacer(),
              Text(
                '${_cart.length} items',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _cart.length,
            itemBuilder: (context, index) {
              final line = _cart[index];

              return Container(
                constraints: const BoxConstraints(minHeight: 39),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${line.product.productName} x '
                        '${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _money(_lineGross(line)),
                      style: const TextStyle(
                        fontSize: 10.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: .16),
            border: Border(
              top: BorderSide(
                color: scheme.primary.withValues(alpha: .24),
                width: 1.25,
              ),
            ),
          ),
          child: Column(
            children: [
              _paymentSummaryRow('Customer', _customer?.name ?? '-'),
              _paymentSummaryRow(
                'Order',
                _orderMode.replaceAll('_', ' ').toUpperCase(),
              ),
              _paymentSummaryRow('Subtotal', _money(_subtotal)),
              _paymentSummaryRow('Discount', '- ${_money(_discount)}'),
              _paymentSummaryRow('Tax', _money(_tax)),
              if (_roundOffAmount.abs() > 0.000001)
                _paymentSummaryRow('Round Off', _money(_roundOffAmount)),
              const Divider(height: 14),
              _paymentSummaryRow(
                'Grand Total',
                _money(_total),
                strong: true,
                highlight: true,
              ),
              const SizedBox(height: 2),
              _paymentSummaryRow(
                'Received',
                _money(_appliedPayment),
                highlight: true,
              ),
              if (_change > 0.005)
                _paymentSummaryRow('Change', _money(_change), strong: true),
              if (_accountBalance > 0.005)
                _paymentSummaryRow(
                  'Account Balance',
                  _money(_accountBalance),
                  strong: true,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentSummaryRow(
    String label,
    String value, {
    bool strong = false,
    bool highlight = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(minHeight: strong ? 32 : 25),
      padding: EdgeInsets.symmetric(
        horizontal: highlight ? 8 : 2,
        vertical: highlight ? 4 : 2,
      ),
      decoration: highlight
          ? BoxDecoration(
              color: scheme.surface.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: scheme.primary.withValues(alpha: .14)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 12.5 : 10.5,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                color: strong ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: strong ? 15 : (highlight ? 12.5 : 11),
                fontWeight: strong
                    ? FontWeight.w900
                    : (highlight ? FontWeight.w800 : FontWeight.w700),
                color: strong ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      key: const ValueKey('review'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to payment',
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving ? null : _back,
                  icon: const Icon(Icons.arrow_back, size: 16),
                ),
                const SizedBox(width: 3),
                const Expanded(
                  child: Text(
                    'Invoice Review',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  _customer?.name ?? '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.8,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  _money(_total),
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 760;

                final summary = Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  padding: const EdgeInsets.all(9),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _reviewRow('Customer', _customer?.name ?? '-'),
                        _reviewRow(
                          'Order Type',
                          _orderMode.replaceAll('_', ' ').toUpperCase(),
                        ),
                        _reviewRow('Items', '${_cart.length}'),
                        _reviewRow('Subtotal', _money(_subtotal)),
                        _reviewRow('Discount', '- ${_money(_discount)}'),
                        _reviewRow('Tax', _money(_tax)),
                        if (_roundOffAmount.abs() > 0.000001)
                          _reviewRow('Round Off', _money(_roundOffAmount)),
                        const Divider(height: 10),
                        _reviewRow('Grand Total', _money(_total), strong: true),
                        _reviewRow('Payment', _paymentMethod.toUpperCase()),
                        _reviewRow('Amount Received', _money(_appliedPayment)),
                        if (_change > 0.005)
                          _reviewRow('Change', _money(_change), strong: true),
                        if (_accountBalance > 0.005)
                          _reviewRow(
                            'Added to Account',
                            _money(_accountBalance),
                            strong: true,
                          ),
                        if (_paymentReference.text.trim().isNotEmpty)
                          _reviewRow(
                            'Reference',
                            _paymentReference.text.trim(),
                          ),
                      ],
                    ),
                  ),
                );

                final items = Container(
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
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        color: scheme.surfaceContainerHighest,
                        child: const Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text(
                                'Item',
                                style: TextStyle(
                                  fontSize: 10.1,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Qty',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.1,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                'Tax',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10.1,
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
                                  fontSize: 10.1,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: _cart.length,
                          itemBuilder: (context, index) {
                            final line = _cart[index];
                            final net =
                                _lineGross(line) - _effectiveLineDiscount(line);
                            final lineTotal =
                                net + (net * line.product.taxRate / 100);

                            return Container(
                              constraints: const BoxConstraints(minHeight: 42),
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
                                    flex: 5,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          line.product.productName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10.3,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          line.product.sku,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 10.1,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      line.quantity.toStringAsFixed(
                                        line.quantity % 1 == 0 ? 0 : 2,
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 8.5),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${line.product.taxRate.toStringAsFixed(2)}%',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 8.5),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _money(lineTotal),
                                      textAlign: TextAlign.right,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 10.1,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );

                if (stacked) {
                  return Column(
                    children: [
                      Expanded(child: summary),
                      const SizedBox(height: 5),
                      Expanded(child: items),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: summary),
                    const SizedBox(width: 5),
                    Expanded(flex: 6, child: items),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _back,
                  icon: const Icon(Icons.arrow_back, size: 15),
                  label: const Text('Payment'),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _saving
                      ? null
                      : () => _checkout(printAfter: false),
                  icon: const Icon(Icons.check_circle_outline, size: 15),
                  label: Text(_saving ? 'Saving...' : 'Just Confirm'),
                ),
                const SizedBox(width: 5),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _checkout(printAfter: true),
                  icon: const Icon(Icons.print_outlined, size: 15),
                  label: Text(_saving ? 'Saving...' : 'Print & Confirm'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value, {bool strong = false}) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 9.5 : 8.5,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
                color: strong ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: strong ? 12 : 9,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

ProductUnitOption? _preferredPosUnit(InventoryProduct product) {
  if (product.trackingMode == 'serial') {
    for (final unit in product.saleUnits) {
      if (unit.isBase && unit.allowSale && unit.active) return unit;
    }
    for (final unit in product.saleUnits) {
      if ((unit.conversionToBase - 1).abs() <= 0.000001 &&
          unit.allowSale &&
          unit.active) {
        return unit;
      }
    }
  }
  return product.defaultSaleUnit;
}

class _PosTotalsSnapshot {
  const _PosTotalsSnapshot({
    required this.subtotal,
    required this.manualOrderDiscount,
    required this.discount,
    required this.tax,
    required this.beforeRoundOff,
    required this.roundOffAmount,
    required this.total,
  });

  final double subtotal;
  final double manualOrderDiscount;
  final double discount;
  final double tax;
  final double beforeRoundOff;
  final double roundOffAmount;
  final double total;
}

class _PosLine {
  final InventoryProduct product;
  ProductUnitOption? unit;
  double quantity;
  double discount;
  bool cuttingChargeApplied;
  double? resolvedUnitPrice;
  String? pricingSource;
  String? priceListId;
  final List<String> serialNumbers = [];

  _PosLine({required this.product})
    : unit = _preferredPosUnit(product),
      quantity =
          (product.defaultSaleUnit?.quantityStep ?? product.quantityStep) > 1
          ? (product.defaultSaleUnit?.quantityStep ?? product.quantityStep)
          : 1.0,
      discount = 0.0,
      cuttingChargeApplied = false,
      resolvedUnitPrice = null,
      pricingSource = null,
      priceListId = null;

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
  String get displayQuantity {
    final decimals = unit?.decimalPlaces ?? (product.allowFractional ? 3 : 0);
    return quantity.toStringAsFixed(
      quantity % 1 == 0 ? 0 : decimals.clamp(0, 6).toInt(),
    );
  }

  double get appliedCuttingCharge =>
      cuttingChargeApplied ? (unit?.cuttingCharge ?? 0.0) : 0.0;
}

class _StepBadge extends StatelessWidget {
  final int number;
  final String label;
  final bool active;

  const _StepBadge({
    required this.number,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: active
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: active ? Colors.white : null,
          child: Text(
            '$number',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).dividerColor,
    );
  }
}
