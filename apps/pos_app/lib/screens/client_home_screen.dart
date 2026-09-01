import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../services/client_auth_service.dart';
import 'client_login_screen.dart';
import 'inventory_products_screen.dart';
import 'tracking_workspace_screen.dart';
import 'suppliers_screen.dart';
import 'purchasing_v2_screen.dart';
import 'purchases_screen.dart';
import 'loan_screen.dart';
import 'stock_transfers_screen.dart';
import 'customers_screen.dart';
import 'sales_screen.dart';
import 'dashboard_screen.dart';
import 'expenses_screen.dart';
import 'accounting_screen.dart';
import 'reports_screen.dart';
import 'business_settings_screen.dart';
import 'industry_workspace_screen.dart';
import 'payment_center_screen.dart';
import 'bulk_import_screen.dart';
import 'error_logs_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  final ClientSession session;

  const ClientHomeScreen({super.key, required this.session});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final ClientAuthService _authService = ClientAuthService();

  int _selectedIndex = 0;

  List<ClientModule> get _modules => widget.session.modules;

  Future<void> _logout() async {
    await _authService.signOut();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ClientLoginScreen()),
      (_) => false,
    );
  }

  IconData _moduleIcon(String key) {
    switch (key) {
      case 'dashboard':
        return Icons.dashboard_outlined;

      case 'inventory':
        return Icons.inventory_2_outlined;

      case 'sales':
        return Icons.point_of_sale_outlined;
      case 'sales_details':
        return Icons.receipt_long_outlined;

      case 'purchases':
        return Icons.shopping_cart_outlined;
      case 'purchase_details':
        return Icons.list_alt_outlined;
      case 'loans':
        return Icons.account_balance_wallet_outlined;

      case 'stock_transfers':
        return Icons.swap_horiz_outlined;

      case 'customers':
        return Icons.people_outline;

      case 'suppliers':
        return Icons.local_shipping_outlined;

      case 'expenses':
        return Icons.receipt_long_outlined;

      case 'accounting':
        return Icons.account_balance_outlined;

      case 'reports':
        return Icons.bar_chart_outlined;

      case 'barcode':
        return Icons.qr_code_scanner_outlined;

      case 'warranty':
        return Icons.verified_user_outlined;

      case 'vehicle_compatibility':
        return Icons.directions_car_outlined;

      case 'payments':
        return Icons.payments_outlined;
      case 'bulk_import':
        return Icons.upload_file_outlined;
      case 'logs':
        return Icons.bug_report_outlined;
      case 'invoice_templates':
        return Icons.receipt_long_outlined;
      case 'settings':
        return Icons.settings_outlined;

      case 'restaurant':
      case 'restaurant_orders':
        return Icons.restaurant_outlined;

      case 'workshop':
        return Icons.build_outlined;

      case 'healthcare':
        return Icons.local_hospital_outlined;

      case 'lab':
        return Icons.biotech_outlined;

      case 'pharmacy':
        return Icons.medication_outlined;

      default:
        return Icons.extension_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_modules.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No modules are enabled for this business.')),
      );
    }

    if (_selectedIndex >= _modules.length) {
      _selectedIndex = 0;
    }

    final selectedModule = _modules[_selectedIndex];

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;

        if (desktop) {
          return _buildDesktop(selectedModule);
        }

        return _buildMobile(selectedModule);
      },
    );
  }

  Widget _buildDesktop(ClientModule selectedModule) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      body: Row(
        children: [
          Container(
            width: 250,
            color: Colors.white,
            child: Column(
              children: [
                _BusinessHeader(session: widget.session),

                const Divider(height: 1),

                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _modules.length,
                    itemBuilder: (context, index) {
                      final module = _modules[index];

                      final selected = index == _selectedIndex;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          selected: selected,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          leading: Icon(_moduleIcon(module.key)),
                          title: Text(module.name),
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),

                const Divider(height: 1),

                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign Out'),
                  onTap: _logout,
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),

          const VerticalDivider(width: 1),

          Expanded(
            child: Column(
              children: [
                _SubscriptionBanner(session: widget.session),
                Expanded(
                  child: _ModulePage(
                    module: selectedModule,
                    session: widget.session,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(ClientModule selectedModule) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      appBar: AppBar(title: Text(widget.session.business.name)),

      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              _BusinessHeader(session: widget.session),

              const Divider(height: 1),

              Expanded(
                child: ListView.builder(
                  itemCount: _modules.length,
                  itemBuilder: (context, index) {
                    final module = _modules[index];

                    return ListTile(
                      selected: _selectedIndex == index,
                      leading: Icon(_moduleIcon(module.key)),
                      title: Text(module.name),
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                        });

                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign Out'),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),

      body: Column(
        children: [
          _SubscriptionBanner(session: widget.session),
          Expanded(
            child: _ModulePage(module: selectedModule, session: widget.session),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionBanner extends StatelessWidget {
  final ClientSession session;
  const _SubscriptionBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final status = session.subscription.status;
    if (!session.subscription.hasPlan ||
        status == 'active' ||
        status == 'trial') {
      return const SizedBox.shrink();
    }
    final blocked = session.subscription.blocksAccess;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      color: blocked ? Colors.red.shade50 : Colors.orange.shade50,
      child: Row(
        children: [
          Icon(
            blocked ? Icons.block_outlined : Icons.warning_amber_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Subscription ${status.replaceAll('_', ' ')}${blocked ? ' — contact your administrator to restore module access.' : '.'}',
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessHeader extends StatelessWidget {
  final ClientSession session;

  const _BusinessHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.indigo.shade50,
            ),
            child: const Icon(Icons.storefront_outlined),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.business.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 3),

                Text(
                  session.roles.isEmpty
                      ? 'User'
                      : session.roles.map(_niceName).join(', '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),

                if (session.subscription.hasPlan) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${session.subscription.planName ?? session.subscription.planKey} • ${session.subscription.status}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _niceName(String text) {
    if (text.isEmpty) {
      return text;
    }

    return text[0].toUpperCase() + text.substring(1);
  }
}

class _ModulePage extends StatelessWidget {
  final ClientModule module;
  final ClientSession session;

  const _ModulePage({required this.module, required this.session});

  @override
  Widget build(BuildContext context) {
    if (module.key == 'dashboard') {
      return DashboardScreen(session: session);
    }
    if (module.key == 'inventory') {
      return InventoryProductsScreen(session: session);
    }
    if (module.key == 'warranty') {
      return TrackingWorkspaceScreen(session: session);
    }
    if (module.key == 'suppliers') {
      return SuppliersScreen(session: session);
    }
    if (module.key == 'purchases') {
      return PurchasesScreen(session: session);
    }
    if (module.key == 'purchase_details') {
      return PurchasingV2Screen(session: session);
    }
    if (module.key == 'loans') {
      return LoanScreen(session: session);
    }
    if (module.key == 'stock_transfers') {
      return StockTransfersScreen(session: session);
    }
    if (module.key == 'customers') {
      return CustomersScreen(session: session);
    }
    if (module.key == 'sales' || module.key == 'sales_details') {
      return SalesScreen(session: session);
    }
    if (module.key == 'expenses') {
      return ExpensesScreen(session: session);
    }
    if (module.key == 'accounting') {
      return AccountingScreen(session: session);
    }
    if (module.key == 'reports') {
      return ReportsScreen(session: session);
    }
    if (module.key == 'payments') {
      return PaymentCenterScreen(session: session);
    }
    if (module.key == 'bulk_import') {
      return BulkImportScreen(session: session);
    }
    if (module.key == 'logs') {
      return ErrorLogsScreen(session: session);
    }
    if (module.key == 'settings') {
      return BusinessSettingsScreen(session: session);
    }
    if (const {
      'restaurant',
      'restaurant_orders',
      'workshop',
      'healthcare',
      'lab',
      'pharmacy',
    }.contains(module.key)) {
      return IndustryWorkspaceScreen(session: session, module: module);
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            module.name,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(
            module.description ?? 'THQ Business module',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
          ),

          const SizedBox(height: 30),

          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.construction_outlined, size: 58),

                  const SizedBox(height: 18),

                  Text(
                    '${module.name} is enabled',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'We will build this module next.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'Currency: ${session.currencyCode}   •   Locale: ${session.locale}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
