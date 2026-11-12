import 'dart:async';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/client_session.dart';
import '../../services/location_scope_service.dart';
import 'tabs/smart_barcode_studio_tab.dart';
import 'tabs/smart_inventory_bulk_scan_tab.dart';
import 'tabs/smart_inventory_import_tab.dart';
import 'tabs/smart_inventory_overview_tab.dart';
import 'tabs/smart_inventory_product_lookup_tab.dart';
import 'tabs/smart_inventory_scan_center_tab.dart';
import 'tabs/smart_inventory_scan_history_tab.dart';
import 'tabs/smart_purchase_receiving_tab.dart';
import 'tabs/smart_stock_count_tab.dart';

/// The central Smart Inventory workspace within THQ Client application.
class SmartInventoryWorkspaceScreen extends StatefulWidget {
  final ClientSession session;
  final int initialTab;
  final WirelessScannerTransport? wirelessTransport;
  final WirelessScannerCoordinator? wirelessCoordinator;

  const SmartInventoryWorkspaceScreen({
    super.key,
    required this.session,
    this.initialTab = 0,
    this.wirelessTransport,
    this.wirelessCoordinator,
  });

  @override
  State<SmartInventoryWorkspaceScreen> createState() =>
      _SmartInventoryWorkspaceScreenState();
}

class _SmartInventoryWorkspaceScreenState
    extends State<SmartInventoryWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activeTabIndex = 0;
  late final WirelessScannerCoordinator _wirelessScannerCoordinator;
  StreamSubscription<WirelessScanMessage>? _wirelessScanSub;
  StreamSubscription<WirelessScannerState>? _wirelessStateSub;

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTab.clamp(0, 8);
    _tabController = TabController(
      length: 9,
      vsync: this,
      initialIndex: _activeTabIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _activeTabIndex = _tabController.index);
      }
    });

    if (widget.wirelessCoordinator != null) {
      _wirelessScannerCoordinator = widget.wirelessCoordinator!;
    } else {
      _wirelessScannerCoordinator = WirelessScannerCoordinator(
        transport: widget.wirelessTransport ?? SupabaseRealtimeScannerTransport(),
      );
    }

    _wirelessScanSub =
        _wirelessScannerCoordinator.scans.listen(_handleIncomingWirelessScan);
    _wirelessStateSub =
        _wirelessScannerCoordinator.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _handleIncomingWirelessScan(WirelessScanMessage scan) {
    // Acknowledge receipt
    _wirelessScannerCoordinator.acknowledgeScan(
      messageId: scan.messageId,
      success: true,
      productName: 'Barcode ${scan.rawCode} received',
    );
  }

  void _openWirelessScannerDialog() {
    final location = LocationScopeService.selectedLocation(widget.session);
    ThqWirelessScannerDialog.show(
      context: context,
      coordinator: _wirelessScannerCoordinator,
      tenantId: widget.session.business.id,
      locationId: location?.id,
      hostDeviceName: 'Client-Desktop (${widget.session.username})',
    );
  }

  @override
  void dispose() {
    _wirelessScanSub?.cancel();
    _wirelessStateSub?.cancel();
    if (widget.wirelessCoordinator == null) {
      _wirelessScannerCoordinator.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  void _onSelectTab(int index) {
    if (index >= 0 && index < 9) {
      _tabController.animateTo(index);
      setState(() => _activeTabIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final location = LocationScopeService.selectedLocation(widget.session);

    return Scaffold(
      body: Column(
        children: [
          // Workspace Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.qr_code_scanner, color: colors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Smart Inventory',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Multi-identifier hardware scanning and product resolution',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: _wirelessScannerCoordinator.isConnected
                      ? 'Wireless Scanner (Connected: ${_wirelessScannerCoordinator.activeDevice?.deviceName ?? "Phone"})'
                      : 'Pair Wireless Phone Scanner',
                  child: OutlinedButton.icon(
                    onPressed: _openWirelessScannerDialog,
                    icon: Icon(
                      Icons.phone_android_rounded,
                      size: 16,
                      color: _wirelessScannerCoordinator.isConnected
                          ? Colors.green
                          : null,
                    ),
                    label: Text(
                      _wirelessScannerCoordinator.isConnected
                          ? 'Phone Scanner'
                          : 'Pair Scanner',
                      style: TextStyle(
                        color: _wirelessScannerCoordinator.isConnected
                            ? Colors.green
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ThqStatusBadge(
                  status: ThqStatus.neutral,
                  label: location?.name ?? 'All Locations',
                ),
              ],
            ),
          ),

          // Workspace Segmented Navigation Bar
          Container(
            color: colors.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: colors.primary,
              unselectedLabelColor: colors.onSurfaceVariant,
              indicatorColor: colors.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(
                  icon: Icon(Icons.dashboard_outlined, size: 18),
                  text: 'Overview',
                ),
                Tab(
                  icon: Icon(Icons.center_focus_strong, size: 18),
                  text: 'Scan Center',
                ),
                Tab(
                  icon: Icon(Icons.search, size: 18),
                  text: 'Product Lookup',
                ),
                Tab(
                  icon: Icon(Icons.playlist_add_check, size: 18),
                  text: 'Bulk Scanning',
                ),
                Tab(
                  icon: Icon(Icons.history, size: 18),
                  text: 'Scan History',
                ),
                Tab(
                  icon: Icon(Icons.upload_file_outlined, size: 18),
                  text: 'Product Import',
                ),
                Tab(
                  icon: Icon(Icons.print_outlined, size: 18),
                  text: 'Barcode Studio',
                ),
                Tab(
                  icon: Icon(Icons.inventory_2_outlined, size: 18),
                  text: 'Stock Count',
                ),
                Tab(
                  icon: Icon(Icons.call_received, size: 18),
                  text: 'Purchase Receiving',
                ),
              ],
            ),
          ),

          // Tab Views Body
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SmartInventoryOverviewTab(
                  session: widget.session,
                  onSelectTab: _onSelectTab,
                ),
                SmartInventoryScanCenterTab(session: widget.session),
                SmartInventoryProductLookupTab(session: widget.session),
                SmartInventoryBulkScanTab(session: widget.session),
                SmartInventoryScanHistoryTab(session: widget.session),
                SmartInventoryImportTab(session: widget.session),
                SmartBarcodeStudioTab(session: widget.session),
                SmartInventoryStockCountTab(session: widget.session),
                SmartPurchaseReceivingTab(session: widget.session),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

