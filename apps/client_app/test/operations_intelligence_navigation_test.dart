import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockNavIntelligenceService extends OperationsIntelligenceService {
  @override
  Future<Map<String, dynamic>> operationsSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async => {
        'tenant_id': tenantId,
        'location_id': locationId,
        'days': days,
        'total_monitored_variants': 25,
        'inventory_value': 500000.0,
      };

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
  Future<List<Map<String, dynamic>>> inventory({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    bool useV830 = false,
  }) async => [];

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
  }) async => {'summary': {}, 'performance': {}, 'trial_balance_health': {}};

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
  }) async => {
        'tenant_id': tenantId,
        'summary': {'overall_efficiency_score': 95.0, 'health_status': 'optimal'},
        'bottlenecks': [],
        'branch_comparisons': [],
      };

  @override
  Future<Map<String, dynamic>> workforceIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async => {'summary': {}, 'risks': []};

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
  }) async => {
        'findings': [],
        'stats': {'total': 0, 'new': 0, 'under_review': 0, 'approved': 0, 'resolved': 0},
      };

  @override
  Future<Map<String, dynamic>> predictiveIntelligence({
    required String tenantId,
    String? locationId,
    int horizonDays = 30,
  }) async => {
        'overall_score': 84,
        'horizon_days': horizonDays,
        'demand_forecast': {'projected_total_revenue': 125000.0, 'daily_projections': []},
        'inventory_depletion_forecast': {'imminent_stockouts_count': 0, 'at_risk_items': []},
        'cash_flow_forecast': {'projected_net_cash': 32400.0},
        'receivables_payables_forecast': {'total_receivables': 65000.0, 'total_payables': 57600.0},
        'customer_churn_risk': {'at_risk_customers': []},
        'supplier_delay_risk': {'delayed_deliveries_projected': 0},
        'workforce_requirement_forecast': {'forecasted_understaffed_days': 0},
        'operational_bottleneck_forecast': {'projected_bottlenecks_count': 0},
      };
}

const _testBusiness = ClientBusiness(
  id: '0af96a25-2f04-44e2-a00f-5c4688f34238',
  membershipId: 'mem-834',
  name: 'Tenzo Traders',
  slug: 'tenzo-traders',
  businessType: 'retail',
  status: 'active',
);

ClientSession _createSession({
  bool isOwner = true,
}) {
  return ClientSession(
    business: _testBusiness,
    userId: 'user-001',
    username: 'Operations Director',
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
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
    permissions: const {
      'operations_intelligence.view',
      'inventory.view_cost',
      'staff.payroll',
      'accounting.view',
    },
    locations: const [],
  );
}

void main() {
  group('Operations Intelligence Desktop Dropdown Navigation Tests', () {
    testWidgets('Renders clean section dropdown navigation in place of scrollable tab row', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockNavIntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify page heading
      expect(find.text('Operations Intelligence'), findsOneWidget);

      // Verify that the dropdown selector is present
      final dropdownFinder = find.byKey(const Key('operations_intelligence_section_dropdown'));
      expect(dropdownFinder, findsOneWidget);

      // Verify active section counter shows "Section 1 of 13"
      expect(find.text('Section 1 of 13'), findsOneWidget);

      // Verify step navigation buttons
      final prevBtn = find.byKey(const Key('operations_intelligence_prev_btn'));
      final nextBtn = find.byKey(const Key('operations_intelligence_next_btn'));
      expect(prevBtn, findsOneWidget);
      expect(nextBtn, findsOneWidget);

      // At section 0 (Overview), previous button should be disabled
      final prevWidget = tester.widget<IconButton>(prevBtn);
      expect(prevWidget.onPressed, isNull);

      // Next button should be enabled
      final nextWidget = tester.widget<IconButton>(nextBtn);
      expect(nextWidget.onPressed, isNotNull);
    });

    testWidgets('Dropdown allows selecting section and navigates immediately', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockNavIntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open dropdown
      final dropdownFinder = find.byKey(const Key('operations_intelligence_section_dropdown'));
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Tap "Sales Intelligence" (item 1)
      await tester.tap(find.byKey(const Key('intelligence_section_item_1')));
      await tester.pumpAndSettle();

      // Counter should now be "Section 2 of 13"
      expect(find.text('Section 2 of 13'), findsOneWidget);

      // Previous button should now be enabled
      final prevWidget = tester.widget<IconButton>(find.byKey(const Key('operations_intelligence_prev_btn')));
      expect(prevWidget.onPressed, isNotNull);
    });

    testWidgets('Step navigation buttons (Next and Previous) advance and retreat sections', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockNavIntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Section 1 of 13'), findsOneWidget);

      // Tap Next button -> Section 2 of 13 (Sales Intelligence)
      await tester.tap(find.byKey(const Key('operations_intelligence_next_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Section 2 of 13'), findsOneWidget);

      // Tap Next button again -> Section 3 of 13 (Stock Intelligence)
      await tester.tap(find.byKey(const Key('operations_intelligence_next_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Section 3 of 13'), findsOneWidget);

      // Tap Previous button -> back to Section 2 of 13
      await tester.tap(find.byKey(const Key('operations_intelligence_prev_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Section 2 of 13'), findsOneWidget);
    });

    testWidgets('Deep navigation with initialTab renders target section and updates dropdown', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockNavIntelligenceService();
      final session = _createSession(isOwner: true);

      // Open directly with initialTab: 11 (Predictive Intelligence & Simulations)
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 11,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify counter reflects Section 12 of 13
      expect(find.text('Section 12 of 13'), findsOneWidget);

      // Verify Predictive Intelligence content is displayed
      expect(find.text('Predictive Intelligence & Business Simulations'), findsOneWidget);
    });

    testWidgets('Responsive desktop at 1366x768 renders cleanly without overflow', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockNavIntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('operations_intelligence_section_dropdown')), findsOneWidget);
      expect(find.text('Section 1 of 13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Responsive mobile at 400x800 adapts dropdown and header without overflow', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockNavIntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('operations_intelligence_section_dropdown')), findsOneWidget);
      expect(find.text('Section 1 of 13'), findsOneWidget);
      expect(find.byKey(const Key('operations_intelligence_prev_btn_compact')), findsOneWidget);
      expect(find.byKey(const Key('operations_intelligence_next_btn_compact')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
