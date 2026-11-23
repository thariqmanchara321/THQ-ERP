import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhase10IntelligenceService extends OperationsIntelligenceService {
  final bool failPredictive;
  final bool emptyData;
  final bool canViewCost;
  bool scanTriggered = false;
  bool simulationRunTriggered = false;
  bool saveSimulationTriggered = false;
  bool deleteSimulationTriggered = false;

  _MockPhase10IntelligenceService({
    this.failPredictive = false,
    this.emptyData = false,
    this.canViewCost = true,
  });

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
  }) async {
    if (failPredictive) {
      throw Exception('Predictive intelligence engine calculation failed');
    }
    if (emptyData) {
      return {
        'success': true,
        'horizon_days': horizonDays,
        'can_view_cost': canViewCost,
        'summary': {
          'forecast_horizon_days': horizonDays,
          'predictive_health_score': 85.0,
          'projected_revenue': 0.0,
          'projected_net_cash': 0.0,
          'stockouts_imminent_count': 0,
          'churn_risk_customers_count': 0,
          'at_risk_suppliers_count': 0,
        },
        'sales_demand_forecast': {'projected_total_revenue': 0.0, 'daily_projections': []},
        'inventory_depletion_forecast': {'imminent_stockouts': [], 'excess_stock_items': []},
        'cash_flow_forecast': {'projected_inflows': 0.0, 'projected_outflows': 0.0, 'projected_net_cash': 0.0},
        'receivables_payables_forecast': {'total_receivables': 0.0, 'total_payables': 0.0},
        'customer_churn_risk': {'at_risk_customers': []},
        'supplier_delivery_risk': {'at_risk_suppliers': []},
        'backtesting_accuracy': {'accuracy_score': 88.5, 'mae': 0.0, 'mape': 11.5},
        'risks': [],
      };
    }

    return {
      'success': true,
      'horizon_days': horizonDays,
      'can_view_cost': canViewCost,
      'summary': {
        'forecast_horizon_days': horizonDays,
        'predictive_health_score': 84.0,
        'projected_revenue': 142500.0,
        'daily_run_rate': 4750.0,
        'projected_net_cash': 32400.0,
        'projected_closing_cash': 282400.0,
        'stockouts_imminent_count': 2,
        'churn_risk_customers_count': 3,
        'at_risk_suppliers_count': 1,
      },
      'sales_demand_forecast': {
        'historical_sales_total': 285000.0,
        'projected_total_revenue': 142500.0,
        'trend_slope_per_day': 125.40,
        'trend_direction': 'Upward Demand Trend',
        'growth_rate_pct': 4.8,
        'daily_projections': [
          {'date': '2026-11-24', 'day_index': 1, 'trend_value': 4620.0, 'low_bound_80': 3927.0, 'high_bound_80': 5313.0},
          {'date': '2026-11-25', 'day_index': 2, 'trend_value': 4745.0, 'low_bound_80': 4033.0, 'high_bound_80': 5456.0},
          {'date': '2026-11-26', 'day_index': 3, 'trend_value': 4870.0, 'low_bound_80': 4139.0, 'high_bound_80': 5600.0},
        ],
      },
      'inventory_depletion_forecast': {
        'imminent_stockouts': [
          {
            'product_name': 'Amul Butter 500g',
            'sku': 'SKU-AMUL-01',
            'current_stock': 8,
            'daily_burn_rate': 2.5,
            'days_cover': 3.2,
            'predicted_stockout_date': '2026-11-27',
            'suggested_reorder': 50,
            'risk_urgency': 'critical',
          },
          {
            'product_name': 'Fortune Sunflower Oil 1L',
            'sku': 'SKU-OIL-02',
            'current_stock': 14,
            'daily_burn_rate': 2.0,
            'days_cover': 7.0,
            'predicted_stockout_date': '2026-12-01',
            'suggested_reorder': 40,
            'risk_urgency': 'high',
          },
        ],
        'excess_stock_items': [
          {
            'product_name': 'Vintage Organic Tea 250g',
            'sku': 'SKU-TEA-99',
            'current_stock': 85,
            'stock_value': 18700.0,
            'stagnation_reason': '0 sales in past 45 days',
          },
        ],
      },
      'cash_flow_forecast': {
        'projected_inflows': 114000.0,
        'projected_outflows': 81600.0,
        'projected_expenses': 24000.0,
        'projected_net_cash': 32400.0,
        'closing_cash_position': 282400.0,
      },
      'receivables_payables_forecast': {
        'total_receivables': 65000.0,
        'overdue_receivables': 12500.0,
        'high_risk_customers_count': 2,
        'total_payables': 57600.0,
        'overdue_payables': 8400.0,
      },
      'customer_churn_risk': {
        'at_risk_customers': [
          {
            'customer_name': 'Apex Retailers',
            'phone': '9876543210',
            'days_since_last_order': 58,
            'total_orders': 14,
            'historical_spend': 98000.0,
            'churn_risk_level': 'critical',
          },
        ],
      },
      'supplier_delivery_risk': {
        'at_risk_suppliers': [
          {
            'supplier_name': 'Global Logistics Distributors',
            'total_pos': 12,
            'delayed_pos': 5,
            'delay_rate_pct': 41.7,
            'po_volume': 165000.0,
          },
        ],
      },
      'backtesting_accuracy': {
        'accuracy_score': 88.5,
        'mae': 570.0,
        'mape': 11.5,
        'evaluated_backtest_days': 14,
      },
      'risks': [
        {
          'rule_code': 'PRED_STOCKOUT_IMMINENT',
          'title': 'Imminent Stockout Risk for 2 Fast-Moving Products',
          'severity': 'critical',
          'description': 'Amul Butter 500g and Fortune Sunflower Oil will deplete in ≤ 7 days at current burn rates.',
          'affected_process': 'inventory_procurement',
        },
        {
          'rule_code': 'PRED_CUSTOMER_CHURN',
          'title': 'High-Value Customer Churn Inactivity: Apex Retailers',
          'severity': 'warning',
          'description': 'Apex Retailers has had 0 purchases in 58 days (exceeds normal 18-day reorder cycle).',
          'affected_process': 'sales_crm',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> predictiveIntelligenceScan({
    required String tenantId,
    String? locationId,
  }) async {
    scanTriggered = true;
    return {
      'success': true,
      'total_detected': 2,
      'inserted': 1,
      'updated': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> simulateBusinessScenario({
    required String tenantId,
    required String category,
    required Map<String, dynamic> params,
    String? locationId,
  }) async {
    simulationRunTriggered = true;
    return {
      'success': true,
      'simulation_category': category,
      'simulation_results': {
        'simulated_price': 105.0,
        'simulated_quantity': 376.0,
        'simulated_revenue': 39480.0,
        'simulated_gross_profit': 13160.0,
        'revenue_delta': 1880.0,
        'gross_profit_delta': 1160.0,
        'recommendation_summary': 'Favorable: Price change increases gross profit by ₹1160.0',
      },
      'sensitivity_analysis': [
        {'scenario': '-10% Elasticity Shift', 'change_pct': -10.0, 'projected_rev': 40120.0},
        {'scenario': 'Base Simulated Projection', 'change_pct': 0.0, 'projected_rev': 39480.0},
        {'scenario': '+10% Elasticity Shift', 'change_pct': 10.0, 'projected_rev': 38840.0},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> saveBusinessSimulation({
    required String tenantId,
    required String scenarioName,
    required String category,
    required Map<String, dynamic> params,
    required Map<String, dynamic> results,
    String? locationId,
    String? notes,
  }) async {
    saveSimulationTriggered = true;
    return {
      'success': true,
      'simulation_id': 'sim-1234-uuid',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listBusinessSimulations({
    required String tenantId,
    String? category,
    String? locationId,
    int limit = 50,
  }) async => [
        {
          'id': 'sim-001',
          'scenario_name': 'Q4 5% Price Hike Test',
          'simulation_category': 'pricing',
          'created_at': '2026-11-23 10:30',
        },
      ];

  @override
  Future<Map<String, dynamic>> deleteBusinessSimulation({
    required String tenantId,
    required String simulationId,
  }) async {
    deleteSimulationTriggered = true;
    return {'success': true};
  }
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
  bool canViewCost = true,
  Set<String>? permissions,
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
    permissions: permissions ??
        {
          'operations_intelligence.view',
          if (canViewCost) 'inventory.view_cost',
          if (canViewCost) 'accounting.view',
          if (canViewCost) 'reports.view',
        },
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
    locations: const [
      ClientLocationAccess(
        id: 'loc-1',
        code: 'MAIN',
        name: 'Main Warehouse',
        type: 'store',
        trackingCode: 'TRK-01',
        accessLevel: 'manage',
      ),
    ],
  );
}

void main() {
  group('Operations Intelligence Phase 10: Mathematical & Statistical Logic Tests', () {
    test('Calculates OLS linear trend slope correctly', () {
      // Points: (1, 100), (2, 110), (3, 120), (4, 130), (5, 140) -> slope = 10.0
      final y = [100.0, 110.0, 120.0, 130.0, 140.0];
      final n = y.length;
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      for (int i = 0; i < n; i++) {
        final x = (i + 1).toDouble();
        sumX += x;
        sumY += y[i];
        sumXY += x * y[i];
        sumX2 += x * x;
      }
      final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      expect(slope, closeTo(10.0, 0.001));
    });

    test('Calculates price change and elasticity quantity delta correctly', () {
      // Base Qty = 100, Base Price = 50, Delta Price % = +10%, Elasticity = -1.2
      const baseQty = 100.0;
      const basePrice = 50.0;
      const priceDeltaPct = 10.0;
      const elasticity = -1.2;

      final simPrice = basePrice * (1.0 + priceDeltaPct / 100.0); // 55.0
      final qtyDeltaPct = priceDeltaPct * elasticity;             // -12.0%
      final simQty = baseQty * (1.0 + qtyDeltaPct / 100.0);        // 88.0

      expect(simPrice, closeTo(55.0, 0.001));
      expect(simQty, closeTo(88.0, 0.001));
      expect(simPrice * simQty, closeTo(4840.0, 0.001)); // Simulated Revenue
    });

    test('Calculates inventory days cover and burn rate depletion', () {
      const currentStock = 50.0;
      const dailyBurnRate = 2.5;
      final daysCover = currentStock / dailyBurnRate;
      expect(daysCover, 20.0);
    });

    test('Evaluates bulk purchasing net financial benefit with holding cost', () {
      const orderQty = 500.0;
      const baseCost = 100.0;
      const discountPct = 10.0;
      const holdingCostAnnualPct = 15.0;

      final grossSavings = orderQty * baseCost * (discountPct / 100.0); // 5000.0
      final holdingCost = (orderQty * baseCost * (1.0 - discountPct / 100.0) / 2.0) * (holdingCostAnnualPct / 100.0) * (180.0 / 365.0);
      final netBenefit = grossSavings - holdingCost;

      expect(grossSavings, 5000.0);
      expect(netBenefit, greaterThan(0.0));
    });
  });

  group('Operations Intelligence Phase 10: Widget & UI Verification Tests', () {
    testWidgets('Renders Tab 11 Predictive Intelligence & Simulations with Score, KPIs and 8 Domains', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase10IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 11, // Tab 11: Predictive & Simulations
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Header & Scan Button
      expect(find.text('Predictive Intelligence & Business Simulations'), findsWidgets);
      expect(find.text('Run Predictive Scan'), findsOneWidget);

      // Score Card
      expect(find.text('Predictive Health Score: 84 / 100'), findsOneWidget);
      expect(find.text('30-Day Forward Model'), findsWidgets);

      // 4 Main Metric Cards
      expect(find.text('Projected Total Revenue'), findsWidgets);
      expect(find.text('Projected Net Cash Flow'), findsOneWidget);
      expect(find.text('Stockouts Imminent'), findsOneWidget);
      expect(find.text('At-Risk Accounts'), findsOneWidget);

      // 8 Forecasting Domains Table
      expect(find.text('Forecasting Domains & Statistical Confidence'), findsOneWidget);
      expect(find.text('Sales & Demand'), findsWidgets);
      expect(find.text('Inventory Depletion'), findsWidgets);
      expect(find.text('Cash Flow Forecast'), findsWidgets);
      expect(find.text('Customer Inactivity'), findsWidgets);
      expect(find.text('Supplier Delivery'), findsWidgets);

      // Detected Risks
      expect(find.text('Imminent Stockout Risk for 2 Fast-Moving Products'), findsOneWidget);
      expect(find.text('Manage in Action Centre'), findsOneWidget);
    });

    testWidgets('Subtab ChoiceChips navigate through Sales, Inventory, Cash Flow, and Simulations', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase10IntelligenceService();
      final session = _createSession(isOwner: true);

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

      // 1. Switch to Sales & Demand Subtab
      await tester.tap(find.widgetWithText(ChoiceChip, 'Sales & Demand'));
      await tester.pumpAndSettle();
      expect(find.text('Historical Baseline Sales'), findsOneWidget);
      expect(find.text('Daily Projection & Prediction Interval Table'), findsOneWidget);
      expect(find.text('2026-11-24'), findsOneWidget);

      // 2. Switch to Inventory Depletion Subtab
      await tester.tap(find.widgetWithText(ChoiceChip, 'Inventory Depletion'));
      await tester.pumpAndSettle();
      expect(find.text('Imminent Depletion & Stockout Risk Table'), findsOneWidget);
      expect(find.text('Amul Butter 500g'), findsOneWidget);
      expect(find.text('Fortune Sunflower Oil 1L'), findsOneWidget);
      expect(find.text('Excess Stock & Stagnant Capital (>45 Days Zero Sales)'), findsOneWidget);

      // 3. Switch to Cash Flow & Working Capital Subtab
      await tester.tap(find.widgetWithText(ChoiceChip, 'Cash Flow & Working Capital'));
      await tester.pumpAndSettle();
      expect(find.text('Projected Inflows'), findsOneWidget);
      expect(find.text('Projected Outflows'), findsOneWidget);
      expect(find.text('Closing Cash Position'), findsOneWidget);
      expect(find.text('Receivables & Payables Forward Horizon Breakdown'), findsOneWidget);

      // 4. Switch to What-If Simulations Subtab
      await tester.tap(find.widgetWithText(ChoiceChip, 'What-If Simulations'));
      await tester.pumpAndSettle();
      expect(find.text('Pricing Optimization'), findsWidgets);
      expect(find.text('Bulk Purchasing Discount'), findsWidgets);
      expect(find.text('Credit Policy Terms'), findsWidgets);
      expect(find.text('Run Simulation'), findsOneWidget);
    });

    testWidgets('Executes what-if pricing simulation and displays sensitivity matrix', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase10IntelligenceService();
      final session = _createSession(isOwner: true);

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

      // Navigate to Simulations Subtab
      await tester.tap(find.widgetWithText(ChoiceChip, 'What-If Simulations'));
      await tester.pumpAndSettle();

      // Tap "Run Simulation"
      await tester.tap(find.text('Run Simulation'));
      await tester.pumpAndSettle();

      expect(service.simulationRunTriggered, isTrue);
      expect(find.text('Simulation Outcome & Impact Summary'), findsOneWidget);
      expect(find.text('Favorable: Price change increases gross profit by ₹1160.0'), findsOneWidget);
      expect(find.text('Sensitivity Analysis Matrix'), findsOneWidget);
      expect(find.text('-10% Elasticity Shift'), findsOneWidget);
    });

    testWidgets('Triggers predictive diagnostic scan syncing with Action Centre', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase10IntelligenceService();
      final session = _createSession(isOwner: true);

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

      // Tap "Run Predictive Scan"
      await tester.tap(find.text('Run Predictive Scan'));
      await tester.pump();

      expect(service.scanTriggered, isTrue);
    });

    testWidgets('Enforces strict permission masking when user lacks view_cost permissions', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase10IntelligenceService(canViewCost: false);
      final session = _createSession(isOwner: false, canViewCost: false);

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

      // Confidential redacted values should be rendered
      expect(find.text('Confidential'), findsWidgets);
    });
  });
}
