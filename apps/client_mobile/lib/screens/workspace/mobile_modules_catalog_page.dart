import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:thq_logistics/thq_logistics.dart';
import 'package:thq_ui/thq_ui.dart';

import '../../models/mobile_session.dart';
import '../../services/mobile_client_service.dart';
import 'mobile_accounting_page.dart';
import 'mobile_material_yard_page.dart';
import 'mobile_party_payments_page.dart';
import 'mobile_purchase_create_page.dart';
import 'mobile_reports_center_page.dart';
import 'mobile_staff_attendance_page.dart';
import 'mobile_stock_transfers_page.dart';
import 'mobile_tools_pages.dart';

class MobileModulesCatalogPage extends StatefulWidget {
  final MobileSession session;
  final MobileClientService service;
  final String? locationId;
  final void Function(int tabIndex)? onSwitchTab;

  const MobileModulesCatalogPage({
    super.key,
    required this.session,
    required this.service,
    this.locationId,
    this.onSwitchTab,
  });

  @override
  State<MobileModulesCatalogPage> createState() =>
      _MobileModulesCatalogPageState();
}

class _MobileModulesCatalogPageState extends State<MobileModulesCatalogPage> {
  final _searchCtrl = TextEditingController();
  String _selectedCategory = 'All';
  late Future<List<dynamic>> _dataFuture;

  List<ThqNavigationNode> _allNodes = [];
  ThqUserUiPreferences _preferences = ThqUserUiPreferences.defaults('client_mobile');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _load() {
    _dataFuture = Future.wait([
      widget.service.loadNavigation(widget.session.tenantId, 'client_mobile'),
      widget.service.loadUserPreferences('client_mobile'),
    ]);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _dataFuture;
  }

  void _toggleFavorite(String nodeKey) async {
    final next = _preferences.toggleFavorite(nodeKey);
    setState(() => _preferences = next);
    try {
      await widget.service.saveUserPreferences(next);
    } catch (_) {}
  }

