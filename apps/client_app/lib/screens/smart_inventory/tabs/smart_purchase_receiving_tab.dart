import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';
import '../../../services/device_installation_service.dart';
import '../../../services/location_scope_service.dart';
import '../../../services/purchase_receiving_service.dart';
import '../../../services/supplier_service.dart';

/// Purchase Receiving & Goods Inward Workspace Tab (Phase 10).
///
/// Features:
/// 1. Goods Receipt Note (GRN) receiving against authorized Purchase Orders.
/// 2. Direct supplier inward receiving without prior PO.
/// 3. Hardware gun wedge & mobile camera scanning with multi-identifier resolution.
/// 4. Discrepancy analysis: complete, partial, missing, excess, damaged, and rejected items.
/// 5. Separation of duties, verification confirmation, and double-entry ledger posting.
/// 6. Historical GRN audit review.
class SmartPurchaseReceivingTab extends StatefulWidget {
  final ClientSession session;
  final PurchaseReceivingSession? initialSession;

  const SmartPurchaseReceivingTab({
    super.key,
    required this.session,
    this.initialSession,
  });

  @override
  State<SmartPurchaseReceivingTab> createState() =>
      _SmartPurchaseReceivingTabState();
}

class _SmartPurchaseReceivingTabState extends State<SmartPurchaseReceivingTab> {
  final PurchaseReceivingService _receivingService =
      PurchaseReceivingService.instance;
  final ClientSmartInventoryService _identService =
      ClientSmartInventoryService.instance;

  late final SmartScannerController _scannerController;
  final TextEditingController _manualInput = TextEditingController();
  final FocusNode _manualFocus = FocusNode();
  final TextEditingController _searchPoController = TextEditingController();

  // Active Session State
  PurchaseReceivingSession? _activeSession;
  bool _isLoading = false;
  bool _isCameraOpen = false;

  // Active filters
  String _activeFilter = 'all'; // 'all', 'pending', 'received', 'missing', 'damaged_rejected', 'excess'
  String _searchItemQuery = '';

  // Setup view lists
  List<PurchaseOrderSummaryRecord> _receivableOrders = [];
  List<GoodsReceiptSummaryRecord> _pastGrns = [];
  bool _isLoadingOrders = false;
  bool _isLoadingGrns = false;
  int _setupSubTab = 0; // 0: Open POs, 1: Direct Inward, 2: GRN History

  // Direct Inward form controllers
  final TextEditingController _directSupplierInvoice = TextEditingController();
  final TextEditingController _directDeliveryNote = TextEditingController();
  String? _directSupplierId;
  String? _directSupplierName;
  List<Map<String, dynamic>> _availableSuppliers = [];

  bool get _canReceiveAndPost =>
      widget.session.hasPermission('purchases.receive') ||
      widget.session.hasPermission('purchases.manage') ||
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasRole('owner') ||
      widget.session.hasRole('admin') ||
      widget.session.hasRole('manager');

