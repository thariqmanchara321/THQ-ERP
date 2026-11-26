import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thq_ui/thq_ui.dart';

class MockOperationsIntelligenceService extends OperationsIntelligenceService {
  int lastRequestedDays = 0;

  @override
  Future<Map<String, dynamic>> operationsSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    lastRequestedDays = days;
    return {
      'from_date': '2026-11-01',
      'to_date': '2026-11-24',
      'gross_sales': 100000.0,
      'net_sales': 95000.0,
      'sales_returns': 5000.0,
      'order_count': 50,
      'average_order_value': 1900.0,
      'gross_profit': 30000.0,
      'expenses': 15000.0,
      'net_operating_profit': 15000.0,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> inventory({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    bool useV830 = true,
  }) async {
    return [
      {
        'location_name': 'Main Branch',
        'product_name': 'Steel Rebar 12mm',
        'sku': 'STL-12MM',
        'available': 150.0,
        'incoming_po_qty': 50.0,
        'in_transit_qty': 20.0,
        'reorder_level': 100.0,
        'max_stock': 500.0,
        'avg_daily_sales': 12.5,
        'days_cover': 12.0,
        'suggested_reorder': 80.0,
        'stock_value': 450000.0,
        'abc_class': 'A',
        'movement_class': 'FAST',
        'status': 'HEALTHY',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> salesIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async => {
        'performance': {'current': {'net_sales': 100000.0}},
        'trends': {'daily': []},
        'products': {'best_selling': []},
        'categories': [],
        'customer_intelligence': {'summary': {}, 'segments': [], 'top_customers': []},
        'anomalies': [],
      };

  @override
  Future<List<Map<String, dynamic>>> rebalancing({
    required String tenantId,
    String? locationId,
    int days = 30,
    int limit = 100,
  }) async => [];

  @override
  Future<Map<String, dynamic>> purchaseIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async => {'summary': {}, 'trends': {}, 'by_supplier': []};

  @override
  Future<Map<String, dynamic>> supplierIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 200,
  }) async => {'summary': {}, 'suppliers': []};

  @override
  Future<Map<String, dynamic>> procurementIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 500,
  }) async => {'summary': {}, 'recommendations': []};

