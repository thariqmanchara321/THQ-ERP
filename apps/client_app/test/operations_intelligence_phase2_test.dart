import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/client_navigation_scope.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockOperationsIntelligenceService extends OperationsIntelligenceService {
  final bool failPayables;

  _MockOperationsIntelligenceService({
    this.failPayables = false,
  });

  @override
  Future<Map<String, dynamic>> operationsSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    if (days > 30) {
      // 2x period for comparison
      return {
        'flow_metrics': {
          'gross_sales': 270000.0,
          'net_sales': 255000.0,
          'sales_returns': 15000.0,
          'order_count': 220,
          'aov': 1159.0,
          'cogs': 170000.0,
          'gross_profit': 85000.0,
          'gross_margin_pct': 33.33,
          'operating_expenses': 24000.0,
          'net_profit': 61000.0,
        },
      };
    }

    return {
      'flow_metrics': {
        'gross_sales': 150000.0,
        'net_sales': 142500.0,
        'sales_returns': 7500.0,
        'order_count': 120,
        'aov': 1187.5,
        'cogs': 95000.0,
        'gross_profit': 47500.0,
        'gross_margin_pct': 33.33,
        'operating_expenses': 12500.0,
        'net_profit': 35000.0,
      },
      'inventory_metrics': {
        'total_valuation': 450000.0,
        'monitored_variants': 85,
        'low_stock_count': 12,
        'out_of_stock_count': 3,
        'dead_stock_count': 5,
        'overstock_count': 8,
      },
      'financial_metrics': {
        'customer_receivables': 68000.0,
        'receivables_overdue': 15000.0,
        'supplier_payables': 89000.0,
        'payables_overdue': 22000.0,
      },
      'top_products': [
        {
          'product_name': 'UltraTech Cement 50kg',
          'variant_name': 'PPC Bag',
          'units_sold': 340,
          'revenue': 51000.0,
          'profit': 10200.0,
        },
      ],
      'attention_counts': {
        'pending_reorder_approvals': 2,
        'draft_grns': 1,
        'unpaid_overdue_invoices': 4,
        'in_transit_transfers': 3,
        'expiring_batches': 5,
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> inventory({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    bool useV830 = false,
  }) async {
    return [
      {
        'product_name': 'UltraTech Cement 50kg',
        'variant_name': 'PPC Bag',
        'sku': 'SKU-CEM-PPC',
        'stock_quantity': 15.0,
        'reorder_point': 50.0,
        'stock_status': 'low_stock',
        'abc_class': 'A',
        'current_cost': 310.0,
        'selling_price': 380.0,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> customerCredit({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async {
    return [
      {
        'customer_name': 'BuildCon Infra',
        'total_outstanding': 35000.0,
        'overdue_amount': 15000.0,
        'credit_limit': 50000.0,
        'credit_status': 'active',
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> supplierPayables({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async {
    if (failPayables) {
      throw StateError('Payables network timeout simulation');
    }
    return [
      {
        'supplier_name': 'UltraTech Cement Dist.',
        'total_payable': 65000.0,
        'overdue_amount': 22000.0,
        'pending_bills_count': 3,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> reorder({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    return [
      {
        'variant_id': 'var-cement-ppc',
        'product_name': 'UltraTech Cement 50kg',
        'sku': 'SKU-CEM-PPC',
        'stock_quantity': 15.0,
        'suggested_reorder_quantity': 85.0,
        'preferred_supplier_id': 'sup-1',
        'preferred_supplier_name': 'UltraTech Dist.',
        'estimated_cost': 310.0,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> purchaseOrders({
    required String tenantId,
    String? locationId,
    String? status,
    String query = '',
  }) async {
    return [
      {
        'order_id': 'po-101',
        'order_number': 'PO-2026-001',
        'supplier_name': 'UltraTech Dist.',
        'status': 'draft',
        'total_amount': 26350.0,
        'items_count': 1,
        'created_at': DateTime.now().toIso8601String(),
      },
    ];
  }
}

void main() {
  const tenantId = 'tenant-test-1';

  const testBusiness = ClientBusiness(
    id: tenantId,
    membershipId: 'mem-1',
    name: 'THQ Mega Infra Ltd',
    slug: 'thq-mega-infra',
    businessType: 'retail',
    status: 'active',
  );

  final testLocations = [
    const ClientLocationAccess(
      id: 'loc-1',
      code: 'MAIN',
      name: 'Main Central Yard',
      type: 'store',
      trackingCode: 'TRK-01',
      accessLevel: 'manage',
    ),
    const ClientLocationAccess(
      id: 'loc-2',
      code: 'NORTH',
      name: 'North Retail Store',
      type: 'store',
      trackingCode: 'TRK-02',
      accessLevel: 'manage',
    ),
  ];

  ClientSession createSession({
    bool isOwner = true,
    bool canViewCost = true,
    bool multiLocation = true,
  }) {
    return ClientSession(
      business: testBusiness,
      userId: 'user-1',
      username: 'Test User',
      modules: const [
        ClientModule(
          key: 'operations_intelligence',
          name: 'Operations Intelligence',
          description: null,
          category: 'analytics',
          sortOrder: 1,
        ),
      ],
      roles: isOwner ? {'owner'} : {'staff'},
      permissions: {
        'inventory.view',
        if (canViewCost) 'inventory.view_cost',
      },
      currencyCode: 'INR',
      timezone: 'Asia/Kolkata',
      locale: 'en_IN',
      locations: multiLocation ? testLocations : [testLocations.first],
    );
  }

  group('ComparisonMetric unit tests', () {
    test('Calculates positive percentage change accurately', () {
      final metric = ComparisonMetric.calculate(150.0, 100.0);

      expect(metric.current, 150.0);
      expect(metric.previous, 100.0);
      expect(metric.difference, 50.0);
      expect(metric.percentChange, closeTo(50.0, 0.01));
      expect(metric.isPositive, isTrue);
      expect(metric.isNeutral, isFalse);
    });

    test('Calculates negative percentage change accurately', () {
      final metric = ComparisonMetric.calculate(75.0, 100.0);

      expect(metric.current, 75.0);
      expect(metric.previous, 100.0);
      expect(metric.difference, -25.0);
      expect(metric.percentChange, closeTo(-25.0, 0.01));
      expect(metric.isPositive, isFalse);
      expect(metric.isNeutral, isFalse);
    });

    test('Handles zero previous cleanly with 100% change', () {
      final metric = ComparisonMetric.calculate(120.0, 0.0);

      expect(metric.difference, 120.0);
      expect(metric.percentChange, 100.0);
      expect(metric.isPositive, isTrue);
    });

    test('Handles both zero values as neutral', () {
      final metric = ComparisonMetric.calculate(0.0, 0.0);

      expect(metric.difference, 0.0);
      expect(metric.percentChange, 0.0);
      expect(metric.isNeutral, isTrue);
    });
  });

  group('SectionState unit tests', () {
    test('Transitions from idle to loading, success, and error', () {
      const initial = SectionState<int>(data: 0);
      expect(initial.loading, isFalse);
      expect(initial.hasError, isFalse);
      expect(initial.data, 0);

      final loading = initial.toLoading();
      expect(loading.loading, isTrue);
      expect(loading.hasError, isFalse);

      final success = loading.toSuccess(42);
      expect(success.loading, isFalse);
      expect(success.hasError, isFalse);
      expect(success.data, 42);
      expect(success.lastLoaded, isNotNull);

      final error = success.toError('Network connection timed out');
      expect(error.loading, isFalse);
      expect(error.hasError, isTrue);
      expect(error.error, 'Network connection timed out');
      expect(error.data, 42); // Preserves cached data
    });
  });

  group('ClientNavigationScope unit tests', () {
    testWidgets('Provides in-shell module switching without throwing', (tester) async {
      String? requestedModule;
      int? requestedTab;
      dynamic requestedArgs;

      await tester.pumpWidget(
        MaterialApp(
          home: ClientNavigationScope(
            navigateTo: (module, {int? tabIndex, dynamic args}) {
              requestedModule = module;
              requestedTab = tabIndex;
              requestedArgs = args;
            },
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ClientNavigationScope.navigate(
                      context,
                      'smart_inventory',
                      tabIndex: 2,
                      args: {'auto_scan': true},
                    );
                  },
                  child: const Text('Go To Smart Inventory'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go To Smart Inventory'));
      await tester.pump();

      expect(requestedModule, 'smart_inventory');
      expect(requestedTab, 2);
      expect(requestedArgs is Map && requestedArgs['auto_scan'] == true, isTrue);
    });

    testWidgets('Returns false safely when outside ClientNavigationScope', (tester) async {
      bool? navigated;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  navigated = ClientNavigationScope.navigate(
                    context,
                    'inventory',
                  );
                },
                child: const Text('Outside Scope'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Outside Scope'));
      await tester.pump();

      expect(navigated, isFalse);
    });
  });

  group('OperationsIntelligenceScreen widget tests', () {
    testWidgets('Renders Executive Business Overview with Sales and Profitability', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = _MockOperationsIntelligenceService();
      final session = createSession(isOwner: true, canViewCost: true, multiLocation: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: mockService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header title
      expect(find.text('Operations Intelligence'), findsOneWidget);

      // Period selector chips
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('7 Days'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);
      expect(find.text('90 Days'), findsOneWidget);

      // Key metrics
      expect(find.text('Gross Sales'), findsOneWidget);
      expect(find.text('Net Sales'), findsWidgets);
      expect(find.text('Gross Profit'), findsWidgets);
      expect(find.text('Operating Expenses'), findsOneWidget);

      // Inventory valuation and stock
      expect(find.text('Total Stock Value'), findsOneWidget);
      expect(find.text('Monitored Variants'), findsOneWidget);

      // Top Products table
      expect(find.text('Top Selling Products'), findsOneWidget);
      expect(find.text('UltraTech Cement 50kg'), findsWidgets);

      // Multi-store comparison table (multiLocation is true)
      expect(find.text('Store Comparison'), findsOneWidget);
      expect(find.textContaining('Main Central Yard'), findsOneWidget);
      expect(find.textContaining('North Retail Store'), findsOneWidget);
    });

    testWidgets('Masks cost & profit when cost permission is denied', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = _MockOperationsIntelligenceService();
      final session = createSession(isOwner: false, canViewCost: false, multiLocation: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: mockService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Shows Cost Restricted badge
      expect(find.text('Cost Restricted'), findsWidgets);
      // Masked profit values
      expect(find.text('Access restricted'), findsWidgets);

      // Single location user should not see multi-store comparison table
      expect(find.text('Store & Yard Performance Comparison'), findsNothing);
    });

    testWidgets('Isolates section failures and displays section-specific retry', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = _MockOperationsIntelligenceService(failPayables: true);
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: mockService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Overview still loads and displays Gross Sales successfully
      expect(find.text('Gross Sales'), findsOneWidget);

      // Switch to Supplier Payables tab (index 3)
      await tester.tap(find.widgetWithText(Tab, 'Supplier Payables'));
      await tester.pumpAndSettle();

      // Payables should display error and retry button
      expect(find.textContaining('Payables network timeout simulation'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
