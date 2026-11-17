import 'package:flutter_test/flutter_test.dart';
import 'package:erp_core/erp_core.dart';

void main() {
  group('Operations Intelligence Domain Models Tests', () {
    test('InsightRecord serialization and copyWith', () {
      final now = DateTime.now();
      final insight = InsightRecord(
        id: 'ins-101',
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        engine: IntelligenceEngineType.inventory,
        category: 'stockout_risk',
        severity: InsightSeverity.critical,
        priority: InsightPriority.urgent,
        title: 'Low stock on cement',
        description: 'Only 3 bags remain in store.',
        evidence: const InsightEvidence(
          currentValue: 3,
          threshold: 15,
          metricUnit: 'bags',
        ),
        sourceReferences: const [
          InsightSourceReference(entityType: 'product_variant', entityId: 'var-1', entityNumber: 'CEM-50')
        ],
        confidence: 0.95,
        dataFreshness: now,
        status: InsightStatus.newInsight,
        createdAt: now,
        updatedAt: now,
      );

      final map = insight.toMap();
      expect(map['id'], 'ins-101');
      expect(map['engine'], 'inventory');
      expect(map['severity'], 'critical');
      expect(map['priority'], 'urgent');
      expect(map['status'], 'new_insight');

      final fromMap = InsightRecord.fromMap(map);
      expect(fromMap.id, insight.id);
      expect(fromMap.title, insight.title);
      expect(fromMap.evidence.currentValue, 3.0);
      expect(fromMap.sourceReferences.first.entityNumber, 'CEM-50');

      final acknowledged = fromMap.copyWith(status: InsightStatus.acknowledged);
      expect(acknowledged.status, InsightStatus.acknowledged);
    });

    test('ExecutiveHealthSnapshot calculates composite score and metrics', () {
      final now = DateTime.now();
      final snapshot = ExecutiveHealthSnapshot.fromMap({
        'period_days': 30,
        'from_date': now.subtract(const Duration(days: 30)).toIso8601String(),
        'to_date': now.toIso8601String(),
        'gross_sales': 100000.0,
        'sales_returns': 2000.0,
        'net_sales': 98000.0,
        'gross_profit': 25000.0,
        'gross_margin_pct': 25.51,
        'expenses': 12000.0,
        'net_operating_profit': 13000.0,
        'order_count': 120,
        'average_order_value': 816.67,
        'inventory_value': 200000.0,
        'total_monitored_variants': 150,
        'low_stock_count': 5,
        'out_of_stock_count': 1,
        'dead_stock_count': 3,
        'overstock_count': 2,
        'receivables': 20000.0,
        'overdue_receivables': 2000.0,
        'payables': 15000.0,
        'overdue_payables': 1000.0,
        'unresolved_insights_count': 2,
        'critical_insights_count': 0,
        'pending_actions_count': 1,
      });

      expect(snapshot.netSales, 98000.0);
      expect(snapshot.grossMarginPct, 25.51);
      expect(snapshot.compositeHealthScore, greaterThan(80.0));
    });
  });

  group('Operations Intelligence Core & Collectors Tests', () {
    late MockOperationsIntelligenceRepository repo;
    late OperationsIntelligenceContext context;

    setUp(() {
      repo = MockOperationsIntelligenceRepository();
      context = OperationsIntelligenceContext(
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        periodDays: 30,
        now: DateTime.now(),
      );
    });

    test('Orchestrator runs all registered collectors with error isolation', () async {
      final core = OperationsIntelligenceCore(repository: repo);
      core.registerCollectors([
        ExecutiveHealthEngine(),
        SalesIntelligenceEngine(),
        InventoryIntelligenceEngine(),
        FinancialIntelligenceEngine(),
        CustomerIntelligenceEngine(),
        SupplierIntelligenceEngine(),
        ProcurementIntelligenceEngine(),
        OperationalEfficiencyEngine(),
        WorkforceIntelligenceEngine(),
        RiskAnomalyEngine(),
        PredictiveIntelligenceEngine(),
        BusinessSimulationEngine(),
      ]);

      final insights = await core.runCollection(context, persist: false);
      expect(insights, isNotEmpty);
      expect(core.collectors.length, 12);
    });

    test('ExecutiveHealthEngine generates insights on low composite health or high expenses', () async {
      repo.customSnapshot = ExecutiveHealthSnapshot(
        periodDays: 30,
        fromDate: DateTime.now().subtract(const Duration(days: 30)),
        toDate: DateTime.now(),
        grossSales: 50000.0,
        salesReturns: 5000.0,
        netSales: 45000.0,
        grossProfit: 4000.0,
        grossMarginPct: 8.89, // Low margin
        expenses: 25000.0, // High expenses > 35% of revenue
        netOperatingProfit: -21000.0,
        orderCount: 40,
        averageOrderValue: 1125.0,
        inventoryValue: 100000.0,
        totalMonitoredVariants: 100,
        lowStockCount: 20,
        outOfStockCount: 15,
        deadStockCount: 10,
        overstockCount: 5,
        receivables: 40000.0,
        overdueReceivables: 20000.0,
        payables: 30000.0,
        overduePayables: 15000.0,
        unresolvedInsightsCount: 10,
        criticalInsightsCount: 5,
        pendingActionsCount: 4,
        compositeHealthScore: 45.0, // Critical
      );

      final engine = ExecutiveHealthEngine();
      final insights = await engine.collect(context, repo);
      expect(insights.any((i) => i.category == 'health_alert'), isTrue);
      expect(insights.any((i) => i.category == 'operating_expense_ratio'), isTrue);
    });
  });

  group('Risk & Anomaly Engine Tests', () {
    test('isAbnormalDiscount flags discounts above threshold', () {
      expect(RiskAnomalyEngine.isAbnormalDiscount(25.0, thresholdPct: 20.0), isTrue);
      expect(RiskAnomalyEngine.isAbnormalDiscount(15.0, thresholdPct: 20.0), isFalse);
    });

    test('isNegativeMargin detects selling below cost', () {
      expect(RiskAnomalyEngine.isNegativeMargin(85.0, 100.0), isTrue);
      expect(RiskAnomalyEngine.isNegativeMargin(120.0, 100.0), isFalse);
    });

    test('isPotentialDuplicatePayment detects matching payments within 7 days', () {
      final d1 = DateTime(2026, 11, 1);
      final d2 = DateTime(2026, 11, 4);
      final d3 = DateTime(2026, 11, 20);

      expect(RiskAnomalyEngine.isPotentialDuplicatePayment(
        amount1: 5000.0,
        amount2: 5000.0,
        date1: d1,
        date2: d2,
      ), isTrue);

      expect(RiskAnomalyEngine.isPotentialDuplicatePayment(
        amount1: 5000.0,
        amount2: 5000.0,
        date1: d1,
        date2: d3,
      ), isFalse);
    });
  });

  group('Predictive Statistical Forecasting Tests', () {
    test('Simple Moving Average (SMA) calculates correctly', () {
      final values = [10.0, 20.0, 30.0, 40.0, 50.0];
      final sma3 = PredictiveModels.simpleMovingAverage(values, 3);
      expect(sma3, 40.0); // (30 + 40 + 50) / 3
    });

    test('Exponential Moving Average (EMA) responds dynamically to trend', () {
      final values = [10.0, 15.0, 25.0, 35.0, 50.0];
      final ema = PredictiveModels.exponentialMovingAverage(values, alpha: 0.4);
      expect(ema, greaterThan(25.0));
      expect(ema, lessThan(50.0));
    });

    test('Linear Regression trend line and next-step forecast', () {
      final values = [10.0, 20.0, 30.0, 40.0, 50.0];
      final reg = PredictiveModels.linearRegression(values);
      expect(reg[0], closeTo(10.0, 0.001)); // slope = 10
      expect(reg[1], closeTo(10.0, 0.001)); // intercept = 10
      expect(reg[2], closeTo(1.0, 0.001)); // rSquared = 1.0 (perfect fit)

      final next = PredictiveModels.forecastNextLinear(values, 1);
      expect(next, closeTo(60.0, 0.001));
    });

    test('Accuracy metrics: MAE and MAPE calculation', () {
      final actual = [100.0, 110.0, 120.0, 130.0];
      final predicted = [102.0, 108.0, 125.0, 128.0];
      final mae = PredictiveModels.calculateMae(actual, predicted);
      final mape = PredictiveModels.calculateMape(actual, predicted);

      expect(mae, closeTo(2.75, 0.01));
      expect(mape, greaterThan(2.0));
      expect(mape, lessThan(3.0));
    });

    test('projectStockoutDays calculates days remaining', () {
      expect(PredictiveModels.projectStockoutDays(20.0, 4.0), 5.0);
      expect(PredictiveModels.projectStockoutDays(0.0, 4.0), 0.0);
      expect(PredictiveModels.projectStockoutDays(20.0, 0.0), 999.0);
    });
  });

  group('Business Simulation & Decision Engine Tests', () {
    test('simulatePricingChange calculates elasticity and profit impact', () {
      final sim = BusinessSimulationEngine.simulatePricingChange(
        baseSellingPrice: 100.0,
        baseCostPrice: 70.0,
        baseVolume: 1000.0,
        priceChangePercent: 5.0, // +5% price
        priceElasticity: -0.8, // volume drops by -4%
      );

      expect(sim['new_price'], 105.0);
      expect(sim['new_volume'], 960.0);
      expect(sim['new_profit'], greaterThan(sim['base_profit']));
      expect(sim['is_profitable_change'], isTrue);
    });

    test('simulateBulkPurchase evaluates holding cost against discounts', () {
      final viableSim = BusinessSimulationEngine.simulateBulkPurchase(
        standardUnitCost: 100.0,
        bulkUnitCost: 85.0, // 15% discount
        orderQuantity: 500.0,
        annualHoldingCostRate: 0.15,
        estimatedMonthsToSell: 3.0,
      );

      expect(viableSim['discount_savings'], 7500.0);
      expect(viableSim['is_economically_viable'], isTrue);
      expect(viableSim['net_benefit'], greaterThan(0));
    });

    test('simulateCreditPolicy calculates released working capital', () {
      final sim = BusinessSimulationEngine.simulateCreditPolicy(
        currentAnnualCreditSales: 1200000.0,
        currentAverageCollectionDays: 60.0,
        proposedAverageCollectionDays: 45.0,
      );

      expect(sim['working_capital_released'], greaterThan(45000.0));
      expect(sim['annual_capital_savings'], greaterThan(5000.0));
    });
  });

  group('Read-Only AI Business Assistant Tests', () {
    test('Answers questions using only sanitized authorized context', () async {
      final repo = MockOperationsIntelligenceRepository();
      final assistant = ReadOnlyAiBusinessAssistant(repository: repo);

      final healthAnswer = await assistant.ask(
        question: 'What is our current business health?',
        tenantId: 'tenant-1',
      );
      expect(healthAnswer, contains('Composite Health Score'));

      final salesAnswer = await assistant.ask(
        question: 'How are sales performing?',
        tenantId: 'tenant-1',
      );
      expect(salesAnswer, contains('Net sales'));

      final stockAnswer = await assistant.explainMetric(
        metricKey: 'stockouts',
        tenantId: 'tenant-1',
      );
      expect(stockAnswer, contains('Inventory'));
    });
  });

  group('Intelligence Action Centre Tests', () {
    test('Action lifecycle: propose, approve, and resolve', () async {
      final repo = MockOperationsIntelligenceRepository();
      final actionCentre = IntelligenceActionCentre(repo);

      final proposal = await actionCentre.proposeAction(
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        insightId: 'ins-1',
        actionType: ActionType.createPurchaseOrder,
        payload: {'variant_id': 'var-c1', 'quantity': 50},
        previewSummary: 'PO for 50 bags cement',
      );

      expect(proposal.id, isNotEmpty);
      expect(proposal.status, ActionStatus.pendingApproval);

      final decision = await actionCentre.decideAction(
        tenantId: 'tenant-1',
        actionId: proposal.id,
        approve: true,
        note: 'Approved by store manager',
      );
      expect(decision['status'], 'approved');

      final updatedActions = await repo.getActions(tenantId: 'tenant-1');
      final target = updatedActions.firstWhere((a) => a.id == proposal.id);
      expect(target.status, ActionStatus.approved);

      final resolved = await actionCentre.transitionInsight(
        tenantId: 'tenant-1',
        insightId: 'ins-1',
        newStatus: InsightStatus.resolved,
        resolutionNote: 'PO placed with Birla Suppliers',
      );
      expect(resolved, isTrue);
    });
  });
}