  void _openCustomization() async {
    final controller = ThqWorkspaceCustomizationController(
      appScope: 'client_mobile',
      allNodes: _allNodes,
      initialPreferences: _preferences,
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThqWorkspaceCustomizationView(
          controller: controller,
          onSave: (updated) async {
            await widget.service.saveUserPreferences(updated);
            if (mounted) setState(() => _preferences = updated);
          },
        ),
      ),
    );
    _refresh();
  }

  void _routeToModule(String nodeKey) {
    switch (nodeKey) {
      case 'dashboard':
      case 'overview':
        widget.onSwitchTab?.call(0);
        break;
      case 'sales':
      case 'sales_pos':
        widget.onSwitchTab?.call(1);
        break;
      case 'inventory':
      case 'stock':
        widget.onSwitchTab?.call(2);
        break;
      case 'purchases':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobilePurchasesPage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'purchase_create':
      case 'purchases_create':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobilePurchaseCreatePage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'stock_transfers':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileStockTransfersPage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'material_yard':
      case 'quarry':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileMaterialYardPage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'staff':
      case 'attendance':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileStaffAttendancePage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'accounting':
      case 'accounts':
      case 'ledger':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileAccountingPage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'inventory_reports':
      case 'reports':
      case 'reports_center':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileReportsCenterPage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'payments':
      case 'customer_payments':
      case 'party_payments':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobilePartyPaymentsPage(
              session: widget.session,
              service: widget.service,
            ),
          ),
        );
        break;
      case 'traceability':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileTraceabilityPage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'approvals':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileApprovalsPage(
              session: widget.session,
              service: widget.service,
            ),
          ),
        );
        break;
      case 'audit':
      case 'audit_center':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileAuditPage(
              session: widget.session,
              service: widget.service,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'store_performance':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileStorePerformancePage(
              session: widget.session,
              service: widget.service,
            ),
          ),
        );
        break;
      case 'vehicle_logistics':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VehicleLogisticsReportWorkspace(
              tenantId: widget.session.tenantId,
              locationId: widget.locationId,
            ),
          ),
        );
        break;
      case 'customization':
        _openCustomization();
        break;
      default:
        ThqNotify.info(
          context,
          'Module',
          message: 'Opening ${nodeKey.replaceAll('_', ' ')} workspace.',
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasData) {
          _allNodes = (snapshot.data![0] as List<ThqNavigationNode>);
          _preferences = (snapshot.data![1] as ThqUserUiPreferences);
        }

        // Fallback default modules if offline or empty
        final displayNodes = _allNodes.isNotEmpty
            ? _allNodes.where((n) => !_preferences.hiddenNodes.contains(n.nodeKey)).toList()
            : _fallbackDefaultNodes();

        final query = _searchCtrl.text.trim().toLowerCase();
        final filteredNodes = displayNodes.where((node) {
          if (_selectedCategory != 'All' && node.category != _selectedCategory) {
            return false;
          }
          if (query.isEmpty) return true;
          return node.label.toLowerCase().contains(query) ||
              node.nodeKey.toLowerCase().contains(query);
        }).toList();

        // Pinned favorites
        final favoriteNodes = displayNodes
            .where((n) => _preferences.favorites.contains(n.nodeKey))
            .toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            children: [
              // Search & Customize Header
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search all modules & tools...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Customize Workspace',
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: _openCustomization,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Favorites Section
              if (favoriteNodes.isNotEmpty && query.isEmpty && _selectedCategory == 'All') ...[
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 18, color: Colors.amber.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Pinned Quick Launch',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: favoriteNodes.map((n) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Icon(ThqModuleIcons.resolve(n.moduleKey ?? n.nodeKey, n.iconKey), size: 16),
                          label: Text(n.label),
                          onPressed: () => _routeToModule(n.nodeKey),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Category Selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    'All',
                    'Operations',
                    'Logistics & Quarry',
                    'Accounting & Finance',
                    'Workforce & HR',
                    'Reports & Settings',
                  ].map((cat) {
                    final sel = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(cat),
                        selected: sel,
                        onSelected: (_) => setState(() => _selectedCategory = cat),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Modules Grid / List
              if (filteredNodes.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.widgets_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 8),
                        const Text('No modules matched your search'),
                      ],
                    ),
                  ),
                )
              else
                ...filteredNodes.map((node) {
                  final isFav = _preferences.favorites.contains(node.nodeKey);
                  final icon = ThqModuleIcons.resolve(node.moduleKey ?? node.nodeKey, node.iconKey);

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                      title: Text(
                        node.label,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: Text(
                        node.category.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: isFav ? Colors.amber.shade700 : null,
                              size: 20,
                            ),
                            tooltip: isFav ? 'Unpin favorite' : 'Pin favorite',
                            onPressed: () => _toggleFavorite(node.nodeKey),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        ],
                      ),
                      onTap: () => _routeToModule(node.nodeKey),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  List<ThqNavigationNode> _fallbackDefaultNodes() {
    return [
      const ThqNavigationNode(
        id: 'sales',
        nodeKey: 'sales',
        nodeType: 'module',
        label: 'Sales & POS',
        metadata: {'category': 'Operations'},
        sortOrder: 10,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'inventory',
        nodeKey: 'inventory',
        nodeType: 'module',
        label: 'Stock & Inventory',
        metadata: {'category': 'Operations'},
        sortOrder: 20,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'purchases',
        nodeKey: 'purchases',
        nodeType: 'module',
        label: 'Purchases Register',
        metadata: {'category': 'Operations'},
        sortOrder: 30,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'purchase_create',
        nodeKey: 'purchase_create',
        nodeType: 'module',
        label: 'New Purchase Bill',
        metadata: {'category': 'Operations'},
        sortOrder: 35,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'stock_transfers',
        nodeKey: 'stock_transfers',
        nodeType: 'module',
        label: 'Stock Transfers',
        metadata: {'category': 'Operations'},
        sortOrder: 40,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'material_yard',
        nodeKey: 'material_yard',
        nodeType: 'module',
        label: 'Material Yard & Quarry',
        metadata: {'category': 'Logistics & Quarry'},
        sortOrder: 50,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'vehicle_logistics',
        nodeKey: 'vehicle_logistics',
        nodeType: 'module',
        label: 'Vehicle Stock Logistics',
        metadata: {'category': 'Logistics & Quarry'},
        sortOrder: 55,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'staff',
        nodeKey: 'staff',
        nodeType: 'module',
        label: 'Staff & Attendance',
        metadata: {'category': 'Workforce & HR'},
        sortOrder: 60,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'accounting',
        nodeKey: 'accounting',
        nodeType: 'module',
        label: 'Financial & Accounting',
        metadata: {'category': 'Accounting & Finance'},
        sortOrder: 70,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'customer_payments',
        nodeKey: 'customer_payments',
        nodeType: 'module',
        label: 'Party Receipts & Payments',
        metadata: {'category': 'Accounting & Finance'},
        sortOrder: 75,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'reports',
        nodeKey: 'reports',
        nodeType: 'module',
        label: 'Reports Center',
        metadata: {'category': 'Reports & Settings'},
        sortOrder: 80,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'traceability',
        nodeKey: 'traceability',
        nodeType: 'module',
        label: 'Traceability & Story',
        metadata: {'category': 'Reports & Settings'},
        sortOrder: 85,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'approvals',
        nodeKey: 'approvals',
        nodeType: 'module',
        label: 'Approvals Manager',
        metadata: {'category': 'Reports & Settings'},
        sortOrder: 90,
        enabled: true,
      ),
      const ThqNavigationNode(
        id: 'audit',
        nodeKey: 'audit',
        nodeType: 'module',
        label: 'Audit Center',
        metadata: {'category': 'Reports & Settings'},
        sortOrder: 95,
        enabled: true,
      ),
    ];
  }
}
