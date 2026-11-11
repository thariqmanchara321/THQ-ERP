import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_smart_inventory_service.dart';
import '../../widgets/mobile_smart_inventory_dialogs.dart';

/// The authoritative Mobile Smart Inventory workspace for THQ Client Mobile.
///
/// Provides a compact, mobile-first interface for:
/// - Overview & live activity streaming
/// - High-performance camera & wedge barcode scanning
/// - Multi-identifier product catalog lookup
/// - Non-mutating bulk scan staging and session verification
/// - Historical scan review
class MobileSmartInventoryWorkspaceScreen extends StatefulWidget {
  final MobileSession session;
  final MobileSmartInventoryService service;
  final String? locationId;

  const MobileSmartInventoryWorkspaceScreen({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
  });

  @override
  State<MobileSmartInventoryWorkspaceScreen> createState() =>
      _MobileSmartInventoryWorkspaceScreenState();
}

class _MobileSmartInventoryWorkspaceScreenState
    extends State<MobileSmartInventoryWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final SmartScannerController _scannerController;
  StreamSubscription<ScanActivityLogEntry>? _activitySubscription;

  // Active scan state
  ProductIdentificationResult? _lastScanResult;
  bool _isProcessingScan = false;
  bool _isContinuousMode = true;

  // Lookup state
  final TextEditingController _lookupSearchController = TextEditingController();
  List<ProductIdentificationMatch> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounceTimer;

  // Session metadata
  late String _activeLocationId;
  late String _activeLocationName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    _activeLocationId = widget.locationId ?? widget.session.locationId;
    _activeLocationName = widget.session.locations
        .firstWhere(
          (loc) => loc.id == _activeLocationId,
          orElse: () => MobileLocation(
            id: _activeLocationId,
            code: widget.session.locationCode,
            name: widget.session.locationName,
            accessLevel: 'full',
          ),
        )
        .name;

    _scannerController = SmartScannerController(
      configuration: ScannerConfiguration(
        mode: _isContinuousMode ? ScannerMode.continuous : ScannerMode.single,
        duplicateSuppressionDuration: const Duration(milliseconds: 1400),
        allowDuplicates: false,
      ),
    );

    _activitySubscription = widget.service.activityStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();
    _searchDebounceTimer?.cancel();
    _lookupSearchController.dispose();
    _scannerController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // --- External Wedge Scanner Handler ---
  void _handleWedgeScan(String barcode, ScannerSource source) {
    if (!mounted) return;
    _onBarcodeReceived(barcode, source);
  }

  // --- Core Scan Ingestion ---
  Future<void> _onScanDetected(SmartScanResult scan) async {
    await _onBarcodeReceived(scan.normalizedValue, scan.source);
  }

  Future<void> _onBarcodeReceived(String code, ScannerSource source) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty || _isProcessingScan) return;

    setState(() {
      _isProcessingScan = true;
    });

    try {
      final result = await widget.service.identifyCode(
        cleanCode,
        session: widget.session,
        locationId: _activeLocationId,
        source: source,
      );

      if (!mounted) return;

      setState(() {
        _lastScanResult = result;
      });

      // Handle multi-match disambiguation
      if (result.isAmbiguous && result.matches.isNotEmpty) {
        final chosenMatch = await showDialog<ProductIdentificationMatch>(
          context: context,
          builder: (ctx) => MobileSmartInventoryMultipleMatchDialog(
            rawCode: cleanCode,
            matches: result.matches,
            currencyCode: widget.session.currency,
          ),
        );

        if (chosenMatch != null && mounted) {
          _handleResolvedMatch(chosenMatch);
        }
      } else if (result.isExact && result.primaryMatch != null) {
        _handleResolvedMatch(result.primaryMatch!);
      } else if (result.isNotFound) {
        final bulk = widget.service.activeBulkSession;
        if (bulk != null) {
          bulk.addUnresolved(cleanCode, source, 'Product not found');
          setState(() {});
        }
        ThqNotify.warning(
          context,
          'Product not found for: $cleanCode',
        );
      } else if (result.status == ProductIdentificationStatus.offlineMiss ||
          (result.hasError &&
              (result.errorMessage?.toLowerCase().contains('connection') == true ||
                  result.errorMessage?.toLowerCase().contains('network') == true ||
                  result.errorMessage?.toLowerCase().contains('offline') == true))) {
        ThqNotify.error(
          context,
          'Online connection required. Offline lookup is unavailable on mobile.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingScan = false;
        });
      }
    }
  }

  void _handleResolvedMatch(ProductIdentificationMatch match) {
    final bulk = widget.service.activeBulkSession;
    if (bulk != null) {
      bulk.addOrIncrementMatch(match);
      ThqNotify.success(
        context,
        'Added ${match.productName} (Qty: ${bulk.items.firstWhere((it) => (it.variantId.isNotEmpty ? it.variantId : it.productId) == (match.variantId.isNotEmpty ? match.variantId : match.productId)).quantity})',
      );
    } else {
      ThqNotify.success(
        context,
        'Identified: ${match.productName} (${match.sku})',
      );
    }
  }

  void _toggleContinuousMode(bool value) {
    setState(() {
      _isContinuousMode = value;
      _scannerController.setMode(
        value ? ScannerMode.continuous : ScannerMode.single,
      );
    });
  }

  Future<void> _openManualEntry() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const MobileManualCodeEntryDialog(),
    );
    if (code != null && code.isNotEmpty && mounted) {
      await _onBarcodeReceived(code, ScannerSource.manual);
    }
  }

  void _onLookupSearchChanged(String text) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      _performLookup(text);
    });
  }

  Future<void> _performLookup(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    final results = await widget.service.searchCatalog(
      q,
      session: widget.session,
      locationId: _activeLocationId,
    );

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _openProductDetail(ProductIdentificationMatch match) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MobileProductDetailModal(
        match: match,
        session: widget.session,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ThqBarcodeWedgeListener(
      onScan: _handleWedgeScan,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Smart Inventory',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Icon(Icons.storefront_outlined,
                      size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    _activeLocationName,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Enter code manually',
              icon: const Icon(Icons.keyboard_outlined),
              onPressed: _openManualEntry,
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              const Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined, size: 20)),
              Tab(
                text: 'Scan',
                icon: Badge(
                  isLabelVisible: _isProcessingScan,
                  smallSize: 8,
                  child: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                ),
              ),
              const Tab(text: 'Lookup', icon: Icon(Icons.search_rounded, size: 20)),
              Tab(
                text: 'Bulk',
                icon: Badge(
                  isLabelVisible: widget.service.activeBulkSession != null,
                  label: Text('${widget.service.activeBulkSession?.totalDistinctProducts ?? 0}'),
                  child: const Icon(Icons.inventory_2_outlined, size: 20),
                ),
              ),
              const Tab(text: 'History', icon: Icon(Icons.history_rounded, size: 20)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(),
            _buildScanTab(),
            _buildLookupTab(),
            _buildBulkTab(),
            _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // TAB 1: OVERVIEW
  // ==========================================================================
  Widget _buildOverviewTab() {
    final scheme = Theme.of(context).colorScheme;
    final activity = widget.service.recentActivity;
    final bulk = widget.service.activeBulkSession;

    final totalScans = activity.length;
    final successfulMatches = activity.where((a) => a.isSuccess).length;
    final unresolvedCount = activity.where((a) => !a.isSuccess).length;

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
        children: [
          // Active Location Scope Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.location_on_outlined,
                      color: scheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Active Store Location',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      Text(
                        _activeLocationName,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (widget.session.locations.length > 1)
                  TextButton.icon(
                    onPressed: _switchLocationScope,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: const Text('Change', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Live Metrics Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Scans',
                  value: '$totalScans',
                  icon: Icons.qr_code_2_rounded,
                  color: const Color(0xFF0052CC),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Identified',
                  value: '$successfulMatches',
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF00875A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Unresolved',
                  value: '$unresolvedCount',
                  icon: Icons.help_outline_rounded,
                  color: unresolvedCount > 0
                      ? const Color(0xFFDE350B)
                      : Colors.grey,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Quick Action Launchers
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera Scan',
                  color: const Color(0xFF0052CC),
                  onTap: () => _tabController.animateTo(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.search_rounded,
                  label: 'Search SKU',
                  color: const Color(0xFF635BFF),
                  onTap: () => _tabController.animateTo(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.playlist_add_check_rounded,
                  label: bulk == null ? 'Start Bulk Session' : 'Active Bulk (${bulk.totalDistinctProducts})',
                  color: const Color(0xFF0D9488),
                  onTap: () => _tabController.animateTo(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.keyboard_outlined,
                  label: 'Manual Code',
                  color: const Color(0xFF4A5568),
                  onTap: _openManualEntry,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Recent Activity Stream Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Activity',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              if (activity.isNotEmpty)
                TextButton(
                  onPressed: () {
                    widget.service.clearActivity();
                    setState(() {});
                  },
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),

          if (activity.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.history_rounded, size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('No scans recorded yet.'),
                      SizedBox(height: 4),
                      Text(
                        'Use the camera scanner or enter barcodes above.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            ...activity.take(20).map((item) => _buildActivityTile(item)),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTile(ScanActivityLogEntry item) {
    final scheme = Theme.of(context).colorScheme;
    final isSuccess = item.isSuccess;
    final badgeColor = isSuccess ? const Color(0xFF00875A) : const Color(0xFFDE350B);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: badgeColor.withValues(alpha: 0.12),
          child: Icon(
            isSuccess ? Icons.check_rounded : Icons.close_rounded,
            color: badgeColor,
            size: 16,
          ),
        ),
        title: Text(
          item.productName ?? item.rawCode,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.rawCode}${item.sku != null ? " • SKU: ${item.sku}" : ""} • ${item.source.name}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Text(
          '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}',
          style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  void _switchLocationScope() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select Operating Store Scope',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView(
                  children: widget.session.locations.map((loc) {
                    final isSelected = loc.id == _activeLocationId;
                    return ListTile(
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: isSelected ? Theme.of(ctx).colorScheme.primary : null,
                      ),
                      title: Text(loc.name),
                      subtitle: Text(loc.code),
                      onTap: () {
                        setState(() {
                          _activeLocationId = loc.id;
                          _activeLocationName = loc.name;
                        });
                        Navigator.of(ctx).pop();
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================================
  // TAB 2: SCAN (CAMERA + VIEW CARD)
  // ==========================================================================
  Widget _buildScanTab() {
    final scheme = Theme.of(context).colorScheme;
    final lastScan = _lastScanResult;

    return Column(
      children: [
        // Top Scan Mode bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Continuous scan',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Switch.adaptive(
                    value: _isContinuousMode,
                    onChanged: _toggleContinuousMode,
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                onPressed: _openManualEntry,
                icon: const Icon(Icons.keyboard_outlined, size: 16),
                label: const Text('Manual', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        // Camera Viewfinder Box
        Expanded(
          flex: 5,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ThqSmartScannerView(
              controller: _scannerController,
              onScan: _onScanDetected,
              showControls: true,
              enableHaptic: true,
              instructionText: _isContinuousMode
                  ? 'Continuous scan active. Align code in box.'
                  : 'Single scan mode. Align code in box.',
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Feedback / Match Display Card
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: _buildScanFeedbackCard(lastScan, scheme),
          ),
        ),
      ],
    );
  }

  Widget _buildScanFeedbackCard(
      ProductIdentificationResult? result, ColorScheme scheme) {
    if (result == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner_rounded, size: 36, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Waiting for barcode scan...',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SizedBox(height: 2),
              Text(
                'Camera viewfinder or external Bluetooth scanner supported.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (result.isNotFound) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 36, color: scheme.error),
              const SizedBox(height: 6),
              Text(
                'Not Found: "${result.request.rawIdentifier}"',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: scheme.error),
              ),
              const SizedBox(height: 4),
              const Text(
                'No product or variant in THQ ERP matches this identifier.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: _openManualEntry,
                child: const Text('Try Another Code', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    final isOffline = result.status == ProductIdentificationStatus.offlineMiss ||
        (result.hasError &&
            (result.errorMessage?.toLowerCase().contains('connection') == true ||
                result.errorMessage?.toLowerCase().contains('network') == true ||
                result.errorMessage?.toLowerCase().contains('offline') == true));

    if (isOffline) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.amber),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 36, color: Colors.amber),
              const SizedBox(height: 6),
              const Text(
                'Offline Lookup Unavailable',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                result.errorMessage ??
                    'Client Mobile requires a live internet connection to resolve products.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final match = result.primaryMatch;
    if (match == null) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF00875A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF00875A), size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Identified Product',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00875A),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _openProductDetail(match),
                  child: const Text('Full Details', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const Divider(height: 8),
            Text(
              match.productName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (match.variantName.isNotEmpty &&
                match.variantName != match.productName)
              Text(
                match.variantName,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SKU: ${match.sku}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (match.barcode != null && match.barcode!.isNotEmpty)
                      Text('Barcode: ${match.barcode}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${widget.session.currency} ${match.sellingPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Stock: ${match.stockQuantity} ${match.unitCode}',
                      style: TextStyle(
                        fontSize: 11,
                        color: match.stockQuantity > 0
                            ? const Color(0xFF00875A)
                            : scheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // TAB 3: PRODUCT LOOKUP
  // ==========================================================================
  Widget _buildLookupTab() {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: TextField(
            controller: _lookupSearchController,
            decoration: InputDecoration(
              hintText: 'Search product name, SKU, barcode, brand...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _lookupSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _lookupSearchController.clear();
                        _performLookup('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: _onLookupSearchChanged,
          ),
        ),
        if (_isSearching)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),

        Expanded(
          child: _searchResults.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 44, color: scheme.outline),
                        const SizedBox(height: 10),
                        Text(
                          _lookupSearchController.text.trim().isEmpty
                              ? 'Enter a keyword, SKU or barcode to search'
                              : 'No products found for "${_lookupSearchController.text.trim()}"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    return Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: ListTile(
                        onTap: () => _openProductDetail(item),
                        title: Text(
                          item.productName,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${item.sku.isNotEmpty ? "SKU: ${item.sku} • " : ""}${item.barcode != null ? "BC: ${item.barcode} • " : ""}Stock: ${item.stockQuantity} ${item.unitCode}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.session.currency} ${item.sellingPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            if (widget.service.activeBulkSession != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline_rounded,
                                    color: Color(0xFF00875A)),
                                tooltip: 'Add to Bulk Session',
                                onPressed: () => _handleResolvedMatch(item),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 4: BULK SCANNING
  // ==========================================================================
  Widget _buildBulkTab() {
    final scheme = Theme.of(context).colorScheme;
    final session = widget.service.activeBulkSession;

    if (session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.playlist_add_check_rounded,
                  size: 48, color: scheme.primary),
              const SizedBox(height: 12),
              const Text(
                'No Active Bulk Session',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Create a temporary staging session to scan multiple products rapidly, consolidate quantities, and audit lines.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  widget.service.startBulkSession(
                    session: widget.session,
                    locationId: _activeLocationId,
                    locationName: _activeLocationName,
                  );
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Start Bulk Session'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
      children: [
        // Non-mutating Notice Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0052CC).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF0052CC).withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF0052CC)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Staging only. Bulk scanning verifies codes without altering live stock.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF0052CC)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Session Header Summary Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      session.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Operator: ${session.operatorName}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatPill('Products', '${session.totalDistinctProducts}'),
                    const SizedBox(width: 6),
                    _buildStatPill('Total Qty', session.totalQuantity.toStringAsFixed(1)),
                    const SizedBox(width: 6),
                    _buildStatPill('Scans', '${session.totalScans}'),
                    const SizedBox(width: 6),
                    _buildStatPill('Unresolved', '${session.totalUnresolved}',
                        isWarning: session.totalUnresolved > 0),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          _toggleContinuousMode(true);
                          _tabController.animateTo(1);
                        },
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                        label: const Text('Scan Items', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00875A),
                        ),
                        onPressed: _finishBulkSession,
                        icon: const Icon(Icons.done_all_rounded, size: 16),
                        label: const Text('Finish', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Color(0xFFDE350B)),
                      tooltip: 'Discard Session',
                      onPressed: _discardBulkSession,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Distinct items list
        Text(
          'Staged Products (${session.items.length})',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),

        if (session.items.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text('No items staged yet. Start scanning to add items.'),
              ),
            ),
          )
        else
          ...session.items.map((item) {
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          if (item.variantName.isNotEmpty &&
                              item.variantName != item.productName)
                            Text(
                              item.variantName,
                              style: TextStyle(
                                  fontSize: 11, color: scheme.primary),
                            ),
                          Text(
                            'SKU: ${item.sku} • ${item.unitCode}',
                            style: const TextStyle(
                                fontSize: 10.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded,
                              size: 20),
                          onPressed: () {
                            setState(() => item.decrement(1.0));
                          },
                        ),
                        Text(
                          item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              size: 20),
                          onPressed: () {
                            setState(() => item.increment(1.0));
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: Colors.grey),
                          onPressed: () {
                            setState(() => session.removeItem(item.variantId));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

        if (session.unresolvedScans.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Unresolved Scans (${session.unresolvedScans.length})',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFDE350B)),
          ),
          const SizedBox(height: 6),
          ...session.unresolvedScans.map((unres) {
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                    color: const Color(0xFFDE350B).withValues(alpha: 0.5)),
              ),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFDE350B)),
                title: Text(unres.rawCode,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(unres.note ?? 'Product not found'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: 'Retry identification',
                      onPressed: () async {
                        session.removeUnresolved(unres.id);
                        await _onBarcodeReceived(unres.rawCode, unres.source);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () {
                        setState(() => session.removeUnresolved(unres.id));
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildStatPill(String label, String value, {bool isWarning = false}) {
    final color = isWarning ? const Color(0xFFDE350B) : const Color(0xFF0052CC);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  void _finishBulkSession() {
    final completed = widget.service.finishBulkSession();
    if (completed != null && mounted) {
      setState(() {});
      ThqNotify.success(
        context,
        'Bulk session "${completed.title}" finished (${completed.totalDistinctProducts} products).',
      );
      _tabController.animateTo(4); // Switch to History
    }
  }

  void _discardBulkSession() {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Bulk Session?'),
        content: const Text(
          'Are you sure you want to discard this in-memory session? All staged items will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDE350B),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        widget.service.cancelBulkSession();
        setState(() {});
      }
    });
  }

  // ==========================================================================
  // TAB 5: SCAN HISTORY
  // ==========================================================================
  Widget _buildHistoryTab() {
    final scheme = Theme.of(context).colorScheme;
    final sessions = widget.service.completedSessions;

    if (sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_toggle_off_rounded,
                  size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              const Text(
                'No Completed Sessions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Completed bulk sessions from this app run will appear here for review.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
      itemCount: sessions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final s = sessions[index];
        final completedStr = s.completedAt != null
            ? '${s.completedAt!.hour.toString().padLeft(2, '0')}:${s.completedAt!.minute.toString().padLeft(2, '0')}'
            : '';

        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF00875A).withValues(alpha: 0.12),
              child: const Icon(Icons.check_rounded,
                  color: Color(0xFF00875A), size: 18),
            ),
            title: Text(
              s.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            subtitle: Text(
              '${s.totalDistinctProducts} products • ${s.totalQuantity.toStringAsFixed(1)} units • $completedStr',
              style: const TextStyle(fontSize: 11),
            ),
            children: [
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Details',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary),
                    ),
                    const SizedBox(height: 4),
                    Text('Location: ${s.locationName ?? "Default"}',
                        style: const TextStyle(fontSize: 11.5)),
                    Text('Operator: ${s.operatorName}',
                        style: const TextStyle(fontSize: 11.5)),
                    const SizedBox(height: 8),
                    ...s.items.map((it) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '• ${it.productName}',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${it.quantity.toStringAsFixed(it.quantity % 1 == 0 ? 0 : 2)} ${it.unitCode}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
