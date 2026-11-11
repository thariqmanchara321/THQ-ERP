import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../models/client_session.dart';
import '../../../services/client_smart_inventory_service.dart';
import '../../../services/device_installation_service.dart';
import '../../../services/location_scope_service.dart';
import '../../../services/stock_counting_service.dart';

/// Physical Stock Counting & Reconciliation Workspace Tab (Phase 9).
///
/// Features:
/// 1. Snapshot capture of expected system quantities.
/// 2. Barcode/RFID hardware gun wedge & mobile/webcam camera scanning.
/// 3. Real-time variance tracking (Shortage, Excess, Matched).
/// 4. Discrepancy investigation and count correction.
/// 5. Approval separation and idempotent posting through `inventory_stock_count_post_v485`.
/// 6. Historical audit review of past counts.
class SmartInventoryStockCountTab extends StatefulWidget {
  final ClientSession session;
  final StockCountSession? initialSession;

  const SmartInventoryStockCountTab({
    super.key,
    required this.session,
    this.initialSession,
  });

  @override
  State<SmartInventoryStockCountTab> createState() =>
      _SmartInventoryStockCountTabState();
}

class _SmartInventoryStockCountTabState
    extends State<SmartInventoryStockCountTab> {
  final StockCountingService _stockService = StockCountingService.instance;
  final ClientSmartInventoryService _identService =
      ClientSmartInventoryService.instance;

  late final SmartScannerController _scannerController;
  final TextEditingController _manualInput = TextEditingController();
  final FocusNode _manualFocus = FocusNode();

  // Active Session State
  StockCountSession? _activeSession;
  bool _isLoading = false;
  bool _isCameraOpen = false;

  // Filters & Search
  String _searchQuery = '';
  String _activeFilter = 'all'; // 'all', 'pending', 'shortage', 'excess', 'matched', 'unresolved'

  // Past Audit Records
  List<StockCountAuditRecord> _pastCounts = [];
  bool _isLoadingHistory = false;
  bool _showHistoryView = false;

  bool get _canApproveAndPost =>
      widget.session.hasPermission('inventory.stock_count') ||
      widget.session.hasPermission('inventory.manage') ||
      widget.session.hasRole('owner');

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
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _manualInput.dispose();
    _manualFocus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final locId = LocationScopeService.selectedLocationId.value ??
          LocationScopeService.currentForRead(widget.session);

      final list = await _stockService.listPastCounts(
        tenantId: widget.session.business.id,
        locationId: locId,
      );
      if (!mounted) return;
      setState(() {
        _pastCounts = list;
        _isLoadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
    }
  }

  // --- Session Initiation & Snapshot ---

  Future<void> _startNewCount({
    required String sessionName,
    String? locationId,
    String? locationName,
    String filterQuery = '',
  }) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final loc = locationId ??
          LocationScopeService.selectedLocationId.value ??
          LocationScopeService.currentForRead(widget.session);

      if (loc == null || loc.isEmpty) {
        throw StateError('Please select a business location for this count.');
      }

      final items = await _stockService.fetchSnapshot(
        tenantId: widget.session.business.id,
        locationId: loc,
        query: filterQuery,
      );

      final session = StockCountSession(
        id: const Uuid().v4(),
        countNumber: 'DRAFT-${DateTime.now().millisecondsSinceEpoch % 1000000}',
        tenantId: widget.session.business.id,
        locationId: loc,
        locationName: locationName ??
            LocationScopeService.selectedLocation(widget.session)?.name ??
            'Selected Location',
        sessionName: sessionName.trim().isEmpty
            ? 'Stock Count - ${DateTime.now().toLocal().toString().substring(0, 16)}'
            : sessionName.trim(),
        requestId: const Uuid().v4(),
        items: items,
        createdByName: widget.session.username,
      );

      if (!mounted) return;
      setState(() {
        _activeSession = session;
        _isLoading = false;
        _showHistoryView = false;
      });

      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text(
            'Stock count started with ${items.length} expected products in snapshot.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start stock count: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // --- Barcode Scanning & Identification ---

  void _onScanReceived(SmartScanResult scan) {
    if (_activeSession == null) return;
    _handleCodeScanned(scan.rawValue, source: scan.source);
  }

  Future<void> _handleCodeScanned(
    String rawCode, {
    ScannerSource source = ScannerSource.manual,
  }) async {
    final session = _activeSession;
    if (session == null) return;

    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty) return;

    // 1. Direct fast lookup in snapshot items by SKU or Barcode
    StockCountItem? matchedItem;
    for (final item in session.items) {
      if (item.barcode != null && item.barcode!.trim() == cleanCode) {
        matchedItem = item;
        break;
      }
      if (item.sku.trim().toLowerCase() == cleanCode.toLowerCase()) {
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
            'Counted: ${matchedItem.productName} (${matchedItem.countedQuantity.toInt()})',
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
            content: Text('Identified & Counted: ${match.productName}'),
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
            content: Text('Unresolved scan: $cleanCode'),
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

  List<StockCountItem> get _filteredItems {
    final session = _activeSession;
    if (session == null) return const [];

    var list = session.items;

    if (_activeFilter == 'pending') {
      list = list.where((i) => !i.isCounted).toList();
    } else if (_activeFilter == 'shortage') {
      list = list.where((i) => i.isCounted && i.variance < -0.0001).toList();
    } else if (_activeFilter == 'excess') {
      list = list.where((i) => i.isCounted && i.variance > 0.0001).toList();
    } else if (_activeFilter == 'matched') {
      list = list.where((i) => i.isCounted && i.variance.abs() <= 0.0001).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((i) {
        return i.productName.toLowerCase().contains(q) ||
            i.sku.toLowerCase().contains(q) ||
            (i.barcode ?? '').toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  // --- Review & Reconciliation Workflow ---

  Future<void> _openReviewAndApprovalDialog() async {
    final session = _activeSession;
    if (session == null) return;

    final summary = session.summary;
    final notesController = TextEditingController(text: session.notes ?? '');
    bool confirmed = false;

    // Check for concurrent stock changes that occurred since snapshot
    final concurrentChanges = await _stockService.checkConcurrentStockChanges(
      tenantId: widget.session.business.id,
      locationId: session.locationId,
      originalItems: session.items,
    );

    if (!mounted) return;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.assignment_turned_in, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text('Review & Approve Stock Count'),
                ],
              ),
              content: SizedBox(
                width: 600,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Concurrent movements warning
                      if (concurrentChanges.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber, color: Colors.amber.shade900),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Warning: ${concurrentChanges.length} products had stock movements (sales/receipts) during counting. Adjustments will reconcile to your physical count.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Summary Metrics
                      Row(
                        children: [
                          _buildMetricBox('Counted', '${summary.countedItems}', Colors.blue),
                          const SizedBox(width: 8),
                          _buildMetricBox('Matched', '${summary.matchedItems}', Colors.green),
                          const SizedBox(width: 8),
                          _buildMetricBox('Shortages', '${summary.shortageItems}', Colors.red),
                          const SizedBox(width: 8),
                          _buildMetricBox('Excess', '${summary.excessItems}', Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Text(
                        'Total Net Variance: ${summary.netVarianceQuantity >= 0 ? "+" : ""}${summary.netVarianceQuantity.toStringAsFixed(1)} units',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 12),

                      // Reconciliation Notes
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Audit & Reconciliation Notes',
                          hintText: 'e.g. Broken tiles discarded, found excess cement pallets...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),

                      // Non-Destructive Accounting Guarantee
                      Text(
                        'Posting will create an approved stock adjustment via inventory_stock_count_post_v485, recording the movement in the inventory ledger and updating location balances atomically.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Explicit Confirmation Checkbox
                      CheckboxListTile(
                        value: confirmed,
                        onChanged: (v) => setDialogState(() => confirmed = v ?? false),
                        title: const Text(
                          'I confirm this physical count is verified and approve posting adjustments.',
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
                  child: const Text('Back to Counting'),
                ),
                FilledButton.icon(
                  onPressed: confirmed && _canApproveAndPost
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Post Adjustments'),
                ),
              ],
            );
          },
        );
      },
    );

    if (approved == true) {
      await _executePostStockCount(notesController.text.trim());
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

  // --- Post Stock Count Execution ---

  Future<void> _executePostStockCount(String notes) async {
    final session = _activeSession;
    if (session == null) return;

    setState(() => _isLoading = true);
    try {
      final payload = session.toPostPayload();
      if (payload.isEmpty) {
        throw StateError('Cannot post a count with 0 counted items.');
      }

      String? deviceId;
      try {
        final activation = await DeviceInstallationService()
            .readActivation()
            .timeout(const Duration(milliseconds: 150), onTimeout: () => null);
        deviceId = activation?.deviceId;
      } catch (_) {}

      final result = await _stockService.postStockCount(
        tenantId: widget.session.business.id,
        locationId: session.locationId,
        items: payload,
        notes: notes,
        deviceId: deviceId,
        requestId: session.requestId,
      );

      final postedCountNumber = result['count_number']?.toString() ?? session.countNumber;

      if (!mounted) return;
      setState(() {
        session.status = StockCountStatus.posted;
        session.countNumber = postedCountNumber;
        session.postedAt = DateTime.now();
        _isLoading = false;
        _activeSession = null;
        _showHistoryView = true;
      });

      _loadHistory();

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Stock Count Posted'),
            ],
          ),
          content: Text(
            'Stock count $postedCountNumber has been posted successfully!\n\n'
            'Inventory movements have been posted to the movement ledger, and location stock balances have been updated.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text('Failed to post stock count: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- Main Build ---

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activeSession == null || _showHistoryView) {
      return _buildInactiveOrHistoryView(colors);
    }

    return ThqBarcodeWedgeListener(
      controller: _scannerController,
      child: _buildActiveCountView(colors),
    );
  }

  // --- Inactive / Start Session View ---

  Widget _buildInactiveOrHistoryView(ColorScheme colors) {
    final sessionLocation = LocationScopeService.selectedLocation(widget.session);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Launch Count Card
          ThqCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
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
                        child: Icon(Icons.inventory_2, color: colors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Physical Stock Count & Reconciliation',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              'Audit store stock, capture snapshot quantities, scan physical items, and post reconciled adjustments.',
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
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _showStartCountDialog(),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start New Stock Count'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadHistory,
                        icon: const Icon(Icons.history),
                        label: const Text('Refresh Past Counts'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Historical Counts Table Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Historical Stock Counts & Audits',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (_isLoadingHistory)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_pastCounts.isEmpty && !_isLoadingHistory)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No historical stock counts found for this location.',
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
                itemCount: _pastCounts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final record = _pastCounts[index];
                  final hadVariance = record.totalVariance.abs() > 0.0001;

                  return ListTile(
                    leading: Icon(
                      hadVariance ? Icons.rule : Icons.check_circle,
                      color: hadVariance ? Colors.orange : Colors.green,
                    ),
                    title: Text(
                      record.countNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                      '${record.locationName} • ${record.lineCount} items • Created: ${record.createdAt.toLocal().toString().substring(0, 16)}',
                      style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Variance: ${record.totalVariance >= 0 ? "+" : ""}${record.totalVariance.toInt()}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: hadVariance ? Colors.orange.shade800 : Colors.green.shade800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ThqStatusBadge(
                          status: record.status == 'posted' ? ThqStatus.completed : ThqStatus.draft,
                          label: record.status.toUpperCase(),
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
  }

  Future<void> _showStartCountDialog() async {
    final nameController = TextEditingController(
      text: 'Stock Count - ${DateTime.now().toLocal().toString().substring(0, 10)}',
    );
    final filterController = TextEditingController();

    final started = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Stock Count Session'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Session Reference / Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: filterController,
                decoration: const InputDecoration(
                  labelText: 'Product / Category Filter (Optional)',
                  hintText: 'Leave empty for all store products',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Starting a count will capture a snapshot of current system stock levels for reconciliation.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Capture Snapshot & Begin'),
          ),
        ],
      ),
    );

    if (started == true) {
      await _startNewCount(
        sessionName: nameController.text,
        filterQuery: filterController.text,
      );
    }
  }

  // --- Active Count View ---

  Widget _buildActiveCountView(ColorScheme colors) {
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
                        Text(
                          session.sessionName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${session.countNumber})',
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Text(
                      'Location: ${session.locationName} • Started: ${session.createdAt.toLocal().toString().substring(0, 16)}',
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
                child: const Text('Save Draft & Exit'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: summary.countedItems > 0 ? _openReviewAndApprovalDialog : null,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Review & Post'),
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
                _buildProgressChip('Expected', '${summary.totalItems}', colors.onSurface),
                const SizedBox(width: 6),
                _buildProgressChip('Counted', '${summary.countedItems} (${summary.completionPercentage.toInt()}%)', Colors.blue),
                const SizedBox(width: 6),
                _buildProgressChip('Matched', '${summary.matchedItems}', Colors.green),
                const SizedBox(width: 6),
                _buildProgressChip('Shortages', '${summary.shortageItems}', Colors.red),
                const SizedBox(width: 6),
                _buildProgressChip('Excess', '${summary.excessItems}', Colors.purple),
                if (summary.unresolvedCount > 0) ...[
                  const SizedBox(width: 6),
                  _buildProgressChip('Unresolved', '${summary.unresolvedCount}', Colors.orange),
                ],
              ],
            ),
          ),
        ),

        // Search & Filter Toolbar
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
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    suffixIcon: _manualInput.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _manualInput.clear();
                              setState(() => _searchQuery = '');
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
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  if (_manualInput.text.isNotEmpty) {
                    _handleCodeScanned(_manualInput.text, source: ScannerSource.manual);
                    _manualInput.clear();
                  }
                },
                child: const Text('Enter'),
              ),
            ],
          ),
        ),

        // Filter Chips Bar
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
                  label: Text('Pending (${summary.uncountedItems})'),
                  selected: _activeFilter == 'pending',
                  onSelected: (_) => setState(() => _activeFilter = 'pending'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Shortages (${summary.shortageItems})'),
                  selected: _activeFilter == 'shortage',
                  onSelected: (_) => setState(() => _activeFilter = 'shortage'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Excess (${summary.excessItems})'),
                  selected: _activeFilter == 'excess',
                  onSelected: (_) => setState(() => _activeFilter = 'excess'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: Text('Matched (${summary.matchedItems})'),
                  selected: _activeFilter == 'matched',
                  onSelected: (_) => setState(() => _activeFilter = 'matched'),
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
                    'No products match the selected filter.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final variance = item.variance;

                    Color varianceColor = Colors.grey;
                    if (item.isCounted) {
                      if (variance.abs() <= 0.0001) {
                        varianceColor = Colors.green;
                      } else if (variance < 0) {
                        varianceColor = Colors.red;
                      } else {
                        varianceColor = Colors.purple;
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        color: item.isCounted
                            ? colors.primary.withValues(alpha: 0.02)
                            : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          // Status Dot
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: item.isCounted ? varianceColor : Colors.grey.shade400,
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

                          // Expected Stock
                          SizedBox(
                            width: 80,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Expected', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                Text(
                                  '${item.systemQuantity.toInt()} ${item.unitName}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Counted Stepper Controls
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 14),
                                onPressed: item.countedQuantity > 0 ? () => setState(() => item.decrement(1)) : null,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              ),
                              Container(
                                width: 50,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(color: colors.outlineVariant),
                                  borderRadius: BorderRadius.circular(4),
                                  color: colors.surface,
                                ),
                                child: Text(
                                  item.isCounted ? '${item.countedQuantity.toInt()}' : '—',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: item.isCounted ? colors.primary : colors.onSurfaceVariant,
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
                          const SizedBox(width: 12),

                          // Variance Badge
                          Container(
                            width: 60,
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                            decoration: BoxDecoration(
                              color: varianceColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: varianceColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              !item.isCounted
                                  ? 'Pending'
                                  : variance == 0
                                      ? 'Match'
                                      : '${variance > 0 ? "+" : ""}${variance.toInt()}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: varianceColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Quick Match Button
                          TextButton(
                            onPressed: () => setState(() => item.setCounted(item.systemQuantity)),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            child: const Text('Match', style: TextStyle(fontSize: 11)),
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
}
