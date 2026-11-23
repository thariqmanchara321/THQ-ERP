import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhase3IntelligenceService extends OperationsIntelligenceService {
  final bool failSales;
  final bool emptyData;

  _MockPhase3IntelligenceService({
    this.failSales = false,
    this.emptyData = false,
  });

  @override
  Future<Map<String, dynamic>> operationsSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    return {
      'flow_metrics': {
        'gross_sales': 120000.0,
        'net_sales': 114000.0,
        'sales_returns': 6000.0,
        'order_count': 95,
        'aov': 1200.0,
        'gross_profit': 38000.0,
      },
      'inventory_metrics': {
        'total_valuation': 350000.0,
        'monitored_variants': 45,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> salesIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    if (failSales) {
      throw StateError('Sales Intelligence backend connection timeout');
    }

    if (emptyData) {
      return {
        'can_view_cost': true,
        'from_date': '2026-10-21',
        'to_date': '2026-11-20',
        'prev_from_date': '2026-09-21',
        'prev_to_date': '2026-10-20',
        'performance': {
          'current': {
            'gross_sales': 0.0,
            'net_sales': 0.0,
            'returns': 0.0,
            'order_count': 0,
            'aov': 0.0,
            'units_sold': 0.0,
            'gross_profit': 0.0,
            'gross_margin_pct': null,
          },
          'previous': {
            'gross_sales': 0.0,
            'net_sales': 0.0,
            'returns': 0.0,
            'order_count': 0,
            'aov': 0.0,
            'units_sold': 0.0,
            'gross_profit': 0.0,
            'gross_margin_pct': null,
          },
          'growth': {
            'gross_sales_pct': 0.0,
            'net_sales_pct': 0.0,
            'returns_pct': 0.0,
            'order_count_pct': 0.0,
            'aov_pct': 0.0,
            'units_sold_pct': 0.0,
            'gross_profit_pct': 0.0,
          },
        },
        'trends': {
          'daily': <Map<String, dynamic>>[],
          'weekly': <Map<String, dynamic>>[],
          'monthly': <Map<String, dynamic>>[],
        },
        'products': {
          'best_selling': <Map<String, dynamic>>[],
          'highest_volume': <Map<String, dynamic>>[],
          'growing_products': <Map<String, dynamic>>[],
          'declining_products': <Map<String, dynamic>>[],
        },
        'categories': <Map<String, dynamic>>[],
        'customer_intelligence': {
          'summary': {
            'total_active_customers': 0,
            'new_customers': 0,
            'repeat_customers': 0,
            'repeat_rate_pct': 0.0,
            'average_customer_spend': 0.0,
            'average_purchase_frequency': 0.0,
            'at_risk_customers': 0,
            'dormant_customers': 0,
          },
          'segments': <Map<String, dynamic>>[],
          'top_customers': <Map<String, dynamic>>[],
        },
        'anomalies': <Map<String, dynamic>>[],
      };
    }

    return {
      'can_view_cost': true,
      'from_date': '2026-10-21',
      'to_date': '2026-11-20',
      'prev_from_date': '2026-09-21',
      'prev_to_date': '2026-10-20',
      'performance': {
        'current': {
          'gross_sales': 125000.0,
          'net_sales': 118500.0,
          'returns': 6500.0,
          'order_count': 92,
          'aov': 1288.04,
          'units_sold': 245.0,
          'gross_profit': 39500.0,
          'gross_margin_pct': 33.33,
        },
        'previous': {
          'gross_sales': 105000.0,
          'net_sales': 101000.0,
          'returns': 4000.0,
          'order_count': 80,
          'aov': 1262.5,
          'units_sold': 210.0,
          'gross_profit': 33500.0,
          'gross_margin_pct': 33.17,
        },
        'growth': {
          'gross_sales_pct': 19.05,
          'net_sales_pct': 17.33,
          'returns_pct': 62.5,
          'order_count_pct': 15.0,
          'aov_pct': 2.02,
          'units_sold_pct': 16.67,
          'gross_profit_pct': 17.91,
        },
      },
      'trends': {
        'daily': [
          {
            'day_date': '2026-11-18',
            'label': 'Wed, Nov 18',
            'gross_sales': 14200.0,
            'net_sales': 13500.0,
            'returns': 700.0,
            'order_count': 11,
          },
          {
            'day_date': '2026-11-19',
            'label': 'Thu, Nov 19',
            'gross_sales': 18500.0,
            'net_sales': 18500.0,
            'returns': 0.0,
            'order_count': 14,
          },
          {
            'day_date': '2026-11-20',
            'label': 'Fri, Nov 20',
            'gross_sales': 22000.0,
            'net_sales': 20500.0,
            'returns': 1500.0,
            'order_count': 16,
          },
        ],
        'weekly': [
          {
            'week_start': '2026-11-09',
            'label': '09 Nov',
            'gross_sales': 42000.0,
            'net_sales': 39500.0,
            'order_count': 32,
          },
          {
            'week_start': '2026-11-16',
            'label': '16 Nov',
            'gross_sales': 54700.0,
            'net_sales': 52500.0,
            'order_count': 41,
          },
        ],
        'monthly': [
          {
            'month_start': '2026-10-01',
            'label': 'Oct 2026',
            'gross_sales': 105000.0,
            'net_sales': 101000.0,
            'order_count': 80,
          },
          {
            'month_start': '2026-11-01',
            'label': 'Nov 2026',
            'gross_sales': 125000.0,
            'net_sales': 118500.0,
            'order_count': 92,
          },
        ],
      },
      'products': {
        'best_selling': [
          {
            'product_name': 'UltraTech Super Cement',
            'variant_name': '50kg Bag',
            'sku': 'SKU-CEM-01',
            'category_name': 'Building Materials',
            'sold_qty': 120.0,
            'revenue': 45600.0,
            'contribution_pct': 36.48,
            'growth_pct': 22.5,
            'gross_profit': 9120.0,
            'margin_pct': 20.0,
          },
          {
            'product_name': 'Tata Tiscon TMT Rebar 12mm',
            'variant_name': '12m Length',
            'sku': 'SKU-STEEL-12',
            'category_name': 'Steel & Metals',
            'sold_qty': 65.0,
            'revenue': 38500.0,
            'contribution_pct': 30.8,
            'growth_pct': 14.2,
            'gross_profit': 6930.0,
            'margin_pct': 18.0,
          },
        ],
        'highest_volume': [
          {
            'product_name': 'UltraTech Super Cement',
            'variant_name': '50kg Bag',
            'sku': 'SKU-CEM-01',
            'category_name': 'Building Materials',
            'sold_qty': 120.0,
            'revenue': 45600.0,
            'contribution_pct': 36.48,
            'growth_pct': 22.5,
            'gross_profit': 9120.0,
            'margin_pct': 20.0,
          },
          {
            'product_name': 'Tata Tiscon TMT Rebar 12mm',
            'variant_name': '12m Length',
            'sku': 'SKU-STEEL-12',
            'category_name': 'Steel & Metals',
            'sold_qty': 65.0,
            'revenue': 38500.0,
            'contribution_pct': 30.8,
            'growth_pct': 14.2,
            'gross_profit': 6930.0,
            'margin_pct': 18.0,
          },
        ],
        'growing_products': [
          {
            'product_name': 'UltraTech Super Cement',
            'variant_name': '50kg Bag',
            'sku': 'SKU-CEM-01',
            'category_name': 'Building Materials',
            'sold_qty': 120.0,
            'revenue': 45600.0,
            'contribution_pct': 36.48,
            'growth_pct': 22.5,
            'gross_profit': 9120.0,
            'margin_pct': 20.0,
          },
        ],
        'declining_products': [
          {
            'product_name': 'Berger WeatherCoat Paint 20L',
            'variant_name': 'White',
            'sku': 'SKU-PNT-20L',
            'category_name': 'Paints & Finishes',
            'sold_qty': 8.0,
            'revenue': 9600.0,
            'contribution_pct': 7.68,
            'growth_pct': -28.0,
            'gross_profit': 1920.0,
            'margin_pct': 20.0,
          },
        ],
      },
      'categories': [
        {
          'category_name': 'Building Materials',
          'revenue': 58000.0,
          'contribution_pct': 46.4,
          'units_sold': 145.0,
          'growth_pct': 18.5,
          'gross_margin_pct': 21.5,
        },
        {
          'category_name': 'Steel & Metals',
          'revenue': 42000.0,
          'contribution_pct': 33.6,
          'units_sold': 72.0,
          'growth_pct': 12.0,
          'gross_margin_pct': 17.8,
        },
        {
          'category_name': 'Paints & Finishes',
          'revenue': 25000.0,
          'contribution_pct': 20.0,
          'units_sold': 28.0,
          'growth_pct': -15.2,
          'gross_margin_pct': 24.0,
        },
      ],
      'customer_intelligence': {
        'summary': {
          'total_active_customers': 28,
          'new_customers': 7,
          'repeat_customers': 21,
          'repeat_rate_pct': 75.0,
          'average_customer_spend': 4232.14,
          'average_purchase_frequency': 3.29,
          'at_risk_customers': 3,
          'dormant_customers': 5,
        },
        'segments': [
          {
            'segment': 'Champions',
            'count': 6,
            'spend': 54000.0,
            'pct_of_customers': 21.43,
            'criteria': 'Recency <= 30d, Frequency >= 4, High Spend (>= 10,000)',
          },
          {
            'segment': 'Loyal Customers',
            'count': 10,
            'spend': 38000.0,
            'pct_of_customers': 35.71,
            'criteria': 'Recency <= 60d, Frequency >= 3 orders',
          },
          {
            'segment': 'Potential Loyalists',
            'count': 5,
            'spend': 14500.0,
            'pct_of_customers': 17.86,
            'criteria': 'Recency <= 30d, 1–2 orders, Returning buyer',
          },
          {
            'segment': 'New Customers',
            'count': 7,
            'spend': 12000.0,
            'pct_of_customers': 25.0,
            'criteria': 'First purchase ever occurred within current analysis period',
          },
          {
            'segment': 'At Risk',
            'count': 3,
            'spend': 0.0,
            'pct_of_customers': 10.71,
            'criteria': 'Recency 61–120d, previously >= 2 lifetime orders',
          },
          {
            'segment': 'Dormant',
            'count': 5,
            'spend': 0.0,
            'pct_of_customers': 17.86,
            'criteria': 'Recency > 120d without recent purchases',
          },
        ],
        'top_customers': [
          {
            'customer_id': 'cust-01',
            'customer_name': 'Skyline Developers LLP',
            'phone': '9845012345',
            'segment': 'Champions',
            'recency_days': 2,
            'period_orders': 8,
            'period_spend': 32500.0,
            'lifetime_orders': 24,
            'lifetime_spend': 118000.0,
            'aov': 4062.5,
          },
          {
            'customer_id': 'cust-02',
            'customer_name': 'Apex Commercial Projects',
            'phone': '9876543210',
            'segment': 'Champions',
            'recency_days': 5,
            'period_orders': 5,
            'period_spend': 21500.0,
            'lifetime_orders': 15,
            'lifetime_spend': 76000.0,
            'aov': 4300.0,
          },
          {
            'customer_id': 'cust-03',
            'customer_name': 'Classic Builders',
            'phone': '9448123456',
            'segment': 'Loyal Customers',
            'recency_days': 12,
            'period_orders': 4,
            'period_spend': 15200.0,
            'lifetime_orders': 9,
            'lifetime_spend': 39000.0,
            'aov': 3800.0,
          },
        ],
      },
      'anomalies': [
        {
          'rule_id': 'ANOM_HIGH_RETURNS',
          'type': 'high_returns',
          'severity': 'warning',
          'title': 'Elevated Sales Return Ratio',
          'description': 'Sales return rate is 5.49% of gross sales (threshold: 8.00%). Return volume: ₹6,500.',
          'metric_value': 5.49,
          'threshold_value': 8.0,
          'recommended_action': 'Inspect returned items for defects, damaged delivery batches, or billing inaccuracies.',
        },
      ],
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
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> customerCredit({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async {
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> supplierPayables({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async {
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> reorder({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> purchaseOrders({
    required String tenantId,
    String? locationId,
    String? status,
    String query = '',
  }) async {
    return [];
  }
}

void main() {
  const testBusiness = ClientBusiness(
    id: 'test-tenant-832',
    membershipId: 'mem-832',
    name: 'THQ Mega Infra Ltd',
    slug: 'thq-mega-infra',
    businessType: 'retail',
    status: 'active',
  );

  ClientSession createSession({
    bool isOwner = true,
    bool canViewCost = true,
  }) {
    return ClientSession(
      business: testBusiness,
      userId: 'user-832',
      username: 'Operations Manager',
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
      locations: const [
        ClientLocationAccess(
          id: 'loc-main',
          code: 'MAIN',
          name: 'Main Yard',
          type: 'store',
          trackingCode: 'TRK-01',
          accessLevel: 'manage',
        ),
      ],
    );
  }

  group('Phase 3 Sales Intelligence Unit Tests', () {
    test('Calculates period-over-period delta and percentages accurately', () {
      final gross = ComparisonMetric.calculate(125000.0, 105000.0);
      expect(gross.difference, 20000.0);
      expect(gross.percentChange, closeTo(19.05, 0.01));
      expect(gross.isPositive, isTrue);

      final returns = ComparisonMetric.calculate(6500.0, 4000.0);
      expect(returns.difference, 2500.0);
      expect(returns.percentChange, closeTo(62.5, 0.01));

      final aov = ComparisonMetric.calculate(1288.04, 1262.5);
      expect(aov.percentChange, closeTo(2.02, 0.01));
    });

    test('Handles zero previous window values gracefully with 100% change', () {
      final newProd = ComparisonMetric.calculate(45000.0, 0.0);
      expect(newProd.difference, 45000.0);
      expect(newProd.percentChange, 100.0);
      expect(newProd.isPositive, isTrue);
    });

    test('Classifies RFM segmentation rules deterministically', () {
      String classifyRFM({
        required int recencyDays,
        required int periodOrders,
        required double periodSpend,
        required int lifetimeOrders,
        required bool isNewCustomer,
      }) {
        if (recencyDays <= 30 && (periodOrders >= 4 || lifetimeOrders >= 10) && periodSpend >= 10000) {
          return 'Champions';
        }
        if (recencyDays <= 60 && (periodOrders >= 3 || lifetimeOrders >= 5)) {
          return 'Loyal Customers';
        }
        if (recencyDays <= 30 && periodOrders <= 2 && !isNewCustomer) {
          return 'Potential Loyalists';
        }
        if (isNewCustomer && recencyDays <= 30) {
          return 'New Customers';
        }
        if (recencyDays >= 61 && recencyDays <= 120 && lifetimeOrders >= 2) {
          return 'At Risk';
        }
        if (recencyDays > 120) {
          return 'Dormant';
        }
        return 'Occasional Buyers';
      }

      expect(
        classifyRFM(recencyDays: 2, periodOrders: 5, periodSpend: 25000, lifetimeOrders: 15, isNewCustomer: false),
        'Champions',
      );
      expect(
        classifyRFM(recencyDays: 45, periodOrders: 3, periodSpend: 8000, lifetimeOrders: 6, isNewCustomer: false),
        'Loyal Customers',
      );
      expect(
        classifyRFM(recencyDays: 10, periodOrders: 1, periodSpend: 4000, lifetimeOrders: 3, isNewCustomer: false),
        'Potential Loyalists',
      );
      expect(
        classifyRFM(recencyDays: 15, periodOrders: 1, periodSpend: 3500, lifetimeOrders: 1, isNewCustomer: true),
        'New Customers',
      );
      expect(
        classifyRFM(recencyDays: 85, periodOrders: 0, periodSpend: 0, lifetimeOrders: 4, isNewCustomer: false),
        'At Risk',
      );
      expect(
        classifyRFM(recencyDays: 150, periodOrders: 0, periodSpend: 0, lifetimeOrders: 2, isNewCustomer: false),
        'Dormant',
      );
    });
  });

  group('Phase 3 Sales Intelligence Widget Tests', () {
    testWidgets('Renders Sales Intelligence tab, performance metrics, and trends', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = _MockPhase3IntelligenceService();
      final session = createSession(isOwner: true, canViewCost: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: mockService,
              initialTab: 1, // Open Tab 1: Sales Intelligence directly
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Active section title check
      expect(find.text('Sales Intelligence'), findsWidgets);

      // Section 1: Sales Performance KPIs
      expect(find.text('Sales Performance'), findsOneWidget);
      expect(find.text('Gross Sales'), findsOneWidget);
      expect(find.text('Net Sales'), findsWidgets);
      expect(find.text('Sales Returns'), findsOneWidget);
      expect(find.text('Completed Transactions'), findsOneWidget);
      expect(find.text('Average Order Value (AOV)'), findsOneWidget);
      expect(find.text('Total Units Sold'), findsOneWidget);
      expect(find.text('Gross Profit'), findsWidgets);
      expect(find.text('Gross Margin'), findsOneWidget);

      // Section 2: Sales Anomaly Indicators
      expect(find.text('Sales Anomaly & Integrity Indicators'), findsOneWidget);
      expect(find.text('Elevated Sales Return Ratio'), findsOneWidget);
      expect(find.textContaining('Inspect returned items for defects'), findsOneWidget);

      // Section 3: Sales Trends
      expect(find.text('Sales Trends'), findsOneWidget);
      expect(find.textContaining('Daily Revenue Series'), findsOneWidget);

      // Switch to Weekly Trend
      await tester.tap(find.textContaining('Weekly ('));
      await tester.pumpAndSettle();
      expect(find.text('Week Starting'), findsOneWidget);

      // Switch to Monthly Trend
      await tester.tap(find.textContaining('Monthly ('));
      await tester.pumpAndSettle();
      expect(find.text('Month'), findsOneWidget);

      // Section 4: Category Performance
      expect(find.text('Category Performance'), findsOneWidget);
      expect(find.text('Building Materials'), findsWidgets);
      expect(find.text('Steel & Metals'), findsWidgets);
      expect(find.text('Paints & Finishes'), findsWidgets);

      // Section 5: Product Performance & Sub-tabs
      expect(find.text('Product Performance'), findsOneWidget);
      expect(find.text('UltraTech Super Cement (50kg Bag)'), findsWidgets);
      expect(find.text('Tata Tiscon TMT Rebar 12mm (12m Length)'), findsWidgets);

      // Switch to High Volume
      await tester.tap(find.textContaining('High Volume ('));
      await tester.pumpAndSettle();
      expect(find.text('UltraTech Super Cement (50kg Bag)'), findsWidgets);

      // Switch to Declining
      await tester.tap(find.textContaining('Declining ('));
      await tester.pumpAndSettle();
      expect(find.text('Berger WeatherCoat Paint 20L (White)'), findsOneWidget);

      // Scroll down to Section 6: Customer Purchasing Intelligence & RFM
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Customer Purchasing & RFM Intelligence'), findsOneWidget);
      expect(find.text('Active Purchasing Customers'), findsOneWidget);
      expect(find.text('New Customers'), findsWidgets);
      expect(find.text('Repeat Customers'), findsOneWidget);
      expect(find.text('Repeat Purchase Rate'), findsOneWidget);
      expect(find.text('Average Customer Spend'), findsOneWidget);
      expect(find.text('Purchase Frequency'), findsOneWidget);
      expect(find.text('At-Risk Customers'), findsOneWidget);
      expect(find.text('Dormant Customers'), findsOneWidget);

      // Scroll further down to RFM Segments and Top Customers Ranking
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      // RFM Segments grid
      expect(find.text('RFM Behavioral Segments'), findsOneWidget);
      expect(find.text('Champions'), findsWidgets);
      expect(find.text('Loyal Customers'), findsWidgets);
      expect(find.text('Potential Loyalists'), findsOneWidget);

      // Top Customers Ranking table
      expect(find.text('Top Customers Ranking'), findsOneWidget);
      expect(find.text('Skyline Developers LLP'), findsOneWidget);
      expect(find.text('Apex Commercial Projects'), findsOneWidget);
      expect(find.text('Classic Builders'), findsOneWidget);
    });

    testWidgets('Restricts cost, gross profit, and margins when user lacks view_cost permission', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = _MockPhase3IntelligenceService();
      final session = createSession(isOwner: false, canViewCost: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: mockService,
              initialTab: 1,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Displays Cost Restricted badge in section header
      expect(find.text('Cost Restricted'), findsWidgets);

      // Profit and margin cards display Access restricted
      expect(find.text('Access restricted'), findsWidgets);

      // Category table hides Gross Margin % column
      expect(find.text('Gross Margin %'), findsNothing);
    });

    testWidgets('Displays positive all-clear banner when no anomalies detected', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: _MockEmptyAnomaliesService(),
              initialTab: 1,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('No sales anomalies detected for this analysis window'), findsOneWidget);
    });

    testWidgets('Handles empty dataset cleanly without division-by-zero crashes', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = _MockPhase3IntelligenceService(emptyData: true);
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: mockService,
              initialTab: 1,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Zero sales rendered cleanly
      expect(find.text('Completed Transactions'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      expect(find.text('No category sales recorded in this period.'), findsOneWidget);
      expect(find.text('No products match this criterion for the selected period.'), findsOneWidget);
    });

    testWidgets('Isolates sales intelligence failure and provides tab retry', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockService = _MockPhase3IntelligenceService(failSales: true);
      final session = createSession();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OperationsIntelligenceScreen(
              session: session,
              service: mockService,
              initialTab: 1,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Sales Intelligence could not be loaded'), findsOneWidget);
      expect(find.textContaining('Sales Intelligence backend connection timeout'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

class _MockEmptyAnomaliesService extends _MockPhase3IntelligenceService {
  @override
  Future<Map<String, dynamic>> salesIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    final base = await super.salesIntelligence(
      tenantId: tenantId,
      locationId: locationId,
      days: days,
      query: query,
    );
    base['anomalies'] = <Map<String, dynamic>>[];
    return base;
  }
}
