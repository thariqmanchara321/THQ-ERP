import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:erp_core/erp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testTenantId = 'tenant-test-101';

  const testBusiness = ClientBusiness(
    id: testTenantId,
    membershipId: 'mem-101',
    name: 'THQ Test Enterprise',
    slug: 'thq-test',
    businessType: 'retail',
    status: 'active',
  );

  const testSession = ClientSession(
    business: testBusiness,
    userId: 'user-cfo',
    username: 'Executive User',
    modules: [
      ClientModule(
        key: 'operations_intelligence',
        name: 'Operations Intelligence',
        description: null,
        category: 'Analytics',
        sortOrder: 1,
      ),
    ],
    roles: {'owner', 'cfo'},
    permissions: {'intelligence.view', 'intelligence.manage'},
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
  );

  group('OperationsIntelligenceService Unit Tests', () {
    late MockOperationsIntelligenceRepository mockRepo;
    late OperationsIntelligenceService service;

    setUp(() {
      mockRepo = MockOperationsIntelligenceRepository();
      service = OperationsIntelligenceService(mockRepo);
    });

    test('getExecutiveSummary returns calculated snapshot with score', () async {
      final summary = await service.getExecutiveSummary(
        tenantId: testTenantId,
        days: 30,
      );

      expect(summary.periodDays, 30);
      expect(summary.netSales, greaterThan(0));
      expect(summary.grossMarginPct, greaterThan(0));
      expect(summary.compositeHealthScore, greaterThan(0));
      expect(summary.topProducts, isNotEmpty);
    });

    test('inventoryV830 returns variants with ABC Pareto tags and days cover', () async {
      final rows = await service.inventoryV830(
        tenantId: testTenantId,
        days: 30,
      );

      expect(rows, isNotEmpty);
      expect(rows.any((r) => r['abc_class'] == 'A'), isTrue);
      expect(rows.first.containsKey('available_stock'), isTrue);
      expect(rows.first.containsKey('reorder_level'), isTrue);
    });

    test('getInsights and updateInsightStatus transition lifecycle correctly', () async {
      final insights = await service.getInsights(tenantId: testTenantId);
      expect(insights, isNotEmpty);

      final first = insights.first;
      expect(first.status, InsightStatus.newInsight);

      final success = await service.updateInsightStatus(
        tenantId: testTenantId,
        insightId: first.id,
        status: InsightStatus.acknowledged,
      );
      expect(success, isTrue);

      final updated = await service.getInsights(
        tenantId: testTenantId,
        status: InsightStatus.acknowledged,
      );
      expect(updated.any((i) => i.id == first.id), isTrue);
    });

    test('getActions and decideAction handles approval and rejection', () async {
      final actions = await service.getActions(tenantId: testTenantId);
      expect(actions, isNotEmpty);

      final first = actions.first;
      final result = await service.decideAction(
        tenantId: testTenantId,
        actionId: first.id,
        approve: true,
        note: 'Approved for procurement',
      );

      expect(result['status'], 'approved');
      expect(result['action_id'], first.id);
    });

    test('simulatePricingChange computes elasticity delta deterministically without ledger writes', () {
      final sim = service.simulatePricingChange(
        baseSellingPrice: 100.0,
        baseCostPrice: 60.0,
        baseVolume: 1000.0,
        priceChangePercent: 5.0,
        priceElasticity: -0.8,
      );

      expect(sim['new_price'], 105.0);
      expect(sim['volume_change_pct'], -4.0); // -0.8 * 5% = -4%
      expect(sim['new_volume'], 960.0); // 1000 * 0.96 = 960
      expect(sim['new_revenue'], 105.0 * 960.0); // 100,800
      expect(sim['is_profitable_change'], isTrue);
    });

    test('simulateBulkPurchase evaluates discount vs holding cost trade-off', () {
      final sim = service.simulateBulkPurchase(
        standardUnitCost: 100.0,
        bulkUnitCost: 90.0,
        orderQuantity: 1000.0,
        annualHoldingCostRate: 0.20,
        estimatedMonthsToSell: 3.0,
      );

      expect(sim['discount_savings'], 10000.0); // 10 * 1000
      expect(sim['carrying_cost'], (90.0 * 1000.0 / 2.0) * 0.20 * (3.0 / 12.0)); // 2,250
      expect(sim['net_benefit'], 7750.0); // 10000 - 2250
      expect(sim['is_economically_viable'], isTrue);
    });

    test('simulateCreditPolicy calculates freed working capital', () {
      final sim = service.simulateCreditPolicy(
        currentAnnualCreditSales: 3650000.0,
        currentAverageCollectionDays: 60.0,
        proposedAverageCollectionDays: 45.0,
        costOfCapitalRate: 0.12,
      );

      expect(sim['working_capital_released'], 150000.0);
      expect(sim['annual_capital_savings'], 18000.0);
    });

    test('askAiAssistant provides grounded natural language response', () async {
      final answer = await service.askAiAssistant(
        question: 'What is our current business health score?',
        tenantId: testTenantId,
      );

      expect(answer, contains('Health Score'));
      expect(answer, isNotEmpty);
    });
  });

  group('OperationsIntelligenceScreen Widget Tests', () {
    late MockOperationsIntelligenceRepository mockRepo;
    late OperationsIntelligenceService service;

    setUp(() {
      mockRepo = MockOperationsIntelligenceRepository();
      service = OperationsIntelligenceService(mockRepo);
    });

    testWidgets('renders all 10 intelligence tabs and header controls', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: testSession,
              service: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header checks
      expect(find.text('Operations Intelligence'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.text('Ask AI Assistant'), findsOneWidget);

      // Verify all 10 tab headers
      expect(find.text('Executive Health'), findsOneWidget);
      expect(find.text('Sales Intelligence'), findsOneWidget);
      expect(find.text('Inventory & ABC'), findsOneWidget);
      expect(find.text('Financial & CCC'), findsOneWidget);
      expect(find.text('Customer Credit'), findsOneWidget);
      expect(find.text('Supplier Payables'), findsOneWidget);
      expect(find.text('Procurement & Ops'), findsOneWidget);
      expect(find.text('Risk & Anomalies'), findsOneWidget);
      expect(find.text('Forecast & Simulation'), findsOneWidget);
      expect(find.text('Action Centre'), findsOneWidget);

      // Check Executive Health content
      expect(find.text('Business Health Index'), findsOneWidget);
      expect(find.text('Net Working Capital'), findsOneWidget);
      expect(find.text('Cash Conversion Cycle'), findsOneWidget);

      // Navigate to Sales Intelligence tab
      final salesTab = find.text('Sales Intelligence');
      await tester.ensureVisible(salesTab);
      await tester.tap(salesTab);
      await tester.pumpAndSettle();
      expect(find.text('Sales Velocity'), findsOneWidget);

      // Navigate to Forecast & Simulation tab
      final forecastTab = find.text('Forecast & Simulation');
      await tester.ensureVisible(forecastTab);
      await tester.tap(forecastTab);
      await tester.pumpAndSettle();
      expect(find.text('Pricing Elasticity Simulator'), findsOneWidget);
      expect(find.text('Bulk Purchase Trade-off Simulator'), findsOneWidget);
      expect(find.text('Credit Terms & DSO Simulator'), findsOneWidget);

      // Navigate to Action Centre tab
      final actionTab = find.text('Action Centre');
      await tester.ensureVisible(actionTab);
      await tester.tap(actionTab);
      await tester.pumpAndSettle();
      expect(find.text('Intelligence Action Centre'), findsOneWidget);
    });
  });
}