  @override
  Future<List<Map<String, dynamic>>> customerCredit({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 5000,
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> supplierPayables({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 5000,
  }) async => [];

  @override
  Future<Map<String, dynamic>> financialIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async => {'summary': {}, 'pnl': {}};

  @override
  Future<Map<String, dynamic>> expenseIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async => {'summary': {}, 'by_category': []};

  @override
  Future<Map<String, dynamic>> operationalEfficiency({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async => {'diagnostics': []};

  @override
  Future<Map<String, dynamic>> workforceIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async => {'staff': []};

  @override
  Future<List<Map<String, dynamic>>> reorder({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> purchaseOrders({
    required String tenantId,
    String? locationId,
    String? status,
    String query = '',
  }) async => [];

  Future<Map<String, dynamic>> actionCentreSummary({
    required String tenantId,
    String? locationId,
  }) async => {'total': 0, 'critical': 0, 'by_category': {}};

  @override
  Future<Map<String, dynamic>> actionCentre({
    required String tenantId,
    String? locationId,
    String? engine,
    String? severity,
    String? status,
    String? category,
    String query = '',
    int limit = 100,
    int offset = 0,
  }) async => {'findings': [], 'stats': {}};

  @override
  Future<Map<String, dynamic>> predictiveIntelligence({
    required String tenantId,
    String? locationId,
    int horizonDays = 30,
  }) async => {'overall_score': 84};

  @override
  Future<List<Map<String, dynamic>>> listBusinessSimulations({
    required String tenantId,
    String? locationId,
    String? category,
    int limit = 50,
  }) async => [];
}

const _testBusiness = ClientBusiness(
  id: '0af96a25-2f04-44e2-a00f-5c4688f34238',
  membershipId: 'mem-834',
  name: 'Tenzo Traders',
  slug: 'tenzo-traders',
  businessType: 'retail',
  status: 'active',
);

ClientSession _createSession() {
  return const ClientSession(
    business: _testBusiness,
    userId: 'user-001',
    username: 'Operations Director',
    modules: [
      ClientModule(
        key: 'operations_intelligence',
        name: 'Operations Intelligence',
        description: null,
        category: 'analytics',
        sortOrder: 1,
      ),
    ],
    roles: {'owner'},
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
    permissions: {
      'operations_intelligence.view',
      'inventory.view_cost',
      'staff.payroll',
      'accounting.view',
    },
    locations: [],
  );
}

void main() {
  testWidgets('Calendar date selector updates query days and header', (tester) async {
    final mockService = MockOperationsIntelligenceService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 900,
            child: OperationsIntelligenceScreen(
              session: _createSession(),
              service: mockService,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify ThqDateRangeSelector is rendered with presets
    expect(find.byType(ThqDateRangeSelector), findsOneWidget);
    expect(find.text('7 Days'), findsOneWidget);
    expect(find.text('30 Days'), findsOneWidget);
    expect(find.text('90 Days'), findsOneWidget);

    // Tap '7 Days' preset
    await tester.tap(find.text('7 Days'));
    await tester.pumpAndSettle();

    // The comparison period requests days * 2 = 14
    expect(mockService.lastRequestedDays, equals(14));
  });

  testWidgets('Responsive stock table renders without horizontal overflow and opens detail dialog', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockOperationsIntelligenceService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 900,
            child: OperationsIntelligenceScreen(
              session: _createSession(),
              service: mockService,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to Stock Intelligence via section dropdown
    final dropdownFinder = find.byKey(const Key('operations_intelligence_section_dropdown'));
    expect(dropdownFinder, findsOneWidget);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    // Tap "Stock Intelligence" (item 2)
    final stockItemFinder = find.byKey(const Key('intelligence_section_item_2'));
    expect(stockItemFinder, findsOneWidget);
    await tester.tap(stockItemFinder);
    await tester.pumpAndSettle();

    // Verify responsive table is used instead of horizontal scrollview
    expect(find.byType(ThqResponsiveTable), findsOneWidget);
    expect(find.text('Steel Rebar 12mm'), findsOneWidget);

    // Click on detail button to open comprehensive 14-metric dialog
    final detailBtn = find.byTooltip('View Full Stock Details');
    expect(detailBtn, findsOneWidget);
    await tester.tap(detailBtn);
    await tester.pumpAndSettle();

    // Verify all key metrics are visible in the detail dialog
    expect(find.text('Days of Stock Cover'), findsOneWidget);
    expect(find.text('12.0 days'), findsOneWidget);
    expect(find.text('Burn Rate (Avg Sales/Day)'), findsOneWidget);
    expect(find.text('12.50 /d'), findsOneWidget);
    expect(find.text('Reorder Level'), findsOneWidget);
    expect(find.text('Maximum Stock'), findsOneWidget);
  });

  testWidgets('Header vertical height is compact (<=84px) on desktop viewports', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockOperationsIntelligenceService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: _createSession(),
            service: mockService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerFinder = find.byKey(const Key('operations_intelligence_unified_header'));
    expect(headerFinder, findsOneWidget);

    final headerSize = tester.getSize(headerFinder);
    expect(headerSize.height, lessThanOrEqualTo(84.0));
  });

  testWidgets('Metric cards render at compact width and maintain visible values', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockService = MockOperationsIntelligenceService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: _createSession(),
            service: mockService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check overview metric values
    expect(find.text('Gross Sales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Multi-viewport responsive audit (1920, 1366, 1024, 768, 390) renders with zero overflow', (tester) async {
    final viewports = [
      const Size(1920, 1080),
      const Size(1366, 768),
      const Size(1024, 768),
      const Size(768, 1024),
      const Size(390, 844),
    ];

    final mockService = MockOperationsIntelligenceService();

    for (final size in viewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: _createSession(),
              service: mockService,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Operations Intelligence'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    tester.view.resetPhysicalSize();
  });
}
