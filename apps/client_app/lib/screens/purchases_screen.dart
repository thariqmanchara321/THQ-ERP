import 'package:flutter/material.dart';
import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/gst/gst_compliance_v520_service.dart';
import '../models/client_session.dart';
import '../models/inventory_product.dart';
import '../models/purchase.dart';
import '../models/supplier.dart';
import '../services/inventory_service.dart';
import '../services/location_scope_service.dart';
import '../services/purchase_service.dart';
import '../services/supplier_service.dart';
import '../services/transaction_print_service.dart';
import 'purchase_detail_screen.dart';
import '../widgets/searchable_select.dart';

class PurchasesScreen extends StatefulWidget {
  final ClientSession session;
  final bool startInCreate;
  final bool historyOnly;

  const PurchasesScreen({
    super.key,
    required this.session,
    this.startInCreate = false,
    this.historyOnly = false,
  });

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final PurchaseService _service = PurchaseService();

  late Future<List<Purchase>> _purchasesFuture;

  bool _creating = false;
  int _purchaseGeneration = 0;

  bool get _canManage => widget.session.hasPermission('purchases.manage');

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
    _purchasesFuture = _service.getPurchases(
      tenantId: widget.session.business.id,
    );
  }

  Future<void> _refresh() async {
    setState(_load);

    await _purchasesFuture;
  }

  Future<void> _newPurchase() async {
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

  void _finishNewPurchase(bool created) {
    if (!mounted) return;
    setState(() {
      if (created) {
        _load();
        _purchaseGeneration++;
        _creating =
            widget.startInCreate &&
            _canManage &&
            LocationScopeService.selectedLocationId.value != null;
      } else {
        _creating = false;
      }
    });
    if (created) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase posted. Ready for the next purchase.'),
        ),
      );
    }
  }

  Future<void> _openPurchase(Purchase purchase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseDetailScreen(
          session: widget.session,
          purchaseId: purchase.id,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(_load);
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
        child: Text('You do not have permission to create purchases.'),
      );
    }
    if (widget.startInCreate &&
        LocationScopeService.selectedLocationId.value == null) {
      return const Center(
        child: Text(
          'Select a specific store above to start a new purchase. All Stores is view-only.',
        ),
      );
    }
    if (widget.startInCreate && !_creating) {
      return Center(
        child: FilledButton.icon(
          onPressed: _newPurchase,
          icon: const Icon(Icons.add),
          label: const Text('Start New Purchase'),
        ),
      );
    }
    if (_creating) {
      return NewPurchaseScreen(
        key: ValueKey(_purchaseGeneration),
        session: widget.session,
        locationId: LocationScopeService.currentForCreate(widget.session),
        embedded: true,
        onFinished: _finishNewPurchase,
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
                      widget.historyOnly ? 'Purchase Details' : 'Purchases',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text('Purchase bills and stock received'),
                  ],
                ),
              ),

              if (_canManage && !widget.historyOnly)
                FilledButton.icon(
                  onPressed: _newPurchase,
                  icon: const Icon(Icons.add),
                  label: const Text('New Purchase'),
                ),
            ],
          ),

          const SizedBox(height: 14),

          Expanded(
            child: FutureBuilder<List<Purchase>>(
              future: _purchasesFuture,
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
                        const SizedBox(height: 14),
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final purchases = snapshot.data ?? [];

                if (purchases.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_cart_outlined, size: 70),
                        const SizedBox(height: 18),
                        const Text(
                          'No Purchases Yet',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_canManage && !widget.historyOnly) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _newPurchase,
                            icon: const Icon(Icons.add),
                            label: const Text('Create First Purchase'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    itemCount: purchases.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final purchase = purchases[index];

                      return InkWell(
                        borderRadius: BorderRadius.circular(16),

                        onTap: () => _openPurchase(purchase),

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
                                      purchase.number,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      _date(purchase.purchaseDate),
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
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
                                      purchase.supplierName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      purchase.supplierInvoiceNumber ??
                                          'No supplier invoice',
                                      style: TextStyle(
                                        fontSize: 12,
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
                                      _money(purchase.grandTotal),
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
                                      _money(purchase.balanceDue),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              _PaymentBadge(status: purchase.paymentStatus),

                              const SizedBox(width: 10),

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

class NewPurchaseScreen extends StatefulWidget {
  final ClientSession session;
  final String locationId;
  final bool embedded;
  final ValueChanged<bool>? onFinished;

  const NewPurchaseScreen({
    super.key,
    required this.session,
    required this.locationId,
    this.embedded = false,
    this.onFinished,
  });

  @override
  State<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<NewPurchaseScreen> {
  final PurchaseService _purchaseService = PurchaseService();
  final TransactionPrintService _printService = TransactionPrintService();

  final SupplierService _supplierService = SupplierService();

  final InventoryService _inventoryService = InventoryService();

  final _invoiceController = TextEditingController();

  final _additionalController = TextEditingController(text: '0');

  final _roundOffController = TextEditingController(text: '0');

  final _paymentController = TextEditingController(text: '0');

  final _notesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String? _error;

  List<Supplier> _suppliers = [];
  List<InventoryProduct> _products = [];
  Map<String, Map<String, dynamic>> _gstProfiles = const {};

  String? _supplierId;

  DateTime _purchaseDate = DateTime.now();

  DateTime? _dueDate;

  String _paymentMethod = 'cash';

  final List<_PurchaseLine> _lines = [];

  Supplier? get _selectedSupplier {
    final id = _supplierId;
    if (id == null) return null;
    for (final supplier in _suppliers) {
      if (supplier.id == id) return supplier;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();

    _loadData();
  }

  Future<Map<String, Map<String, dynamic>>> _loadGstProfiles() async {
    try {
      final service = GstComplianceV520Service(
        client: Supabase.instance.client,
        tenantId: widget.session.business.id,
      );
      await service.initialize(locationId: widget.locationId, documentLimit: 1);
      final rows = await service.listProductProfiles(limit: 500);
      return {
        for (final row in rows)
          if (row['variant_id']?.toString().isNotEmpty == true)
            row['variant_id'].toString(): row,
      };
    } catch (_) {
      // Non-GST businesses and users without GST workspace access remain usable.
      return const {};
    }
  }

  String _hsnFor(String variantId) {
    final value = _gstProfiles[variantId]?['hsn_sac']?.toString().trim() ?? '';
    return value.isEmpty ? '—' : value;
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _supplierService.getSuppliers(tenantId: widget.session.business.id),
        _inventoryService.getProducts(
          tenantId: widget.session.business.id,
          locationId: widget.locationId,
        ),
        _loadGstProfiles(),
      ]);

      if (!mounted) {
        return;
      }

      final suppliers = results[0] as List<Supplier>;

      final products = results[1] as List<InventoryProduct>;
      final gstProfiles = results[2] as Map<String, Map<String, dynamic>>;

      setState(() {
        _suppliers = suppliers.where((supplier) => supplier.isActive).toList();

        _products = products
            .where(
              (product) =>
                  product.itemType == 'stock' &&
                  product.productStatus == 'active' &&
                  product.variantStatus == 'active',
            )
            .toList();
        _gstProfiles = gstProfiles;

        if (_suppliers.isNotEmpty) {
          _supplierId = _suppliers.first.id;
        }

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

  double get _additional => _number(_additionalController);

  double get _roundOff => _number(_roundOffController);

  double get _beforeRoundOff => _subtotal - _discount + _tax + _additional;

  double get _grandTotal => _beforeRoundOff + _roundOff;

  double get _taxableAmount => _subtotal - _discount;

  String get _placeOfSupply {
    final value = _selectedSupplier?.state?.trim() ?? '';
    return value.isEmpty ? 'Not configured' : value;
  }

  bool? get _interstatePreview {
    final origin =
        widget.session.settings['business.state']
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    final destination = _selectedSupplier?.state?.trim().toLowerCase() ?? '';
    if (origin.isEmpty || destination.isEmpty) return null;
    return origin != destination;
  }

  double get _cgstPreview => _interstatePreview == false ? _tax / 2 : 0;
  double get _sgstPreview => _interstatePreview == false ? _tax / 2 : 0;
  double get _igstPreview => _interstatePreview == true ? _tax : 0;

  void _applyRoundOff() {
    final delta = _beforeRoundOff.roundToDouble() - _beforeRoundOff;
    _roundOffController.text = delta.abs() < 0.000001
        ? '0.00'
        : delta.toStringAsFixed(2);
    setState(() {});
  }

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }

    return '${widget.session.currencyCode} '
        '${value.toStringAsFixed(2)}';
  }

  Future<void> _addLine() async {
    final available = _products
        .where(
          (product) => !_lines.any(
            (line) => line.product.variantId == product.variantId,
          ),
        )
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more products available to add.')),
      );

      return;
    }

    final line = await showDialog<_PurchaseLine>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddPurchaseItemDialog(products: available),
    );

    if (line != null && mounted) {
      setState(() {
        _lines.add(line);
      });
    }
  }

  Future<void> _choosePurchaseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        _purchaseDate = date;

        if (_dueDate != null && _dueDate!.isBefore(date)) {
          _dueDate = null;
        }
      });
    }
  }

  Future<void> _chooseDueDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _purchaseDate,
      firstDate: _purchaseDate,
      lastDate: DateTime(2100),
    );

    if (date != null && mounted) {
      setState(() {
        _dueDate = date;
      });
    }
  }

  String _date(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.year}';
  }

  String _friendlyPostError(Object error) {
    final message = error.toString();
    final productMatch = RegExp(
      r'Product\s+([^\s\]]+)\s+GST profile requires review',
      caseSensitive: false,
    ).firstMatch(message);
    if (productMatch != null) {
      return 'Cannot confirm this GST purchase. Review and validate the GST '
          'profile for product ${productMatch.group(1)}, then retry this '
          'unchanged purchase.';
    }
    if (message.contains('not compliance-ready')) {
      return 'Cannot confirm this GST purchase because one or more GST profiles '
          'are not compliance-ready. Review them in GST & Compliance, then '
          'retry this unchanged purchase.';
    }
    return message;
  }

  Future<void> _post({bool printAfter = false}) async {
    if (_supplierId == null) {
      setState(() {
        _error = 'Select a supplier.';
      });
      return;
    }

    if (_lines.isEmpty) {
      setState(() {
        _error = 'Add at least one product.';
      });
      return;
    }

    final additional = _number(_additionalController);

    final payment = _number(_paymentController);

    if (additional < 0) {
      setState(() {
        _error = 'Additional charges cannot be negative.';
      });
      return;
    }

    if (_roundOff.abs() > 1.000001) {
      setState(() {
        _error = 'Round off must be between -1.00 and 1.00.';
      });
      return;
    }

    if (payment < 0) {
      setState(() {
        _error = 'Payment cannot be negative.';
      });
      return;
    }

    if (payment > _grandTotal + 0.0001) {
      setState(() {
        _error = 'Payment cannot exceed grand total.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await _purchaseService.createPurchase(
        tenantId: widget.session.business.id,
        supplierId: _supplierId!,
        supplierInvoiceNumber: _invoiceController.text,
        purchaseDate: _purchaseDate,
        dueDate: _dueDate,
        items: _lines
            .map(
              (line) => {
                'variant_id': line.product.variantId,
                'quantity': line.quantity,
                'unit_id': line.unit?.unitId,
                'unit_cost': line.unitCost,
                'discount_amount': line.discount,
                'tax_rate': line.taxRate,
                if (line.serialNumbers.isNotEmpty)
                  'serial_numbers': line.serialNumbers,
                if (line.batches.isNotEmpty) 'batches': line.batches,
              },
            )
            .toList(),
        additionalCharges: additional,
        roundOff: _roundOff,
        initialPayment: payment,
        paymentMethod: _paymentMethod,
        notes: _notesController.text,
        locationId: widget.locationId,
      );

      String? printWarning;
      if (printAfter) {
        try {
          final rawId =
              result['purchase_id'] ??
              result['id'] ??
              (result['result'] is Map
                  ? (result['result'] as Map)['purchase_id']
                  : null) ??
              (result['result'] is Map
                  ? (result['result'] as Map)['id']
                  : null);
          final purchaseId = rawId?.toString() ?? '';
          if (purchaseId.isEmpty) {
            throw StateError(
              'Purchase is confirmed, but the response did not contain a purchase ID.',
            );
          }
          final detail = await _purchaseService.getPurchaseDetail(
            tenantId: widget.session.business.id,
            purchaseId: purchaseId,
          );
          await _printService.printPurchase(
            session: widget.session,
            purchase: detail,
          );
        } catch (error) {
          printWarning =
              'Purchase confirmed successfully, but printing failed: $error';
        }
      }

      if (!mounted) {
        return;
      }

      if (printWarning != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(printWarning)));
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
    _invoiceController.dispose();
    _additionalController.dispose();
    _roundOffController.dispose();
    _paymentController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _suppliers.isEmpty
        ? const Center(child: Text('No active suppliers available.'))
        : LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
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
                      _headerCard(),
                      const SizedBox(height: 12),
                      _itemsCard(),
                      const SizedBox(height: 12),
                      _summaryCard(),
                    ],
                  ),
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
          'New Purchase',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: content,
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
                  'NEW PURCHASE',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text('Purchase Entry', style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('PURCHASE NO.', style: TextStyle(fontSize: 11)),
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

  Widget _headerCard() {
    final supplier = _selectedSupplier;
    return _PurchaseCard(
      title: 'PURCHASE DETAILS',
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
                  value: _supplierId,
                  labelText: 'Supplier',
                  isRequired: true,
                  enabled: !_saving,
                  hintText: 'Search supplier name, ID, phone or GSTIN',
                  prefixIcon: Icons.local_shipping_outlined,
                  options: _suppliers
                      .map(
                        (entry) => SearchableSelectOption<String>(
                          value: entry.id,
                          label: entry.name,
                          subtitle:
                              [entry.publicId, entry.phone, entry.taxNumber]
                                  .where(
                                    (value) => value?.trim().isNotEmpty == true,
                                  )
                                  .join(' • '),
                          searchText:
                              '${entry.name} ${entry.publicId} ${entry.phone ?? ''} '
                              '${entry.email ?? ''} ${entry.taxNumber ?? ''}',
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _supplierId = value;
                          _error = null;
                        }),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _purchaseReadOnlyField(
                  label: 'Supplier GSTIN',
                  value: supplier?.taxNumber?.trim().isNotEmpty == true
                      ? supplier!.taxNumber!
                      : 'Not registered',
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: _invoiceController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Supplier Invoice No.',
                    prefixIcon: Icon(Icons.tag_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: _saving ? null : _choosePurchaseDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Invoice Date  ${_date(_purchaseDate)}'),
                ),
              ),
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
                        ? 'Due Date  Not set'
                        : 'Due Date  ${_date(_dueDate!)}',
                  ),
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _purchaseReadOnlyField(
                  label: 'Place of Supply',
                  value: _placeOfSupply,
                  icon: Icons.place_outlined,
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _purchaseReadOnlyField(
                  label: 'Reverse Charge',
                  value: 'Automatic from GST profile',
                  icon: Icons.sync_alt_outlined,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _purchaseReadOnlyField({
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
    return _PurchaseCard(
      title: 'ADD PRODUCTS',
      trailing: FilledButton.icon(
        onPressed: _saving ? null : _addLine,
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
      child: _lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Center(
                child: Text('Search or scan a product to start this purchase.'),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1120,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      color: const Color(0xFFF1F4F8),
                      child: Row(
                        children: [
                          _purchaseHeaderCell('#', 1),
                          _purchaseHeaderCell('Product', 4),
                          _purchaseHeaderCell('HSN/SAC', 2),
                          _purchaseHeaderCell('Qty', 2),
                          _purchaseHeaderCell('Rate', 2),
                          _purchaseHeaderCell('Disc.', 2),
                          _purchaseHeaderCell('GST', 1),
                          _purchaseHeaderCell('Amount', 2),
                          const SizedBox(width: 44),
                        ],
                      ),
                    ),
                    for (var i = 0; i < _lines.length; i++)
                      _PurchaseLineRow(
                        index: i + 1,
                        line: _lines[i],
                        hsnSac: _hsnFor(_lines[i].product.variantId),
                        money: _money,
                        onDelete: _saving
                            ? null
                            : () => setState(() => _lines.removeAt(i)),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _purchaseHeaderCell(String label, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _summaryCard() {
    final paymentInputs = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment & Charges',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in const [
              ('cash', 'Cash', Icons.payments_outlined),
              ('bank', 'Bank', Icons.account_balance_outlined),
              ('upi', 'UPI', Icons.qr_code_2_outlined),
              ('card', 'Card', Icons.credit_card_outlined),
              ('cheque', 'Cheque', Icons.receipt_long_outlined),
              ('other', 'Other', Icons.more_horiz),
            ])
              ChoiceChip(
                avatar: Icon(entry.$3, size: 17),
                label: Text(entry.$2),
                selected: _paymentMethod == entry.$1,
                onSelected: _saving
                    ? null
                    : (_) => setState(() => _paymentMethod = entry.$1),
              ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 580;
            final payment = TextField(
              controller: _paymentController,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Initial Payment',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            );
            final additional = TextField(
              controller: _additionalController,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Freight / Other Charges',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
              ),
            );
            if (compact) {
              return Column(
                children: [payment, const SizedBox(height: 10), additional],
              );
            }
            return Row(
              children: [
                Expanded(child: payment),
                const SizedBox(width: 12),
                Expanded(child: additional),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _roundOffController,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Round Off',
            helperText: 'Allowed: -1.00 to 1.00',
            prefixText: '₹ ',
            suffixIcon: IconButton(
              tooltip: 'Round total',
              onPressed: _saving ? null : _applyRoundOff,
              icon: const Icon(Icons.exposure_zero),
            ),
            border: const OutlineInputBorder(),
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
        const SizedBox(height: 6),
        const Text(
          'For a credit purchase, leave Initial Payment at ₹0.00.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );

    final taxSummary = Column(
      children: [
        _TotalRow(label: 'Subtotal', value: _money(_subtotal)),
        if (_discount > .0001)
          _TotalRow(label: 'Discount', value: '- ${_money(_discount)}'),
        _TotalRow(label: 'Taxable Amount', value: _money(_taxableAmount)),
        if (_interstatePreview == false) ...[
          _TotalRow(label: 'CGST', value: _money(_cgstPreview)),
          _TotalRow(label: 'SGST', value: _money(_sgstPreview)),
        ] else if (_interstatePreview == true)
          _TotalRow(label: 'IGST', value: _money(_igstPreview))
        else
          _TotalRow(label: 'GST / Tax', value: _money(_tax)),
        if (_additional > .0001)
          _TotalRow(label: 'Additional Charges', value: _money(_additional)),
        if (_roundOff.abs() > .000001)
          _TotalRow(label: 'Round Off', value: _money(_roundOff)),
        const Divider(height: 24),
        _TotalRow(label: 'GRAND TOTAL', value: _money(_grandTotal), bold: true),
        _TotalRow(label: 'Payment', value: _money(_number(_paymentController))),
        _TotalRow(
          label: 'Balance Due',
          value: _money(_grandTotal - _number(_paymentController)),
          bold: true,
        ),
        const SizedBox(height: 8),
        const Text(
          'GST split shown here is an estimate. The confirmed purchase uses the '
          'authoritative GST v5.2 snapshot.',
          style: TextStyle(fontSize: 10, color: Colors.black54),
        ),
      ],
    );

    return _PurchaseCard(
      title: 'TOTALS & PAYMENT',
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 860) {
                return Column(
                  children: [
                    paymentInputs,
                    const SizedBox(height: 22),
                    taxSummary,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: paymentInputs),
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

class _PurchaseLine {
  final InventoryProduct product;
  final ProductUnitOption? unit;
  final double quantity;
  final double unitCost;
  final double discount;
  final double taxRate;
  final List<String> serialNumbers;
  final List<Map<String, dynamic>> batches;

  const _PurchaseLine({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.discount,
    required this.taxRate,
    this.serialNumbers = const [],
    this.batches = const [],
  });

  String get unitCode => unit?.code ?? product.baseUnitCode;
  double get baseQuantity => quantity * (unit?.conversionToBase ?? 1);
  double get subtotal => quantity * unitCost;

  double get taxable => subtotal - discount;

  double get tax => taxable * taxRate / 100;

  double get total => taxable + tax;
}

class _AddPurchaseItemDialog extends StatefulWidget {
  final List<InventoryProduct> products;

  const _AddPurchaseItemDialog({required this.products});

  @override
  State<_AddPurchaseItemDialog> createState() => _AddPurchaseItemDialogState();
}

class _AddPurchaseItemDialogState extends State<_AddPurchaseItemDialog> {
  String? _variantId;
  String? _unitId;

  final _quantityController = TextEditingController(text: '1');

  final _costController = TextEditingController();

  final _discountController = TextEditingController(text: '0');

  final _taxController = TextEditingController();
  final _serialsController = TextEditingController();
  final List<Map<String, dynamic>> _batches = [];
  bool _autoSerials = true;

  String? _error;

  InventoryProduct? get _product {
    if (_variantId == null) {
      return null;
    }

    for (final product in widget.products) {
      if (product.variantId == _variantId) {
        return product;
      }
    }

    return null;
  }

  ProductUnitOption? get _selectedUnit {
    final product = _product;
    if (product == null) return null;
    for (final unit in product.purchaseUnits) {
      if (unit.unitId == _unitId) return unit;
    }
    return product.defaultPurchaseUnit;
  }

  void _selectProduct(String? value) {
    setState(() {
      _variantId = value;

      final product = _product;

      _serialsController.clear();
      _batches.clear();
      _autoSerials = true;

      if (product != null) {
        final unit = product.defaultPurchaseUnit;
        _unitId = unit?.unitId;
        _costController.text =
            (unit?.purchaseCostFor(product.costPrice) ?? product.costPrice)
                .toStringAsFixed(2);
        _taxController.text = product.taxRate.toStringAsFixed(2);
      }
    });

    if (_product?.trackingMode == 'serial') {
      _generateSerials();
    }
  }

  String _serialPrefix(InventoryProduct product) {
    final clean = product.sku
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    return clean.isEmpty ? 'SN' : clean;
  }

  void _generateSerials() {
    final product = _product;
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    final baseQuantity = quantity * (_selectedUnit?.conversionToBase ?? 1);
    if (product == null || product.trackingMode != 'serial') return;
    if (baseQuantity <= 0 || baseQuantity != baseQuantity.truncateToDouble()) {
      setState(() {
        _error =
            'Enter a whole base-unit quantity before generating serial numbers.';
      });
      return;
    }

    final prefix = _serialPrefix(product);
    final stamp = DateTime.now().microsecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase();
    final values = List<String>.generate(
      baseQuantity.round(),
      (index) => '$prefix-$stamp-${(index + 1).toString().padLeft(3, '0')}',
    );
    _serialsController.text = values.join('\n');
    setState(() {
      _autoSerials = true;
      _error = null;
    });
  }

  String _autoBatchNumber(InventoryProduct product) {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final sku = product.sku
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    return 'LOT-${sku.isEmpty ? 'ITEM' : sku}-$date-${_batches.length + 1}';
  }

  Future<void> _addAutoBatch() async {
    final product = _product;
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    if (product == null || product.trackingMode != 'batch') return;

    final baseQuantity = quantity * (_selectedUnit?.conversionToBase ?? 1);
    final allocated = _batches.fold<double>(
      0,
      (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0),
    );
    final remaining = baseQuantity - allocated;
    if (remaining <= 0.000001) {
      setState(() => _error = 'The full batch quantity is already allocated.');
      return;
    }

    final batch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PurchaseBatchDialog(
        initialBatchNumber: _autoBatchNumber(product),
        initialQuantity: remaining,
      ),
    );
    if (batch != null && mounted) {
      setState(() {
        _batches.add(batch);
        _error = null;
      });
    }
  }

  List<String> _serialValues() => _serialsController.text
      .split(RegExp(r'[\n,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _addBatch() async {
    final batch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PurchaseBatchDialog(),
    );
    if (batch != null && mounted) setState(() => _batches.add(batch));
  }

  void _add() {
    final product = _product;

    final quantity = double.tryParse(_quantityController.text.trim());

    final cost = double.tryParse(_costController.text.trim());

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
    if (product.trackingMode == 'batch') {
      final batchQuantity = _batches.fold<double>(
        0,
        (sum, row) => sum + ((row['quantity'] as num?)?.toDouble() ?? 0),
      );
      if ((batchQuantity - baseQuantity).abs() > 0.000001) {
        setState(
          () => _error =
              'Batch quantities must total the base quantity (${baseQuantity.toStringAsFixed(4)}).',
        );
        return;
      }
    }

    if (cost == null || cost < 0) {
      setState(() {
        _error = 'Enter a valid purchase cost.';
      });
      return;
    }

    if (discount < 0 || discount > quantity * cost) {
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
      _PurchaseLine(
        product: product,
        unit: _selectedUnit,
        quantity: quantity,
        unitCost: cost,
        discount: discount,
        taxRate: tax,
        serialNumbers: product.trackingMode == 'serial'
            ? serialNumbers
            : const [],
        batches: product.trackingMode == 'batch'
            ? List<Map<String, dynamic>>.from(_batches)
            : const [],
      ),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    _discountController.dispose();
    _taxController.dispose();
    _serialsController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Product'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<InventoryProduct>(
              displayStringForOption: (product) =>
                  '${product.productName} — ${product.sku}',
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                if (q.isEmpty) return widget.products.take(20);
                bool starts(InventoryProduct product) =>
                    product.productName.toLowerCase().startsWith(q) ||
                    product.sku.toLowerCase().startsWith(q) ||
                    (product.partNumber ?? '').toLowerCase().startsWith(q) ||
                    (product.barcode ?? '').toLowerCase().startsWith(q) ||
                    product.searchCodes
                        .toLowerCase()
                        .split(RegExp(r'\s+'))
                        .any((v) => v.startsWith(q));
                bool contains(InventoryProduct product) =>
                    product.productName.toLowerCase().contains(q) ||
                    product.sku.toLowerCase().contains(q) ||
                    (product.partNumber ?? '').toLowerCase().contains(q) ||
                    (product.barcode ?? '').toLowerCase().contains(q) ||
                    product.searchCodes.toLowerCase().contains(q);
                final first = widget.products.where(starts);
                final rest = widget.products.where(
                  (p) => !starts(p) && contains(p),
                );
                return [...first, ...rest].take(40);
              },
              onSelected: (product) => _selectProduct(product.variantId),
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Product / SKU / part number / barcode',
                    hintText: 'Type first letters or scan a barcode',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) {
                    final q = value.trim().toLowerCase();
                    InventoryProduct? exact;
                    for (final product in widget.products) {
                      if (product.sku.toLowerCase() == q ||
                          (product.barcode ?? '').toLowerCase() == q ||
                          (product.partNumber ?? '').toLowerCase() == q) {
                        exact = product;
                        break;
                      }
                    }
                    if (exact != null) {
                      controller.text = '${exact.productName} — ${exact.sku}';
                      _selectProduct(exact.variantId);
                    } else {
                      onSubmitted();
                    }
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 300,
                      maxWidth: 600,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final product = options.elementAt(index);
                        return ListTile(
                          dense: true,
                          title: Text(product.productName),
                          subtitle: Text(
                            [
                              'SKU ${product.sku}',
                              if ((product.partNumber ?? '').isNotEmpty)
                                'Part ${product.partNumber}',
                              if ((product.barcode ?? '').isNotEmpty)
                                'Barcode ${product.barcode}',
                            ].join(' • '),
                          ),
                          onTap: () => onSelected(product),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (_product != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Chip(label: Text('Selected: ${_product!.productName}')),
                    Chip(label: Text('SKU ${_product!.sku}')),
                    if ((_product!.barcode ?? '').isNotEmpty)
                      Chip(label: Text('Barcode ${_product!.barcode}')),
                  ],
                ),
              ),
            ],

            if ((_product?.purchaseUnits.length ?? 0) > 1) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _unitId,
                decoration: const InputDecoration(
                  labelText: 'Purchase Unit',
                  border: OutlineInputBorder(),
                ),
                items: _product!.purchaseUnits
                    .map(
                      (u) => DropdownMenuItem(
                        value: u.unitId,
                        child: Text(
                          '${u.name} (${u.code}) • 1 = ${u.conversionToBase} ${_product!.baseUnitCode}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _unitId = value;
                    final unit = _selectedUnit;
                    if (unit != null) {
                      _costController.text = unit
                          .purchaseCostFor(_product!.costPrice)
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
                    onChanged: (_) {
                      if (_autoSerials && _product?.trackingMode == 'serial') {
                        _generateSerials();
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Unit Cost',
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Serial tracking',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _generateSerials,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Auto Generate'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _serialsController,
                minLines: 3,
                maxLines: 7,
                onChanged: (_) {
                  if (_autoSerials) setState(() => _autoSerials = false);
                },
                decoration: InputDecoration(
                  labelText: _autoSerials
                      ? 'Auto serial numbers'
                      : 'Manual serial numbers',
                  hintText: 'One serial per base unit',
                  helperText:
                      'Generated automatically for serial-tracked products. You can edit, scan or replace them manually.',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],

            if (_product?.trackingMode == 'batch') ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Batch allocation',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              ..._batches.asMap().entries.map(
                (entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${entry.value['batch_number']} • ${entry.value['quantity']} ${_product?.baseUnitCode ?? ''}',
                  ),
                  subtitle: Text(
                    'MFG ${entry.value['manufactured_on'] ?? '-'} • EXP ${entry.value['expiry_on'] ?? '-'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _batches.removeAt(entry.key)),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _addBatch,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Batch / Lot'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _addAutoBatch,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Auto Batch Number'),
                    ),
                  ],
                ),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
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

class _PurchaseBatchDialog extends StatefulWidget {
  final String initialBatchNumber;
  final double? initialQuantity;

  const _PurchaseBatchDialog({
    this.initialBatchNumber = '',
    this.initialQuantity,
  });
  @override
  State<_PurchaseBatchDialog> createState() => _PurchaseBatchDialogState();
}

class _PurchaseBatchDialogState extends State<_PurchaseBatchDialog> {
  late final TextEditingController _number;
  late final TextEditingController _quantity;
  final _manufactured = TextEditingController();
  final _expiry = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.initialBatchNumber);
    _quantity = TextEditingController(
      text: widget.initialQuantity == null
          ? ''
          : widget.initialQuantity!.toStringAsFixed(
              widget.initialQuantity! % 1 == 0 ? 0 : 4,
            ),
    );
  }

  @override
  void dispose() {
    _number.dispose();
    _quantity.dispose();
    _manufactured.dispose();
    _expiry.dispose();
    super.dispose();
  }

  void _save() {
    final qty = double.tryParse(_quantity.text.trim());
    if (_number.text.trim().isEmpty || qty == null || qty <= 0) {
      setState(
        () => _error = 'Enter a batch number and positive base quantity.',
      );
      return;
    }
    Navigator.of(context).pop(<String, dynamic>{
      'batch_number': _number.text.trim(),
      'quantity': qty,
      'manufactured_on': _manufactured.text.trim().isEmpty
          ? null
          : _manufactured.text.trim(),
      'expiry_on': _expiry.text.trim().isEmpty ? null : _expiry.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Batch'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _number,
            decoration: const InputDecoration(
              labelText: 'Batch / lot number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Quantity in base unit',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _manufactured,
            decoration: const InputDecoration(
              labelText: 'Manufacture date (YYYY-MM-DD)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _expiry,
            decoration: const InputDecoration(
              labelText: 'Expiry date (YYYY-MM-DD)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Add')),
    ],
  );
}

class _PurchaseLineRow extends StatelessWidget {
  final int index;
  final _PurchaseLine line;
  final String hsnSac;
  final String Function(double) money;
  final VoidCallback? onDelete;

  const _PurchaseLineRow({
    required this.index,
    required this.line,
    required this.hsnSac,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  line.product.sku,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
            4,
          ),
          cell(Text(hsnSac), 2),
          cell(Text('${_quantity(line.quantity)} ${line.unitCode}'), 2),
          cell(Text(money(line.unitCost)), 2),
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

class _PurchaseCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _PurchaseCard({
    required this.title,
    required this.child,
    this.trailing,
  });

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

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _TotalRow({
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

class _PaymentBadge extends StatelessWidget {
  final String status;

  const _PaymentBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final text = status.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status == 'paid'
            ? Colors.green.shade50
            : status == 'partial'
            ? Colors.orange.shade50
            : Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