  @override
  void initState() {
    super.initState();
    _scannerController = SmartScannerController(
      configuration: const ScannerConfiguration(
        mode: ScannerMode.continuous,
        duplicateSuppressionDuration: Duration(milliseconds: 900),
      ),
    );

    _scannerController.scans.listen(_onScanReceived);
    _scannerController.start();

    if (widget.initialSession != null) {
      _activeSession = widget.initialSession;
    } else {
      _loadReceivableOrders();
      _loadPastGrns();
      _loadSuppliers();
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _manualInput.dispose();
    _manualFocus.dispose();
    _searchPoController.dispose();
    _directSupplierInvoice.dispose();
    _directDeliveryNote.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final list = await SupplierService().getSuppliers(tenantId: widget.session.business.id);
      if (mounted) {
        setState(() {
          _availableSuppliers = list
              .map((s) => {
                    'id': s.id,
                    'name': s.name,
                  })
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadReceivableOrders() async {
    setState(() => _isLoadingOrders = true);
    try {
      final locId = LocationScopeService.selectedLocationId.value ??
          LocationScopeService.currentForRead(widget.session);

      final list = await _receivingService.listReceivablePurchaseOrders(
        tenantId: widget.session.business.id,
        locationId: locId,
        query: _searchPoController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _receivableOrders = list;
          _isLoadingOrders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingOrders = false);
        ThqNotify.showSnackBar(
          context,
          SnackBar(content: Text('Failed to load purchase orders: $e')),
        );
      }
    }
  }

  Future<void> _loadPastGrns() async {
    setState(() => _isLoadingGrns = true);
    try {
      final locId = LocationScopeService.selectedLocationId.value ??
          LocationScopeService.currentForRead(widget.session);

      final list = await _receivingService.listPastGoodsReceipts(
        tenantId: widget.session.business.id,
        locationId: locId,
      );

      if (mounted) {
        setState(() {
          _pastGrns = list;
          _isLoadingGrns = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingGrns = false);
      }
    }
  }

  Future<void> _startReceivingForPo(PurchaseOrderSummaryRecord po) async {
    setState(() => _isLoading = true);
    try {
      final items = await _receivingService.fetchReceivingItemsForPo(
        tenantId: widget.session.business.id,
        purchaseOrderId: po.id,
      );

      final session = PurchaseReceivingSession(
        id: const Uuid().v4(),
        sessionName: 'Receiving • ${po.orderNumber}',
        tenantId: widget.session.business.id,
        locationId: po.locationId,
        locationName: po.locationName,
        supplierId: po.supplierId,
        supplierName: po.supplierName,
        mode: ReceivingMode.purchaseOrder,
        purchaseOrderId: po.id,
        purchaseOrderNumber: po.orderNumber,
        requestId: const Uuid().v4(),
        items: items,
      );

      if (!mounted) return;
      setState(() {
        _activeSession = session;
        _isLoading = false;
        _activeFilter = 'all';
      });

      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text(
            'Started goods receiving for ${po.orderNumber} (${items.length} items expected).',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('Failed to start receiving: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _startDirectInwardSession() {
    if (_directSupplierId == null || _directSupplierId!.isEmpty) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('Please select a supplier for direct inward.')),
      );
      return;
    }

    final locId = LocationScopeService.selectedLocationId.value ??
        LocationScopeService.currentForRead(widget.session);
    final locName = LocationScopeService.selectedLocation(widget.session)?.name ?? 'Store';

    if (locId == null) {
      ThqNotify.showSnackBar(
        context,
        const SnackBar(content: Text('Please select a location for direct inward.')),
      );
      return;
    }

    final invNum = _directSupplierInvoice.text.trim();
    final session = PurchaseReceivingSession(
      id: const Uuid().v4(),
      sessionName: 'Direct Inward • ${invNum.isNotEmpty ? invNum : "Unreferenced"}',
      tenantId: widget.session.business.id,
      locationId: locId,
      locationName: locName,
      supplierId: _directSupplierId!,
      supplierName: _directSupplierName ?? 'Supplier',
      mode: ReceivingMode.directInward,
      supplierDeliveryNote: _directDeliveryNote.text.trim(),
      requestId: const Uuid().v4(),
      items: [],
    );

    setState(() {
      _activeSession = session;
      _activeFilter = 'all';
    });
  }

  // --- Barcode Scanning & Identification ---

  void _onScanReceived(SmartScanResult scan) {
    if (_activeSession == null) return;
    _handleCodeScanned(scan.rawValue, source: scan.source);
  }

  Future<void> _handleCodeScanned(
    String rawCode, {
    ScannerSource source = ScannerSource.usb,
  }) async {
    final session = _activeSession;
    if (session == null) return;

    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty) return;

    // 1. Local match against session items
    PurchaseReceivingItem? matchedItem;
    for (final item in session.items) {
      if (item.barcode != null && item.barcode!.toLowerCase() == cleanCode.toLowerCase()) {
        matchedItem = item;
        break;
      }
      if (item.sku.toLowerCase() == cleanCode.toLowerCase()) {
        matchedItem = item;
        break;
      }
    }

    if (matchedItem != null) {
      setState(() {
        matchedItem!.increment(1.0);
      });
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text(
            'Received: ${matchedItem.productName} (${matchedItem.receivedQuantity.toInt()} of ${matchedItem.remainingExpectedQuantity.toInt()})',
          ),
          duration: const Duration(milliseconds: 1200),
        ),
      );
      return;
    }

    // 2. Resolve via Shared ProductIdentificationEngine
    try {
      final matchResult = await _identService.identifyCode(
        cleanCode,
        session: widget.session,
      );

      if (!mounted) return;

      if (matchResult.isExact && matchResult.primaryMatch != null) {
        final match = matchResult.primaryMatch!;
        setState(() {
          session.recordScanMatch(match, 1.0);
        });
        ThqNotify.showSnackBar(
          context,
          SnackBar(
            content: Text('Identified & Received: ${match.productName}'),
            duration: const Duration(milliseconds: 1200),
          ),
        );
      } else {
        setState(() {
          session.recordUnresolvedScan(
            cleanCode,
            source,
            matchResult.isNotFound
                ? 'Product not found in catalogue'
                : 'Ambiguous identifier match',
          );
        });
        ThqNotify.showSnackBar(
          context,
          SnackBar(
            content: Text('Unresolved barcode scan: $cleanCode'),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        session.recordUnresolvedScan(cleanCode, source, e.toString());
      });
    }
  }

  // --- Filtered Items View ---

  List<PurchaseReceivingItem> get _filteredItems {
    final session = _activeSession;
    if (session == null) return const [];

    var list = session.items;

    if (_activeFilter == 'pending') {
      list = list.where((i) => i.receivedQuantity == 0 && i.remainingExpectedQuantity > 0).toList();
    } else if (_activeFilter == 'received') {
      list = list.where((i) => i.receivedQuantity > 0).toList();
    } else if (_activeFilter == 'missing') {
      list = list.where((i) => i.isMissing).toList();
    } else if (_activeFilter == 'damaged_rejected') {
      list = list.where((i) => i.damagedQuantity > 0 || i.rejectedQuantity > 0).toList();
    } else if (_activeFilter == 'excess') {
      list = list.where((i) => i.excessQuantity > 0 || i.isUnexpected).toList();
    }

    if (_searchItemQuery.trim().isNotEmpty) {
      final q = _searchItemQuery.trim().toLowerCase();
      list = list.where((i) {
        return i.productName.toLowerCase().contains(q) ||
            i.sku.toLowerCase().contains(q) ||
            (i.barcode != null && i.barcode!.toLowerCase().contains(q));
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ThqBarcodeWedgeListener(
      controller: _scannerController,
      enabled: _activeSession != null,
      onScan: (code, source) => _handleCodeScanned(code, source: source),
      child: Scaffold(
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _activeSession == null
                ? _buildSetupView(colors)
                : _buildActiveReceivingView(colors),
      ),
    );
  }

  // --- Setup / PO Selection View ---

  Widget _buildSetupView(ColorScheme colors) {
    final sessionLocation = LocationScopeService.selectedLocation(widget.session);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Card(
            elevation: 0,
            color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.call_received, color: colors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Purchase Receiving & Inward',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              'Receive inventory against authorized Purchase Orders or direct supplier deliveries with physical discrepancy auditing.',
                              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      ThqStatusBadge(
                        status: ThqStatus.neutral,
                        label: sessionLocation?.name ?? 'Selected Location',
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('Purchase Orders'),
                        icon: Icon(Icons.receipt_long_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Direct Inward'),
                        icon: Icon(Icons.input, size: 16),
                      ),
                      ButtonSegment(
                        value: 2,
                        label: Text('GRN Audit History'),
                        icon: Icon(Icons.history, size: 16),
                      ),
                    ],
                    selected: {_setupSubTab},
                    onSelectionChanged: (set) {
                      setState(() => _setupSubTab = set.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Sub-tab content
          if (_setupSubTab == 0) _buildPurchaseOrdersList(colors),
          if (_setupSubTab == 1) _buildDirectInwardForm(colors),
          if (_setupSubTab == 2) _buildGrnHistoryList(colors),
        ],
      ),
    );
  }

  Widget _buildPurchaseOrdersList(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchPoController,
                decoration: InputDecoration(
                  hintText: 'Search by PO number or supplier name...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onSubmitted: (_) => _loadReceivableOrders(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _loadReceivableOrders,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_isLoadingOrders)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
        else if (_receivableOrders.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No open or partially received Purchase Orders found for this location.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _receivableOrders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final po = _receivableOrders[index];

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.description, color: colors.primary, size: 20),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          po.orderNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ThqStatusBadge(
                        status: po.status == 'partially_received'
                            ? ThqStatus.partial
                            : ThqStatus.processing,
                        label: po.status.replaceAll('_', ' ').toUpperCase(),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${po.supplierName} • Location: ${po.locationName} • Remaining: ${po.remainingReceiveQuantity.toInt()} of ${po.orderedQuantity.toInt()} units',
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                  trailing: FilledButton.icon(
                    onPressed: () => _startReceivingForPo(po),
                    icon: const Icon(Icons.qr_code_scanner, size: 16),
                    label: const Text('Receive Goods'),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDirectInwardForm(ColorScheme colors) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Direct Inward Receiving (Without Purchase Order)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'For ad-hoc supplier deliveries arriving with a direct invoice or delivery challan without a prior Purchase Order.',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // Supplier dropdown
            DropdownButtonFormField<String>(
              initialValue: _directSupplierId,
              decoration: const InputDecoration(
                labelText: 'Supplier',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _availableSuppliers
                  .map((s) => DropdownMenuItem(
                        value: s['id']?.toString(),
                        child: Text(s['name']?.toString() ?? 'Supplier'),
                      ))
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _directSupplierId = val;
                  _directSupplierName = _availableSuppliers
                      .firstWhere((s) => s['id'] == val, orElse: () => {})['name']
                      ?.toString();
                });
              },
            ),
            const SizedBox(height: 12),

            // Supplier Invoice Number
            TextField(
              controller: _directSupplierInvoice,
              decoration: const InputDecoration(
                labelText: 'Supplier Invoice Number / Reference',
                hintText: 'e.g. INV-98234',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),

            // Delivery Note
            TextField(
              controller: _directDeliveryNote,
              decoration: const InputDecoration(
                labelText: 'Delivery Challan / LR Number',
                hintText: 'e.g. DC-00441',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: _startDirectInwardSession,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Begin Inward Receiving'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrnHistoryList(ColorScheme colors) {
    if (_isLoadingGrns) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }

    if (_pastGrns.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No past Goods Receipt Notes (GRNs) recorded for this store.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _pastGrns.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final grn = _pastGrns[index];

          return ListTile(
            leading: Icon(
              grn.status == 'posted' ? Icons.check_circle : Icons.edit_note,
              color: grn.status == 'posted' ? Colors.green : Colors.orange,
            ),
            title: Row(
              children: [
                Text(
                  grn.grnNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  '(PO: ${grn.orderNumber})',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurfaceVariant),
                ),
              ],
            ),
            subtitle: Text(
              '${grn.supplierName} • Date: ${grn.receiptDate.toLocal().toString().substring(0, 10)} • Accepted: ${grn.acceptedQuantity.toInt()}${grn.damagedQuantity > 0 ? " • Damaged: ${grn.damagedQuantity.toInt()}" : ""}',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            trailing: ThqStatusBadge(
              status: grn.status == 'posted' ? ThqStatus.completed : ThqStatus.draft,
              label: grn.status.toUpperCase(),
            ),
          );
        },
      ),
    );
  }

  // --- Active Receiving View ---

  Widget _buildActiveReceivingView(ColorScheme colors) {
    final session = _activeSession!;
    final summary = session.summary;
    final filtered = _filteredItems;

    return Column(
      children: [
        // Camera Viewfinder (if open)
        if (_isCameraOpen)
          Container(
            height: 240,
            color: Colors.black,
            child: ThqSmartScannerView(
              controller: _scannerController,
              onScan: (scan) => _handleCodeScanned(scan.rawValue, source: ScannerSource.camera),
              onClose: () => setState(() => _isCameraOpen = false),
            ),
          ),

        // Session Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.sessionName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ThqStatusBadge(
                          status: session.mode == ReceivingMode.purchaseOrder
                              ? ThqStatus.processing
                              : ThqStatus.neutral,
                          label: session.mode == ReceivingMode.purchaseOrder ? 'PO INWARD' : 'DIRECT',
                        ),
                      ],
                    ),
                    Text(
                      'Supplier: ${session.supplierName} • Location: ${session.locationName}',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(_isCameraOpen ? Icons.camera_alt : Icons.camera_alt_outlined),
                tooltip: _isCameraOpen ? 'Close Camera' : 'Open Camera Viewfinder',
                onPressed: () => setState(() => _isCameraOpen = !_isCameraOpen),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() => _activeSession = null),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: summary.totalReceivedQuantity > 0 ? _openReviewAndApprovalDialog : null,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Review & Post Inward'),
              ),
            ],
          ),
        ),

        // Progress Metric Badges
        Container(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.25),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildProgressChip('Ordered', '${summary.totalOrderedQuantity.toInt()}', colors.onSurface),
                const SizedBox(width: 6),
                _buildProgressChip(
                  'Received',
                  '${summary.totalReceivedQuantity.toInt()} (${summary.completionPercentage.toInt()}%)',
                  Colors.blue,
                ),
                const SizedBox(width: 6),
                _buildProgressChip('Accepted', '${summary.totalAcceptedQuantity.toInt()}', Colors.green),
                const SizedBox(width: 6),
                _buildProgressChip('Complete Lines', '${summary.fullyReceivedLines}', Colors.teal),
                if (summary.missingLines > 0) ...[
                  const SizedBox(width: 6),
                  _buildProgressChip('Missing Lines', '${summary.missingLines}', Colors.red),
                ],
                if (summary.totalDamagedQuantity > 0) ...[
                  const SizedBox(width: 6),
                  _buildProgressChip('Damaged', '${summary.totalDamagedQuantity.toInt()}', Colors.deepOrange),
                ],
                if (summary.totalRejectedQuantity > 0) ...[
                  const SizedBox(width: 6),
                  _buildProgressChip('Rejected', '${summary.totalRejectedQuantity.toInt()}', Colors.pink),
                ],
                if (summary.excessLines > 0 || summary.unexpectedLines > 0) ...[
                  const SizedBox(width: 6),
                  _buildProgressChip(
                    'Excess / Extra',
                    '${summary.excessLines + summary.unexpectedLines}',
                    Colors.purple,
                  ),
                ],
                if (summary.unresolvedScanCount > 0) ...[
                  const SizedBox(width: 6),
                  _buildProgressChip('Unresolved Scans', '${summary.unresolvedScanCount}', Colors.amber.shade900),
                ],
              ],
            ),
          ),
        ),

        // Search & Barcode Input Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualInput,
                  focusNode: _manualFocus,
                  decoration: InputDecoration(
                    hintText: 'Scan or enter SKU / Barcode / Name...',
                    prefixIcon: const Icon(Icons.qr_code_scanner, size: 20),
                    isDense: true,
                    suffixIcon: _manualInput.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _manualInput.clear();
                              setState(() => _searchItemQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (val) {
                    _handleCodeScanned(val, source: ScannerSource.manual);
                    _manualInput.clear();
                    _manualFocus.requestFocus();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () {
                  final text = _manualInput.text.trim();
                  if (text.isNotEmpty) {
                    _handleCodeScanned(text, source: ScannerSource.manual);
                    _manualInput.clear();
                    _manualFocus.requestFocus();
                  }
                },
                child: const Text('Enter'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    for (final item in session.items) {
                      item.matchRemaining();
                    }
                  });
                },
                icon: const Icon(Icons.done_all, size: 16),
                label: const Text('Receive All'),
              ),
            ],
          ),
        ),

        // Filter Chips Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text('All (${session.items.length})'),
                  selected: _activeFilter == 'all',
                  onSelected: (_) => setState(() => _activeFilter = 'all'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Pending (${summary.missingLines})'),
                  selected: _activeFilter == 'pending',
                  onSelected: (_) => setState(() => _activeFilter = 'pending'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Received (${summary.totalReceivedLines})'),
                  selected: _activeFilter == 'received',
                  onSelected: (_) => setState(() => _activeFilter = 'received'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Missing (${summary.missingLines})'),
                  selected: _activeFilter == 'missing',
                  onSelected: (_) => setState(() => _activeFilter = 'missing'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Damaged / Rejected (${summary.totalDamagedQuantity > 0 || summary.totalRejectedQuantity > 0 ? "!" : "0"})'),
                  selected: _activeFilter == 'damaged_rejected',
                  onSelected: (_) => setState(() => _activeFilter = 'damaged_rejected'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Excess / Extra (${summary.excessLines + summary.unexpectedLines})'),
                  selected: _activeFilter == 'excess',
                  onSelected: (_) => setState(() => _activeFilter = 'excess'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Product Items Table
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No receiving lines match the selected filter.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildReceivingRow(item, colors);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReceivingRow(PurchaseReceivingItem item, ColorScheme colors) {
    Color statusColor;
    String statusLabel;

    switch (item.status) {
      case ReceivingItemStatus.complete:
        statusColor = Colors.green;
        statusLabel = 'Complete';
      case ReceivingItemStatus.partial:
        statusColor = Colors.orange;
        statusLabel = 'Partial';
      case ReceivingItemStatus.excess:
        statusColor = Colors.purple;
        statusLabel = 'Excess (+${item.excessQuantity.toInt()})';
      case ReceivingItemStatus.unexpected:
        statusColor = Colors.deepOrange;
        statusLabel = 'Unexpected';
      case ReceivingItemStatus.pending:
        statusColor = Colors.grey;
        statusLabel = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: item.receivedQuantity > 0 ? colors.primary.withValues(alpha: 0.02) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Status Indicator Dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),

              // Product Info
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'SKU: ${item.sku}${item.barcode != null ? " • Barcode: ${item.barcode}" : ""}',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Right-side actions and quantities (horizontally scrollable if screen is narrow)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Expected / Ordered Qty
                    SizedBox(
                      width: 80,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Remaining', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text(
                            '${item.remainingExpectedQuantity.toInt()} ${item.unitName}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Stepper Controls
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 14),
                          onPressed: item.receivedQuantity > 0 ? () => setState(() => item.decrement(1)) : null,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        ),
                        Container(
                          width: 44,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.outlineVariant),
                            borderRadius: BorderRadius.circular(4),
                            color: colors.surface,
                          ),
                          child: Text(
                            item.receivedQuantity > 0 ? '${item.receivedQuantity.toInt()}' : '0',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: item.receivedQuantity > 0 ? colors.primary : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 14),
                          onPressed: () => setState(() => item.increment(1)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),

                    // Status Badge
                    Container(
                      width: 70,
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        statusLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Quick "Receive All" Match Button
                    if (item.remainingExpectedQuantity > 0)
                      TextButton(
                        onPressed: () => setState(() => item.matchRemaining()),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        child: const Text('Match', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // Damaged & Rejected Info Tag (if present)
          if (item.damagedQuantity > 0 || item.rejectedQuantity > 0)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 4),
              child: Row(
                children: [
                  if (item.damagedQuantity > 0)
                    Text(
                      'Damaged: ${item.damagedQuantity.toInt()} (${item.damageNote ?? "No notes"}) • ',
                      style: const TextStyle(fontSize: 11, color: Colors.deepOrange),
                    ),
                  if (item.rejectedQuantity > 0)
                    Text(
                      'Rejected: ${item.rejectedQuantity.toInt()} (${item.rejectionReason ?? "No reason"})',
                      style: const TextStyle(fontSize: 11, color: Colors.pink),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 11, color: color)),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // --- Review & Approval Dialog ---

  Future<void> _openReviewAndApprovalDialog() async {
    final session = _activeSession;
    if (session == null) return;

    final summary = session.summary;
    final deliveryNoteController = TextEditingController(text: session.supplierDeliveryNote ?? '');
    final notesController = TextEditingController(text: session.notes ?? '');
    bool confirmed = false;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_turned_in, color: Colors.blue),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Review & Approve Goods Receipt',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Supplier and Order reference
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Supplier: ${session.supplierName}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            if (session.purchaseOrderNumber != null)
                              Text(
                                'Purchase Order: ${session.purchaseOrderNumber}',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                              ),
                            Text(
                              'Receiving Location: ${session.locationName}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Warnings
                      if (summary.missingLines > 0)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber, color: Colors.amber.shade900, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Partial Delivery: ${summary.missingLines} items are not fully received. The PO status will be set to "Partially Received".',
                                  style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (summary.excessLines > 0 || summary.unexpectedLines > 0)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.purple.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.purple.shade900, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Notice: ${summary.excessLines + summary.unexpectedLines} items exceed PO quantities. Items within the PO will be received on the GRN.',
                                  style: TextStyle(fontSize: 11, color: Colors.purple.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Metrics Grid
                      Row(
                        children: [
                          _buildMetricBox('Accepted', '${summary.totalAcceptedQuantity.toInt()}', Colors.green),
                          const SizedBox(width: 8),
                          _buildMetricBox('Damaged', '${summary.totalDamagedQuantity.toInt()}', Colors.deepOrange),
                          const SizedBox(width: 8),
                          _buildMetricBox('Rejected', '${summary.totalRejectedQuantity.toInt()}', Colors.pink),
                          const SizedBox(width: 8),
                          _buildMetricBox('Missing Lines', '${summary.missingLines}', Colors.red),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Delivery Note / Challan
                      TextField(
                        controller: deliveryNoteController,
                        decoration: const InputDecoration(
                          labelText: 'Supplier Delivery Note / Challan No.',
                          hintText: 'e.g. DN-2026-991',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Receiving Notes
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Receiving Remarks / Notes',
                          hintText: 'e.g. Received intact, driver name, vehicle number...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      // Non-Destructive Accounting Guarantee
                      Text(
                        'Posting will record received items in the inventory movement ledger, update location stock balances atomically, and post the Goods Receipt Note.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 12),

                      // Explicit Confirmation Checkbox
                      CheckboxListTile(
                        value: confirmed,
                        onChanged: (v) => setDialogState(() => confirmed = v ?? false),
                        title: const Text(
                          'I confirm that all received items have been physically inspected and verified.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Back to Receiving'),
                ),
                FilledButton.icon(
                  onPressed: confirmed && _canReceiveAndPost
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Confirm & Post Receipt'),
                ),
              ],
            );
          },
        );
      },
    );

    if (approved == true) {
      await _executePostReceipt(
        deliveryNote: deliveryNoteController.text.trim(),
        notes: notesController.text.trim(),
      );
    }
  }

  Widget _buildMetricBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  // --- Execution & Posting ---

  Future<void> _executePostReceipt({
    required String deliveryNote,
    required String notes,
  }) async {
    final session = _activeSession;
    if (session == null) return;

    if (!_canReceiveAndPost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Access Denied: purchases.receive, purchases.manage, or inventory.manage permission required to post receipts.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? deviceId;
      try {
        final activation = await DeviceInstallationService()
            .readActivation()
            .timeout(const Duration(milliseconds: 150), onTimeout: () => null);
        deviceId = activation?.deviceId;
      } catch (_) {}

      if (session.mode == ReceivingMode.purchaseOrder) {
        final payload = session.toGrnPayload();
        if (payload.isEmpty) {
          throw StateError('Cannot post a goods receipt with zero received items on the PO.');
        }

        final result = await _receivingService.createAndPostGoodsReceipt(
          tenantId: widget.session.business.id,
          purchaseOrderId: session.purchaseOrderId!,
          items: payload,
          supplierDeliveryNote: deliveryNote,
          notes: notes,
          deviceId: deviceId,
        );

        final grnNumber = result['grn_number']?.toString() ?? 'GRN';
        final poStatus = result['purchase_order_status']?.toString() ?? 'received';

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _activeSession = null;
          _setupSubTab = 2; // Jump to GRN history
        });

        _loadPastGrns();
        _loadReceivableOrders();

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Goods Receipt Posted'),
              ],
            ),
            content: Text(
              'Goods Receipt $grnNumber has been posted successfully!\n\n'
              'Stock balances have been updated in the inventory ledger and Purchase Order status is now "${poStatus.replaceAll('_', ' ').toUpperCase()}".',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        // Direct Inward Mode
        final itemsPayload = session.items
            .where((i) => i.acceptedQuantity + i.damagedQuantity > 0)
            .map((i) => i.toDirectInwardItemMap())
            .toList();

        if (itemsPayload.isEmpty) {
          throw StateError('Cannot post a direct receipt with 0 received items.');
        }

        final result = await _receivingService.postDirectInwardReceipt(
          tenantId: widget.session.business.id,
          supplierId: session.supplierId,
          supplierInvoiceNumber: deliveryNote.isNotEmpty ? deliveryNote : 'INWARD-${DateTime.now().millisecondsSinceEpoch}',
          receiptDate: session.receiptDate,
          items: itemsPayload,
          notes: notes,
          locationId: session.locationId,
          requestId: session.requestId,
        );

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _activeSession = null;
        });

        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Direct Inward Posted'),
              ],
            ),
            content: Text(
              'Direct purchase receipt ${result['purchase_number'] ?? result['invoice_number'] ?? 'Posted'} completed successfully!\n\n'
              'Stock balances and financial vouchers have been posted to the ledger.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('Failed to post goods receipt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
