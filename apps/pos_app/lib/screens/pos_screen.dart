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
  String _orderMode = 'counter';
  int _step = 0;
  Timer? _searchDebounce;
  Timer? _offlineSyncTimer;
  bool _offlineMode = false;
  bool _offlineHeartbeatBusy = false;

  bool get _canUse =>
      widget.session.hasPermission('pos.use') ||
      widget.session.hasPermission('sales.manage') ||
      widget.session.hasRole('owner');

  bool get _restaurantAvailable =>
      widget.session.hasModule('restaurant') &&
      (widget.session.device?.allowedModules.contains('restaurant') ?? false);

  Customer? get _customer {
    for (final customer in _customers) {
      if (customer.id == _customerId) return customer;
    }
    return null;
  }

  double _lineGross(_PosLine line) => line.quantity * line.unitPrice;

  double get _subtotal => _cart.fold(0.0, (sum, line) => sum + _lineGross(line));

  double get _cuttingCharges =>
      _cart.fold(0.0, (sum, line) => sum + line.appliedCuttingCharge);

  double get _manualOrderDiscount {
    final value = double.tryParse(_orderDiscount.text.trim()) ?? 0.0;
    return value.clamp(0.0, _subtotal).toDouble();
  }

  double _effectiveLineDiscount(_PosLine line) {
    if (_subtotal <= 0) return line.discount;
    final gross = _lineGross(line);
    final allocated = _manualOrderDiscount * (gross / _subtotal);
    return (line.discount + allocated).clamp(0.0, gross).toDouble();
  }

  double get _discount =>
      _cart.fold(0.0, (sum, line) => sum + _effectiveLineDiscount(line));

  double get _tax => _cart.fold(0.0, (sum, line) {
    final taxable = _lineGross(line) - _effectiveLineDiscount(line);
    return sum + (taxable * line.product.taxRate / 100.0);
  });

  double get _roundOffAmount => double.tryParse(_roundOff.text.trim()) ?? 0.0;

  double get _beforeRoundOff => _subtotal - _discount + _tax + _cuttingCharges;

  double get _total => _beforeRoundOff + _roundOffAmount;

  void _applyRoundOff() {
    final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;
    setState(() {
      _roundOff.text = delta.abs() < 0.000001 ? '0.00' : delta.toStringAsFixed(2);
      _syncTendered();
    });
  }

  double get _tenderedAmount => double.tryParse(_tendered.text.trim()) ?? 0.0;

  double get _appliedPayment {
    if (_paymentMethod == 'credit') return 0.0;
    return _tenderedAmount.clamp(0.0, _total).toDouble();
  }

  double get _accountBalance => (_total - _appliedPayment).clamp(0.0, _total).toDouble();

  double get _change => _paymentMethod == 'cash' && _tenderedAmount > _total
      ? _tenderedAmount - _total
      : 0.0;

  List<String> get _categories {
    final values =
        _products
            .map((product) => product.categoryName?.trim() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...values];
  }

  List<InventoryProduct> get _filteredProducts {
    final query = _search.text.trim().toLowerCase();
    final rows = _products.where((product) {
      final categoryMatch =
          _category == 'All' || product.categoryName == _category;
      if (!categoryMatch) return false;
      if (query.isEmpty) return true;
      return product.productName.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          (product.barcode ?? '').toLowerCase().contains(query) ||
          (product.partNumber ?? '').toLowerCase().contains(query) ||
          product.searchCodes.toLowerCase().contains(query) ||
          (product.brandName ?? '').toLowerCase().contains(query) ||
          (product.categoryName ?? '').toLowerCase().contains(query);
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
    return rows;
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
    _offlineSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_offlineHeartbeat()));
  }

  @override
  void dispose() {
    _offlineSyncTimer?.cancel();
    _searchDebounce?.cancel();
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
          throw StateError('POS is offline and no local product/customer cache is available yet. Connect once and refresh the POS before using offline billing. $onlineError');
        }
      }
      final products = catalogue.products
          .where((product) => product.productStatus == 'active' && product.variantStatus == 'active')
          .toList();
      final customers = catalogue.customers.where((customer) => customer.isActive).toList();
      String? selectedCustomer = _customerId;
      if (selectedCustomer == null || !customers.any((customer) => customer.id == selectedCustomer)) {
        for (final customer in customers) {
          if (customer.isWalkIn) {
            selectedCustomer = customer.id;
            break;
          }
        }
        selectedCustomer ??= customers.isEmpty ? null : customers.first.id;
      }
      if (!mounted) return;
      setState(() {
        _products = products;
        _customers = customers;
        _customerId = selectedCustomer;
        _offlineMode = offline;
        if (!_categories.contains(_category)) _category = 'All';
      });
      if (!offline) {
        try { await _refreshHeldSales(silent: true); } catch (_) {}
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _offlineHeartbeat() async {
    if (_offlineHeartbeatBusy || _saving || !mounted || widget.session.device == null) return;
    _offlineHeartbeatBusy = true;
    try {
      final result = await _offlineSync.syncPending(widget.session);
      if (result.synced > 0 || _offlineMode) {
        final catalogue = await _offlineSync.refreshCatalogue(widget.session);
        if (!mounted) return;
        final products = catalogue.products.where((p) => p.productStatus == 'active' && p.variantStatus == 'active').toList();
        final customers = catalogue.customers.where((c) => c.isActive).toList();
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
        if (product.itemType != 'stock' || next * line.conversionToBase <= product.stockQuantity + 0.000001) {
          line.quantity = next;
          line.resolvedUnitPrice = null;
          changedLine = line;
        } else {
          _message('Only ${_formatStock(product.stockQuantity, product.baseUnitCode)} available.');
        }
      } else {
        final line = _PosLine(product: product);
        if (product.itemType != 'stock' || line.baseQuantity <= product.stockQuantity + 0.000001) {
          _cart.add(line);
          changedLine = line;
        } else {
          _message('Only ${_formatStock(product.stockQuantity, product.baseUnitCode)} available.');
        }
      }
      _syncTendered();
    });
    if (changedLine != null) unawaited(_resolveLinePrice(changedLine!));
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

  Future<void> _addSerialByCode(InventoryProduct product, String serialNumber) async {
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
        _message('Serial $serialNumber is not available at this POS store or offline cache.');
        return;
      }
      if (resolved['variant_id']?.toString() != product.variantId) {
        _message('Serial $serialNumber belongs to a different product.');
        return;
      }
      _addResolvedSerial(product, resolved['serial_number']?.toString() ?? serialNumber);
    } catch (error) {
      _message(error.toString());
    }
  }

  void _addResolvedSerial(InventoryProduct product, String serialNumber) {
    final normalized = serialNumber.trim().toLowerCase();
    if (_cart.any((line) => line.serialNumbers.any((value) => value.trim().toLowerCase() == normalized))) {
      _message('Serial $serialNumber is already in this invoice.');
      return;
    }
    var index = _cart.indexWhere((line) => line.product.variantId == product.variantId);
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
    unawaited(_resolveLinePrice(_cart[index]));
    _searchFocus.requestFocus();
  }

  String _formatStock(double value, String unitCode) =>
      '${value.toStringAsFixed(value % 1 == 0 ? 0 : 3)} $unitCode';

  void _changeQuantity(_PosLine line, double delta) {
    if (line.product.trackingMode == 'serial') {
      _message('Serial-tracked quantity is controlled by scanned serial numbers. Remove the line and rescan if needed.');
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
          next * line.conversionToBase <= line.product.stockQuantity + 0.000001) {
        line.quantity = next;
        line.resolvedUnitPrice = null;
      } else {
        _message('Only ${_formatStock(line.product.stockQuantity, line.product.baseUnitCode)} available.');
      }
      _syncTendered();
    });
    if (_cart.contains(line)) unawaited(_resolveLinePrice(line));
  }

  void _openQuantityEditor(_PosLine line) {
    if (_saving) return;
    if (line.product.trackingMode == 'serial') {
      _message('Serial-tracked quantity is controlled by scanned serial numbers.');
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
    if (line.product.itemType == 'stock' && newBase > line.product.stockQuantity + 0.000001) {
      _message('Only ${_formatStock(line.product.stockQuantity, line.product.baseUnitCode)} available.');
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
      _message('Quantity reset to ${line.displayQuantity} ${unit.code} for this unit.');
    }
    unawaited(_resolveLinePrice(line));
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
      _message('Pricing refresh failed for ${line.product.productName}: $error');
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
    InventoryProduct? exact;
    for (final product in _products) {
      if (product.sku.toLowerCase() == query ||
          (product.barcode ?? '').toLowerCase() == query ||
          (product.partNumber ?? '').toLowerCase() == query ||
          product.identifiers.any((identifier) => identifier.active && identifier.code.toLowerCase() == query)) {
        exact = product;
        break;
      }
    }
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
        InventoryProduct? product;
        for (final row in _products) {
          if (row.variantId == variantId) { product = row; break; }
        }
        if (product != null) {
          _addResolvedSerial(product, serial['serial_number']?.toString() ?? raw);
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
    if (_paymentMethod != 'cash') {
      _tendered.text = _paymentMethod == 'credit'
          ? '0.00'
          : _total.toStringAsFixed(2);
    }
  }

  void _cashExact() =>
      setState(() => _tendered.text = _total.toStringAsFixed(2));

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
        _error = '${line.product.productName}: scan exactly ${line.baseQuantity.toStringAsFixed(0)} serial number(s).';
        return false;
      }
    }
    return true;
  }

  bool _validatePayment() {
    if (_roundOffAmount.abs() > 1.000001) {
      _error = 'Round off must be between -1.00 and 1.00.';
      return false;
    }
    final customer = _customer;
    if (customer == null) return false;
    if (_tenderedAmount < -0.0001) {
      _error = 'Payment amount cannot be negative.';
      return false;
    }
    if (_paymentMethod == 'credit' && customer.isWalkIn) {
      _error = 'Walk-in Customer cannot use credit.';
      return false;
    }
    if (customer.isWalkIn && _appliedPayment + 0.0001 < _total) {
      _error = 'Choose a named customer to leave an unpaid balance.';
      return false;
    }
    if (_paymentMethod != 'cash' && _paymentMethod != 'credit' && _tenderedAmount > _total + 0.0001) {
      _error = 'Received amount cannot exceed the invoice total for this payment method.';
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
    'items': _cart
        .map(
          (line) => <String, dynamic>{
            'variant_id': line.product.variantId,
            'quantity': line.quantity,
            'unit_id': line.unit?.unitId,
            'cutting_charge_applied': line.cuttingChargeApplied,
            'discount': line.discount,
            if (line.serialNumbers.isNotEmpty) 'serial_numbers': line.serialNumbers,
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
    _holdLabel.text =
        _customer?.isWalkIn == false ? (_customer?.name ?? '') : '';
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
      _message('Hold or clear the current sale before resuming another invoice.');
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
        InventoryProduct? product;
        for (final row in _products) {
          if (row.variantId == variantId) {
            product = row;
            break;
          }
        }
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
          if (product.trackingMode == 'serial') line.quantity = line.serialNumbers.length.toDouble();
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
        final customerId = state['customer_id']?.toString();
        if (customerId != null && _customers.any((row) => row.id == customerId)) {
          _customerId = customerId;
        }
        _orderMode = state['order_mode']?.toString() ?? 'counter';
        _orderDiscount.text = state['order_discount']?.toString() ?? '0.00';
        _roundOff.text = state['round_off']?.toString() ?? '0.00';
        _notes.text = state['notes']?.toString() ?? '';
        _paymentMethod = state['payment_method']?.toString() ?? 'cash';
        _tendered.text = state['tendered']?.toString() ?? '';
        _paymentReference.text = state['payment_reference']?.toString() ?? '';
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
        canReceive: widget.session.hasRole('owner') ||
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
    if (device.allowedModules.contains('cashier_shifts') && widget.session.hasModule('cashier_shifts')) {
      var hasShift = false;
      try {
        final shift = await _shiftService.current(
          tenantId: widget.session.business.id,
          deviceId: device.deviceId,
        );
        hasShift = shift != null && shift.isNotEmpty;
        if (hasShift) {
          await _offlineLocal.setMeta('shift:${widget.session.business.id}:${device.deviceId}', shift);
        }
      } catch (_) {
        hasShift = await _offlineSync.hasVerifiedOpenShift(widget.session);
      }
      if (!hasShift) {
        setState(() => _error = 'Cashier Shift is enabled. Start a shift while online before offline billing.');
        return;
      }
    }

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
        'items': _cart.map((line) => <String, dynamic>{
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
          if (line.serialNumbers.isNotEmpty) 'serial_numbers': List<String>.from(line.serialNumbers),
        }).toList(),
        'additional_charges': _cuttingCharges,
        'round_off': _roundOffAmount,
        'initial_payment': payment,
        'payment_method': _paymentMethod,
        'payment_reference': _paymentReference.text.trim(),
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
        await _offlineSync.syncPending(widget.session, onlyRequestId: requestId);
      } catch (_) {
        // The durable local queue is the source of truth during a network outage.
      }
      final record = await _offlineLocal.invoice(requestId);
      if (record == null) throw StateError('Offline invoice queue record could not be reloaded.');

      String? printWarning;
      String completedNumber = localNumber;
      if (record.status == 'synced') {
        _offlineMode = false;
        final result = record.serverResponse ?? const <String, dynamic>{};
        final saleNumber = result['sale_number']?.toString() ?? result['number']?.toString() ?? '';
        completedNumber = saleNumber.isEmpty ? localNumber : saleNumber;
        String? saleId = result['sale_id']?.toString();
        if ((saleId == null || saleId.isEmpty) && saleNumber.isNotEmpty) {
          try {
            saleId = await _sales.resolveSaleId(tenantId: widget.session.business.id, saleNumber: saleNumber);
          } catch (_) {}
        }
        SaleDetail? detail;
        if (saleId != null && saleId.isNotEmpty) {
          try { detail = await _sales.getSaleDetail(tenantId: widget.session.business.id, saleId: saleId); } catch (_) {}
        }
        if (printAfter && saleId != null && saleId.isNotEmpty && detail != null) {
          try {
            await _autoPrintCompletedSale(saleId: saleId, detail: detail, cashPayment: _paymentMethod == 'cash', forcePrint: true);
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
        _message('$completedNumber synchronized${printWarning != null ? ' • Print: $printWarning' : ''}${change > 0 ? ' • Change ${_money(change)}' : ''}${outstanding > 0.005 ? ' • ${_money(outstanding)} added to ${customer.name} account' : ''}.');
        try { await _load(); } catch (_) {}
      } else if (status == 'conflict') {
        _message('$localNumber saved locally but needs attention: ${record.conflictCode ?? 'CONFLICT'} • ${record.conflictMessage ?? 'Open Offline Sync.'}');
        final catalogue = await _offlineSync.cachedCatalogue(widget.session);
        if (mounted) setState(() { _products = catalogue.products; _customers = catalogue.customers; });
      } else {
        _message('$localNumber saved offline and queued for automatic sync${printWarning != null ? ' • Print: $printWarning' : ''}.');
        final catalogue = await _offlineSync.cachedCatalogue(widget.session);
        if (mounted) setState(() { _products = catalogue.products; _customers = catalogue.customers; });
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
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        _header(),
        if (_error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!)),
                IconButton(
                  onPressed: () => setState(() => _error = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: switch (_step) {
              0 => _productStep(),
              1 => _paymentStep(),
              _ => _reviewStep(),
            },
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Billing',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              Text(
                '${widget.session.device?.locationCode ?? ''} • ${widget.session.device?.deviceCode ?? ''} • ${widget.session.username} • ${widget.session.roleLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final progress = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          );
          final actions = Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              Chip(
                avatar: Icon(_offlineMode ? Icons.cloud_off_outlined : Icons.cloud_done_outlined, size: 16),
                label: Text(_offlineMode ? 'OFFLINE' : 'ONLINE'),
                visualDensity: VisualDensity.compact,
              ),
              if (_step == 0)
                OutlinedButton.icon(
                  onPressed: _cart.isEmpty || _saving || _workspace == _PosWorkspace.hold
                      ? null
                      : _openHoldEditor,
                  icon: const Icon(Icons.pause_circle_outline, size: 17),
                  label: const Text('Hold'),
                ),
              if (_step == 0)
                OutlinedButton.icon(
                  onPressed: _saving ? null : _resumeSale,
                  icon: const Icon(Icons.play_circle_outline, size: 17),
                  label: const Text('Resume'),
                ),
              IconButton(
                tooltip: 'Focus barcode / product search',
                onPressed: () => _searchFocus.requestFocus(),
                icon: const Icon(Icons.qr_code_scanner),
              ),
              IconButton(
                tooltip: 'Reload products/customers',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    actions,
                  ],
                ),
                const SizedBox(height: 6),
                progress,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              progress,
              const SizedBox(width: 10),
              actions,
            ],
          );
        },
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
        final compact = constraints.maxWidth < 980;
        final design = UiDesignScope.of(context, appKey: 'pos');
        if (compact) {
          return Column(
            children: [
              Expanded(child: _productWorkspace()),
              SizedBox(height: 310, child: _cartPanel()),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 7, child: _productWorkspace()),
            SizedBox(width: design.posCartWidth, child: _cartPanel()),
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
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.pause_circle_outline),
                              label: Text(_saving ? 'Holding…' : 'Hold Invoice'),
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
          Row(children: [
            IconButton.filledTonal(
              tooltip: 'Back to products',
              onPressed: () => setState(() {
                _editingLine = null;
                _workspace = _PosWorkspace.products;
              }),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.product.productName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text('Quantity & unit • Stock ${_formatStock(line.product.stockQuantity, line.product.baseUnitCode)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ])),
          ]),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (units.length > 1) ...[
                      const Text('Sale Unit', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: units.map((u) => ChoiceChip(
                          label: Text('${u.name} (${u.code})'),
                          selected: line.unit?.unitId == u.unitId,
                          onSelected: (_) => _setLineUnit(line, u),
                        )).toList(),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text('Quantity in ${line.unitCode}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton.filledTonal(onPressed: () => _changeQuantity(line, -line.quantityStep), icon: const Icon(Icons.remove)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 160,
                        child: TextFormField(
                          key: ValueKey('qty-${line.product.variantId}-${line.unitCode}-${line.quantity}'),
                          initialValue: line.displayQuantity,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(border: const OutlineInputBorder(), suffixText: line.unitCode),
                          onFieldSubmitted: (value) {
                            final parsed = double.tryParse(value.trim());
                            if (parsed == null || parsed <= 0) {
                              _message('Enter a quantity greater than zero.');
                              return;
                            }
                            final unit = line.unit;
                            if (unit != null && !unit.acceptsQuantity(parsed)) {
                              _message(unit.allowFractional
                                  ? '${line.unitCode} quantity must use increments of ${unit.quantityStep}.'
                                  : '${line.unitCode} only allows whole quantities in increments of ${unit.quantityStep}.');
                              return;
                            }
                            if (line.product.itemType == 'stock' && parsed * line.conversionToBase > line.product.stockQuantity + 0.000001) {
                              _message('Only ${_formatStock(line.product.stockQuantity, line.product.baseUnitCode)} available.');
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
                      IconButton.filledTonal(onPressed: () => _changeQuantity(line, line.quantityStep), icon: const Icon(Icons.add)),
                    ]),
                    const SizedBox(height: 12),
                    Text('Base stock impact: ${_formatStock(line.baseQuantity, line.product.baseUnitCode)}'),
                    Text('Unit price: ${_money(line.unitPrice)}'),
                    if ((line.unit?.cuttingAllowed ?? false) && (line.unit?.cuttingCharge ?? 0) > 0) ...[
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: line.cuttingChargeApplied,
                        onChanged: (value) => setState(() {
                          line.cuttingChargeApplied = value;
                          _syncTendered();
                        }),
                        title: Text('Add cutting charge ${_money(line.unit!.cuttingCharge)}'),
                        subtitle: const Text('Optional service charge added once for this cart line.'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
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
                        onPressed: () => _changeQuantity(line, -line.quantity),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove Item'),
                      ),
                    ]),
                  ]),
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
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select an invoice to restore it and continue billing.',
                      style: TextStyle(
                        fontSize: 11.5,
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
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 5),
                            const Text('Hold a sale first, then use Resume to continue it here.'),
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
                              final total = (row['total'] as num?)?.toDouble() ??
                                  double.tryParse('${row['total']}') ??
                                  0.0;
                              final created = DateTime.tryParse('${row['created_at']}')?.toLocal();
                              final createdLabel = created == null
                                  ? ''
                                  : '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
                              final code = row['hold_code']?.toString().trim() ?? '';
                              final label = row['label']?.toString().trim() ?? '';
                              final customer = row['customer_name']?.toString().trim() ?? '';
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
                                            const Icon(Icons.pause_circle_filled_outlined, size: 19),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                code.isEmpty ? 'Held Invoice' : code,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                            if (createdLabel.isNotEmpty)
                                              Text(createdLabel, style: const TextStyle(fontSize: 10.5)),
                                          ],
                                        ),
                                        if (label.isNotEmpty) ...[
                                          const SizedBox(height: 7),
                                          Text(
                                            label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                        const SizedBox(height: 5),
                                        Text(
                                          customer.isEmpty ? 'Walk-in customer' : customer,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const Spacer(),
                                        Row(
                                          children: [
                                            Text('${row['item_count'] ?? 0} item(s)', style: const TextStyle(fontSize: 11)),
                                            const Spacer(),
                                            Text(
                                              _money(total),
                                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, filters) {
              final width = filters.maxWidth;
              final searchFlex = width >= 1100 ? 5 : 4;
              final compactFlex = width >= 1100 ? 2 : 2;
              return Row(
                children: [
                  Expanded(
                    flex: searchFlex,
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      autofocus: true,
                      onChanged: _searchChanged,
                      onSubmitted: _searchSubmitted,
                      decoration: const InputDecoration(
                        hintText: 'Search product, SKU, barcode, QR or code…',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: compactFlex,
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        isDense: true,
                      ),
                      items: _categories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(
                                category,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _category = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: compactFlex,
                    child: DropdownButtonFormField<String>(
                      initialValue: _sort,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sort',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'name',
                          child: Text(
                            'Name A–Z',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'category',
                          child: Text(
                            'Category',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'price_low',
                          child: Text(
                            'Price low → high',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'price_high',
                          child: Text(
                            'Price high → low',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'stock_high',
                          child: Text(
                            'Stock high → low',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _sort = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: width >= 1100 ? 3 : 2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _chooseCustomer,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, size: 18),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                _customer?.name ?? 'Customer',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Icon(Icons.expand_more, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Customer balance / receive payment',
                    onPressed: _openCustomerAccount,
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          if (_restaurantAvailable) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  'Order type:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                for (final mode in const [
                  'counter',
                  'takeaway',
                  'delivery',
                ]) ...[
                  ChoiceChip(
                    selected: _orderMode == mode,
                    label: Text(mode[0].toUpperCase() + mode.substring(1)),
                    onSelected: (_) => setState(() => _orderMode = mode),
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                Text(
                  'Dine-in / KOT → Restaurant menu',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          if (_selectedProduct != null)
            _selectedProductStrip(_selectedProduct!),
          const SizedBox(height: 10),
          Expanded(
            child: products.isEmpty
                ? const Center(child: Text('No products match this search.'))
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent:
                          UiDesignScope.of(context, appKey: 'pos').posLayout ==
                              'compact_grid'
                          ? 175
                          : UiDesignScope.of(
                                  context,
                                  appKey: 'pos',
                                ).posLayout ==
                                'touch_grid'
                          ? 260
                          : 220,
                      mainAxisExtent:
                          UiDesignScope.of(context, appKey: 'pos').posLayout ==
                              'compact_grid'
                          ? 112
                          : UiDesignScope.of(
                                  context,
                                  appKey: 'pos',
                                ).posLayout ==
                                'touch_grid'
                          ? 158
                          : 136,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) =>
                        _productCard(products[index]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${products.length} matching products',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectedProductStrip(InventoryProduct product) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${product.productName} • SKU ${product.sku}'
              '${(product.partNumber ?? '').isNotEmpty ? ' • Part ${product.partNumber}' : ''}'
              '${(product.brandName ?? '').isNotEmpty ? ' • ${product.brandName}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('Stock ${_formatStock(product.stockQuantity, product.baseUnitCode)}'),
          const SizedBox(width: 16),
          Text(
            _money(product.sellingPrice),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _productCard(InventoryProduct product) {
    final design = UiDesignScope.of(context, appKey: 'pos');
    final outOfStock =
        product.itemType == 'stock' && product.stockQuantity <= 0;
    return Material(
      color: design.surface,
      borderRadius: BorderRadius.circular(design.radius),
      child: InkWell(
        onTap: outOfStock ? null : () => _add(product),
        onLongPress: () => setState(() => _selectedProduct = product),
        borderRadius: BorderRadius.circular(design.radius),
        child: Container(
          padding: EdgeInsets.all(design.compact ? 8 : 11),
          decoration: BoxDecoration(
            border: Border.all(color: design.border),
            borderRadius: BorderRadius.circular(design.radius),
            boxShadow: design.cardStyle == 'soft'
                ? [
                    BoxShadow(
                      color: design.primary.withValues(alpha: .045),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : const [],
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
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    product.itemType == 'stock'
                        ? '${_formatStock(product.stockQuantity, product.baseUnitCode)} left'
                        : product.itemType,
                    style: TextStyle(
                      fontSize: 10,
                      color: outOfStock ? Colors.red : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                product.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                'SKU ${product.sku}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _money(product.sellingPrice),
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    outOfStock ? Icons.block : Icons.add_circle,
                    color: outOfStock
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
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
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 10, 10, 10),
      decoration: BoxDecoration(
        color: design.surface,
        border: Border.all(color: design.border),
        borderRadius: BorderRadius.circular(design.radius),
        boxShadow: design.cardStyle == 'soft'
            ? [
                BoxShadow(
                  color: design.primary.withValues(alpha: .055),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Cart • ${_cart.length} ${_cart.length == 1 ? 'item' : 'items'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_cart.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear cart',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _cart.clear()),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_basket_outlined,
                          size: 42,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        const Text('Scan, search or tap a product'),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    itemCount: _cart.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _cartLine(_cart[index]),
                  ),
          ),
          _totals(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _cart.isEmpty ? null : _next,
                icon: const Icon(Icons.arrow_forward, size: 19),
                label: Text('Payment • ${_money(_total)}'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartLine(_PosLine line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${line.product.sku} • ${_money(line.unitPrice)} / ${line.unitCode}${line.pricingSource == null ? '' : ' • ${line.pricingSource}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: () => _changeQuantity(line, -line.quantityStep),
            icon: const Icon(Icons.remove_circle_outline, size: 19),
          ),
          SizedBox(
            width: 58,
            child: TextButton(
              onPressed: () => _openQuantityEditor(line),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                '${line.displayQuantity} ${line.unitCode}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5),
              ),
            ),
          ),
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: () => _changeQuantity(line, line.quantityStep),
            icon: const Icon(Icons.add_circle_outline, size: 19),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 78,
            child: Text(
              _money(_lineGross(line)),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            onPressed: () => _changeQuantity(line, -line.quantity),
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _totals() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          _totalRow('Subtotal', _subtotal),
          if (_discount > 0) _totalRow('Discount', -_discount),
          _totalRow('Tax', _tax),
          const Divider(),
          _totalRow('Total', _total, strong: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            _money(value),
            style: TextStyle(
              fontSize: strong ? 20 : 14,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentStep() {
    return LayoutBuilder(
      key: const ValueKey('payment'),
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 820;
        Widget pane(Widget child) => SingleChildScrollView(
          padding: const EdgeInsets.only(right: 2),
          child: child,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payment',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Complete directly or review the invoice first.',
                          style: TextStyle(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _money(_total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: stacked
                    ? Column(
                        children: [
                          Expanded(child: pane(_paymentControls())),
                          const SizedBox(height: 8),
                          Expanded(child: pane(_paymentDetails())),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: pane(_paymentControls())),
                          const SizedBox(width: 10),
                          Expanded(flex: 4, child: pane(_paymentDetails())),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              _paymentActionBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _paymentActionBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 690;
        final actions = <Widget>[
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
            icon: const Icon(Icons.visibility_outlined, size: 17),
            label: const Text('View Invoice'),
          ),
          FilledButton.tonalIcon(
            onPressed: _saving ? null : () => _checkout(printAfter: false),
            icon: const Icon(Icons.check_circle_outline, size: 17),
            label: const Text('Just Confirm'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : () => _checkout(printAfter: true),
            icon: const Icon(Icons.print_outlined, size: 17),
            label: const Text('Print & Confirm'),
          ),
        ];
        if (narrow) {
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'Back to products',
                onPressed: _saving ? null : _back,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
              ),
              ...actions,
            ],
          );
        }
        return Row(
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _back,
              icon: const Icon(Icons.inventory_2_outlined, size: 17),
              label: const Text('Products'),
            ),
            const Spacer(),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              actions[i],
            ],
          ],
        );
      },
    );
  }

  Widget _paymentControls() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'upi', child: Text('UPI')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                DropdownMenuItem(value: 'credit', child: Text('Credit / Due')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _paymentMethod = value;
                  _syncTendered();
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _orderDiscount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Invoice discount',
                prefixIcon: const Icon(Icons.discount_outlined),
                helperText: _manualOrderDiscount > 0
                    ? 'Applied across sale items before tax.'
                    : 'Optional',
              ),
              onChanged: (_) {
                setState(() {
                  _syncTendered();
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roundOff,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Round Off',
                      helperText: 'Post-tax adjustment (-1.00 to 1.00)',
                      prefixIcon: Icon(Icons.exposure_zero),
                    ),
                    onChanged: (_) => setState(() { _syncTendered(); }),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _applyRoundOff,
                  icon: const Icon(Icons.exposure_zero),
                  label: const Text('Round Total'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_paymentMethod == 'credit')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _customer?.isWalkIn == false
                            ? 'Full amount ${_money(_total)} will be added to ${_customer?.name} account.'
                            : 'Choose a named customer to use credit.',
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              TextField(
                controller: _tendered,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _paymentMethod == 'cash' ? 'Cash received' : 'Amount received',
                  helperText: _customer?.isWalkIn == false
                      ? 'You may receive less than the invoice total. The remaining balance is added to the customer account.'
                      : 'Walk-in sales must be paid in full.',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  suffixText: _paymentMethod == 'cash' && _change > 0
                      ? 'Change ${_money(_change)}'
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_accountBalance > 0.005 && _customer?.isWalkIn == false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_money(_accountBalance)} will remain on ${_customer?.name} account.',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (_paymentMethod == 'cash') ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    FilledButton.tonal(onPressed: _cashExact, child: const Text('Exact')),
                    for (final amount in const [10, 20, 50, 100, 200, 500, 1000, 2000])
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onPressed: () => _addCash(amount.toDouble()),
                        child: Text('+₹$amount'),
                      ),
                    TextButton(
                      onPressed: () => setState(() => _tendered.clear()),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _paymentReference,
              decoration: const InputDecoration(
                labelText: 'Payment reference (optional)',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Billing note (optional)',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentDetails() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sale Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),
                Chip(label: Text('${_cart.length} items')),
              ],
            ),
            const SizedBox(height: 8),
            _reviewRow('Customer', _customer?.name ?? '-'),
            _reviewRow(
              'Order type',
              _orderMode.replaceAll('_', ' ').toUpperCase(),
            ),
            const Divider(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 230),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _cart.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final line = _cart[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line.product.productName} × ${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _money(_lineGross(line)),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 22),
            _reviewRow('Subtotal', _money(_subtotal)),
            if (_discount > 0) _reviewRow('Discount', '- ${_money(_discount)}'),
            _reviewRow('Tax', _money(_tax)),
            if (_roundOffAmount.abs() > 0.000001) _reviewRow('Round Off', _money(_roundOffAmount)),
            const Divider(height: 18),
            _reviewRow('Grand Total', _money(_total), strong: true),
            _reviewRow('Amount Received', _money(_appliedPayment)),
            if (_paymentMethod == 'cash')
              _reviewRow('Change', _money(_change), strong: _change > 0),
            if (_accountBalance > 0.005)
              _reviewRow('Customer Account Balance', _money(_accountBalance), strong: true),
          ],
        ),
      ),
    );
  }

  Widget _reviewStep() {
    return Padding(
      key: const ValueKey('review'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                onPressed: _back,
                icon: const Icon(Icons.arrow_back, size: 18),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Invoice Review',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                _money(_total),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    children: [
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              _reviewRow('Customer', _customer?.name ?? '-'),
                              _reviewRow(
                                'Order type',
                                _orderMode.replaceAll('_', ' ').toUpperCase(),
                              ),
                              _reviewRow('Items', '${_cart.length}'),
                              _reviewRow('Subtotal', _money(_subtotal)),
                              if (_discount > 0)
                                _reviewRow(
                                  'Discount',
                                  '- ${_money(_discount)}',
                                ),
                              _reviewRow('Tax', _money(_tax)),
                              if (_roundOffAmount.abs() > 0.000001)
                                _reviewRow('Round Off', _money(_roundOffAmount)),
                              const Divider(height: 16),
                              _reviewRow(
                                'Grand Total',
                                _money(_total),
                                strong: true,
                              ),
                              _reviewRow(
                                'Payment',
                                _paymentMethod.toUpperCase(),
                              ),
                              _reviewRow('Amount received', _money(_appliedPayment)),
                              if (_paymentMethod == 'cash')
                                _reviewRow('Change', _money(_change), strong: _change > 0),
                              if (_accountBalance > 0.005)
                                _reviewRow(
                                  'Added to customer account',
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
                      ),
                      const SizedBox(height: 8),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _cart.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final line = _cart[index];
                            final net =
                                _lineGross(line) -
                                _effectiveLineDiscount(line);
                            final lineTotal =
                                net + (net * line.product.taxRate / 100);
                            return ListTile(
                              dense: true,
                              title: Text(
                                line.product.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${line.product.sku} • Qty ${line.quantity.toStringAsFixed(line.quantity % 1 == 0 ? 0 : 2)} • Tax ${line.product.taxRate.toStringAsFixed(2)}%',
                              ),
                              trailing: Text(
                                _money(lineTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, footerConstraints) {
              final buttons = [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _back,
                  icon: const Icon(Icons.arrow_back, size: 17),
                  label: const Text('Payment'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _saving
                      ? null
                      : () => _checkout(printAfter: false),
                  icon: const Icon(Icons.check_circle_outline, size: 17),
                  label: Text(_saving ? 'Saving…' : 'Just Confirm'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _checkout(printAfter: true),
                  icon: const Icon(Icons.print_outlined, size: 17),
                  label: Text(_saving ? 'Saving…' : 'Print & Confirm'),
                ),
              ];
              if (footerConstraints.maxWidth < 620) {
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: buttons,
                );
              }
              return Row(
                children: [
                  buttons.first,
                  const Spacer(),
                  buttons[1],
                  const SizedBox(width: 8),
                  buttons[2],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 19 : 14,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
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
      if ((unit.conversionToBase - 1).abs() <= 0.000001 && unit.allowSale && unit.active) return unit;
    }
  }
  return product.defaultSaleUnit;
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
        quantity = (product.defaultSaleUnit?.quantityStep ?? product.quantityStep) > 1
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
  double get unitPrice => resolvedUnitPrice ?? unit?.salePriceFor(product.sellingPrice) ?? product.sellingPrice;
  String get unitCode => unit?.code ?? product.baseUnitCode;
  String get displayQuantity {
    final decimals = unit?.decimalPlaces ?? (product.allowFractional ? 3 : 0);
    return quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : decimals.clamp(0, 6).toInt());
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
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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
