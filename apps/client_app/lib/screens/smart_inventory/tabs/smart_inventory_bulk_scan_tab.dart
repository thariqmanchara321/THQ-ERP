import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';
import '../../../services/location_scope_service.dart';

class SmartInventoryBulkScanTab extends StatefulWidget {
  final ClientSession session;

  const SmartInventoryBulkScanTab({super.key, required this.session});

  @override
  State<SmartInventoryBulkScanTab> createState() =>
      _SmartInventoryBulkScanTabState();
}

class _SmartInventoryBulkScanTabState extends State<SmartInventoryBulkScanTab>
    with SingleTickerProviderStateMixin {
  final ClientSmartInventoryService _inventoryService =
      ClientSmartInventoryService.instance;

  late final SmartScannerController _scannerController;
  final TextEditingController _manualInput = TextEditingController();
  final FocusNode _manualFocus = FocusNode();

  bool _isCameraOpen = false;
  bool _isProcessing = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _scannerController = SmartScannerController(
      configuration: const ScannerConfiguration(
        mode: ScannerMode.continuous,
        duplicateSuppressionDuration: Duration(milliseconds: 900),
      ),
    );

    _scannerController.scans.listen(_onScanReceived);
    _scannerController.start();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    _manualInput.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  void _onScanReceived(SmartScanResult scan) {
    _handleCode(scan.rawValue, source: scan.source, format: scan.format);
  }

  Future<void> _handleCode(
    String code, {
    ScannerSource source = ScannerSource.usb,
    SmartBarcodeFormat format = SmartBarcodeFormat.unknown,
  }) async {
    final session = _inventoryService.activeBulkSession;
    if (session == null || _isProcessing) return;

    final clean = code.trim();
    if (clean.isEmpty) return;

    setState(() => _isProcessing = true);

    try {
      final scanResult = SmartScanResult.valid(
        rawValue: clean,
        source: source,
        format: format,
      );

      final result = await _inventoryService.identifyScan(
        scanResult,
        session: widget.session,
        locationId: session.locationId,
      );

      if (mounted) {
        setState(() {
          if (result.isExact && result.primaryMatch != null) {
            session.addOrIncrementMatch(result.primaryMatch!);
          } else if (result.isAmbiguous && result.matches.isNotEmpty) {
            // Under bulk scanning, if ambiguity occurs, add highest priority or record
            session.addOrIncrementMatch(result.matches.first);
          } else {
            session.addUnresolved(clean, source, result.errorMessage);
          }
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          session.addUnresolved(clean, source, e.toString());
          _isProcessing = false;
        });
      }
    }
  }

  void _submitManual() {
    final text = _manualInput.text;
    _manualInput.clear();
    _handleCode(text, source: ScannerSource.manual);
    _manualFocus.requestFocus();
  }

  void _startSession() {
    final selected = LocationScopeService.selectedLocation(widget.session);
    final title = 'Bulk Count - ${selected?.name ?? "All Stores"}';
    setState(() {
      _inventoryService.startBulkSession(
        session: widget.session,
        locationId: selected?.id,
        locationName: selected?.name,
        title: title,
      );
    });
  }

  void _finishSession() {
    final active = _inventoryService.activeBulkSession;
    if (active == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish Bulk Scanning Session?'),
        content: Text(
          'This will record the session of ${active.totalDistinctProducts} products (${active.totalQuantity.toStringAsFixed(0)} units total) into your local scan history. No inventory stock balances will be changed.',
        ),
        actions: [
          ThqSecondaryButton(
            label: 'Keep Scanning',
            onPressed: () => Navigator.of(context).pop(),
          ),
          ThqPrimaryButton(
            label: 'Finish & Record',
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _inventoryService.finishBulkSession();
              });
              ThqNotify.showSnackBar(
                context,
                const SnackBar(content: Text('Bulk scanning session completed and saved to history.')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _cancelSession() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Active Session?'),
        content: const Text(
          'Are you sure you want to discard this temporary scan session? All scanned items in this list will be cleared.',
        ),
        actions: [
          ThqSecondaryButton(
            label: 'Keep Session',
            onPressed: () => Navigator.of(context).pop(),
          ),
          ThqDangerButton(
            label: 'Discard Session',
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _inventoryService.cancelBulkSession();
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = _inventoryService.activeBulkSession;
    final colors = Theme.of(context).colorScheme;

    if (activeSession == null) {
      return Center(
        child: ThqCard(
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.playlist_add_check, size: 54, color: colors.primary),
                const SizedBox(height: 16),
                Text(
                  'Bulk Scanning Workspace',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Collect, audit, and count multiple items continuously without posting stock adjustments or financial entries.',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ThqPrimaryButton(
                    icon: Icons.play_arrow,
                    label: 'Start New Bulk Scan Session',
                    onPressed: _startSession,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ThqBarcodeWedgeListener(
      controller: _scannerController,
      onScan: (code, source) => _handleCode(code, source: source),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session Header Card
            ThqCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                activeSession.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(width: 10),
                              const ThqStatusBadge(
                                status: ThqStatus.processing,
                                label: 'Continuous Mode',
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Location: ${activeSession.locationName ?? "All Stores"} • Operator: ${activeSession.operatorName} • Staging only (no stock mutation)',
                            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        ThqSecondaryButton(
                          icon: _isCameraOpen ? Icons.videocam_off : Icons.videocam,
                          label: _isCameraOpen ? 'Close Cam' : 'Camera View',
                          onPressed: () {
                            setState(() => _isCameraOpen = !_isCameraOpen);
                          },
                        ),
                        const SizedBox(width: 8),
                        ThqSecondaryButton(
                          icon: Icons.close,
                          label: 'Cancel',
                          onPressed: _cancelSession,
                        ),
                        const SizedBox(width: 8),
                        ThqPrimaryButton(
                          icon: Icons.done_all,
                          label: 'Finish Session',
                          onPressed: _finishSession,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Live Camera Viewfinder (if toggled)
            if (_isCameraOpen) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 180,
                  child: ThqSmartScannerView(
                    controller: _scannerController,
                    onScan: (scan) => _onScanReceived(scan),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Fast Manual Input Bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualInput,
                    focusNode: _manualFocus,
                    onSubmitted: (_) => _submitManual(),
                    decoration: InputDecoration(
                      hintText: 'Scan with hardware gun or type barcode & hit Enter...',
                      prefixIcon: const Icon(Icons.qr_code_scanner, size: 18),
                      suffixIcon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ThqPrimaryButton(
                  label: 'Add',
                  icon: Icons.add,
                  onPressed: _submitManual,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tabs: Identified Products vs Unresolved
            TabBar(
              controller: _tabController,
              labelColor: colors.primary,
              indicatorColor: colors.primary,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Identified Items'),
                      const SizedBox(width: 8),
                      Badge(
                        label: Text('${activeSession.totalDistinctProducts}'),
                        backgroundColor: colors.primary,
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Unresolved Scans'),
                      if (activeSession.totalUnresolved > 0) ...[
                        const SizedBox(width: 8),
                        Badge(
                          label: Text('${activeSession.totalUnresolved}'),
                          backgroundColor: Colors.orange,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Identified Products
                  activeSession.items.isEmpty
                      ? Center(
                          child: Text(
                            'Scan barcodes to accumulate items into this session.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        )
                      : ThqCard(
                          child: ListView.separated(
                            itemCount: activeSession.items.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = activeSession.items[index];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  item.productName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  'SKU: ${item.sku}${item.barcode != null ? " • Barcode: ${item.barcode}" : ""}',
                                  style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      onPressed: () {
                                        setState(() => item.decrement(1.0));
                                        if (item.quantity <= 0) {
                                          setState(() => activeSession.removeItem(item.variantId));
                                        }
                                      },
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${item.quantity.toStringAsFixed(0)} ${item.unitCode}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: colors.primary,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20),
                                      onPressed: () {
                                        setState(() => item.increment(1.0));
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      onPressed: () {
                                        setState(() => activeSession.removeItem(item.variantId));
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                  // Tab 2: Unresolved Scans
                  activeSession.unresolvedScans.isEmpty
                      ? Center(
                          child: Text(
                            'No unresolved scans in this session.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        )
                      : ThqCard(
                          child: ListView.separated(
                            itemCount: activeSession.unresolvedScans.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final unresolved = activeSession.unresolvedScans[index];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.help_outline, color: Colors.orange),
                                title: Text(
                                  unresolved.rawCode,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Text(
                                  'Source: ${unresolved.source.name} • Note: ${unresolved.note ?? "Not in catalog"}',
                                  style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ThqSecondaryButton(
                                      label: 'Retry',
                                      onPressed: () => _handleCode(unresolved.rawCode, source: unresolved.source),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      onPressed: () {
                                        setState(() => activeSession.removeUnresolved(unresolved.id));
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
