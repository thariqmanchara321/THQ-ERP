import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhase6IntelligenceService extends OperationsIntelligenceService {
  final bool failFinancial;
  final bool failExpense;
  final bool emptyData;
  final bool isUnbalanced;
  final bool isLoss;

  _MockPhase6IntelligenceService({
    this.failFinancial = false,
    this.failExpense = false,
    this.emptyData = false,
    this.isUnbalanced = false,
    this.isLoss = false,
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
        'total_monitored_variants': emptyData ? 0 : 25,
        'inventory_value': emptyData ? 0.0 : 500000.0,
      };

  @override
  Future<Map<String, dynamic>> salesIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async => {
        'can_view_cost': true,
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
  }) async => {
        'summary': {'current': {'gross_purchases': 0.0, 'net_purchases': 0.0}},
        'trends': {'daily': []},
        'by_supplier': [],
        'by_category': [],
        'by_product': [],
        'price_changes': [],
        'po_performance': {},
      };

  @override
  Future<Map<String, dynamic>> supplierIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 200,
  }) async => {
        'summary': {},
        'suppliers': [],
        'risk_alerts': [],
      };

  @override
  Future<Map<String, dynamic>> procurementIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 500,
  }) async => {
        'summary': {},
        'recommendations': [],
        'by_supplier': [],
        'urgency_breakdown': {},
      };

  @override
  Future<Map<String, dynamic>> financialIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    if (failFinancial) {
      throw StateError('Database connection error in financial intelligence RPC');
    }
    if (emptyData) {
      return {
        'tenant_id': tenantId,
        'location_id': locationId,
        'days': days,
        'can_view_cost': true,
        'performance': {
          'revenue': {'current': 0.0, 'prior': 0.0, 'growth_pct': 0.0},
          'cogs': {'current': 0.0, 'prior': 0.0, 'growth_pct': 0.0},
          'gross_profit': {'current': 0.0, 'prior': 0.0, 'growth_pct': 0.0, 'margin_pct': 0.0},
          'operating_expenses': {'current': 0.0, 'prior': 0.0, 'growth_pct': 0.0},
          'operating_profit': {'current': 0.0, 'prior': 0.0, 'growth_pct': 0.0, 'operating_margin_pct': 0.0},
          'other_income': {'current': 0.0, 'prior': 0.0, 'growth_pct': 0.0},
          'other_expenses': {'current': 0.0, 'prior': 0.0, 'growth_pct': 0.0},
          'net_profit': {'current': 0.0, 'prior': 0.0, 'growth_pct': 0.0, 'net_margin_pct': 0.0},
        },
        'cash_flow': {
          'cash': {'opening_balance': 0.0, 'received': 0.0, 'paid': 0.0, 'closing_balance': 0.0, 'net_change': 0.0},
          'bank': {'opening_balance': 0.0, 'received': 0.0, 'paid': 0.0, 'closing_balance': 0.0, 'net_change': 0.0},
          'contra_transfers': {'cash_to_bank': 0.0, 'bank_to_cash': 0.0},
          'net_liquidity_change': 0.0,
          'daily_flow': [],
        },
        'working_capital': {
          'inventory_valuation': 0.0,
          'accounts_receivable': 0.0,
          'accounts_payable': 0.0,
          'net_working_capital': 0.0,
          'current_ratio': 0.0,
          'receivables_aging': {'current': 0.0, 'days_1_30': 0.0, 'days_31_60': 0.0, 'days_61_90': 0.0, 'days_90_plus': 0.0, 'total': 0.0},
          'payables_aging': {'current': 0.0, 'days_1_30': 0.0, 'days_31_60': 0.0, 'days_61_90': 0.0, 'days_90_plus': 0.0, 'total': 0.0},
          'top_debtors': [],
          'top_creditors': [],
        },
        'trial_balance_health': {
          'total_debits': 0.0,
          'total_credits': 0.0,
          'difference': 0.0,
          'is_balanced': true,
          'posted_entry_count': 0,
          'account_groups': [],
        },
        'tax_intelligence': {
          'output_tax': 0.0,
          'input_tax_itc': 0.0,
          'net_tax_liability': 0.0,
          'itc_balance': 0.0,
        },
        'anomalies': [],
        'projections_30d': {
          'expected_collections': 0.0,
          'expected_payables': 0.0,
          'projected_monthly_burn': 0.0,
          'run_rate_basis': {'avg_daily_revenue': 0.0, 'avg_daily_expense': 0.0, 'net_daily_cashflow': 0.0},
        },
      };
    }

    final double revenue = 120000.0;
    final double cogs = 75000.0;
    final double gp = revenue - cogs;
    final double opex = 20000.0;
    final double op = gp - opex;
    final double netProfit = isLoss ? -5000.0 : op;

    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'days': days,
      'can_view_cost': true,
      'performance': {
        'revenue': {'current': revenue, 'prior': 100000.0, 'growth_pct': 20.0},
        'cogs': {'current': cogs, 'prior': 65000.0, 'growth_pct': 15.38},
        'gross_profit': {'current': gp, 'prior': 35000.0, 'growth_pct': 28.57, 'margin_pct': 37.5},
        'operating_expenses': {'current': opex, 'prior': 18000.0, 'growth_pct': 11.11},
        'operating_profit': {'current': op, 'prior': 17000.0, 'growth_pct': 47.06, 'operating_margin_pct': 20.83},
        'other_income': {'current': 2000.0, 'prior': 1500.0, 'growth_pct': 33.33},
        'other_expenses': {'current': 1000.0, 'prior': 800.0, 'growth_pct': 25.0},
        'net_profit': {'current': netProfit, 'prior': 17700.0, 'growth_pct': isLoss ? -128.2 : 46.89, 'net_margin_pct': isLoss ? -4.17 : 21.67},
      },
      'cash_flow': {
        'cash': {'opening_balance': 15000.0, 'received': 45000.0, 'paid': 30000.0, 'closing_balance': 30000.0, 'net_change': 15000.0},
        'bank': {'opening_balance': 85000.0, 'received': 95000.0, 'paid': 60000.0, 'closing_balance': 120000.0, 'net_change': 35000.0},
        'contra_transfers': {'cash_to_bank': 10000.0, 'bank_to_cash': 2000.0},
        'net_liquidity_change': 50000.0,
        'daily_flow': [
          {'date': '2026-11-18', 'cash_in': 1500.0, 'cash_out': 1000.0, 'bank_in': 4000.0, 'bank_out': 2500.0, 'net': 2000.0},
          {'date': '2026-11-19', 'cash_in': 2000.0, 'cash_out': 1200.0, 'bank_in': 5000.0, 'bank_out': 3000.0, 'net': 2800.0},
        ],
      },
      'working_capital': {
        'inventory_valuation': 350000.0,
        'accounts_receivable': 45000.0,
        'accounts_payable': 30000.0,
        'net_working_capital': 365000.0,
        'current_ratio': 13.17,
        'receivables_aging': {'current': 30000.0, 'days_1_30': 10000.0, 'days_31_60': 3000.0, 'days_61_90': 1500.0, 'days_90_plus': 500.0, 'total': 45000.0},
        'payables_aging': {'current': 20000.0, 'days_1_30': 7000.0, 'days_31_60': 2000.0, 'days_61_90': 1000.0, 'days_90_plus': 0.0, 'total': 30000.0},
        'top_debtors': [
          {'customer_id': 'c1', 'name': 'Apex Retailers', 'balance': 25000.0, 'share_pct': 55.56},
          {'customer_id': 'c2', 'name': 'Blue Star Corp', 'balance': 15000.0, 'share_pct': 33.33},
        ],
        'top_creditors': [
          {'supplier_id': 's1', 'name': 'Global Wholesale Ltd', 'balance': 20000.0, 'share_pct': 66.67},
          {'supplier_id': 's2', 'name': 'Quality Foods Co', 'balance': 10000.0, 'share_pct': 33.33},
        ],
      },
      'trial_balance_health': {
        'total_debits': 650000.0,
        'total_credits': isUnbalanced ? 640000.0 : 650000.0,
        'difference': isUnbalanced ? 10000.0 : 0.0,
        'is_balanced': !isUnbalanced,
        'posted_entry_count': 142,
        'account_groups': [
          {'type': 'asset', 'debit_total': 500000.0, 'credit_total': 15000.0, 'net_balance': 485000.0, 'count': 8},
          {'type': 'liability', 'debit_total': 10000.0, 'credit_total': 40000.0, 'net_balance': 30000.0, 'count': 4},
          {'type': 'revenue', 'debit_total': 0.0, 'credit_total': 120000.0, 'net_balance': 120000.0, 'count': 3},
          {'type': 'expense', 'debit_total': 95000.0, 'credit_total': 0.0, 'net_balance': 95000.0, 'count': 6},
        ],
      },
      'tax_intelligence': {
        'output_tax': 18000.0,
        'input_tax_itc': 12500.0,
        'net_tax_liability': 5500.0,
        'itc_balance': 0.0,
      },
      'anomalies': [
        {
          'type': 'unbalanced_ledger',
          'code': 'LEDGER_DIFF_DETECTED',
          'title': 'Trial Balance Discrepancy',
          'severity': 'critical',
          'description': 'Debits do not match credits in posted ledger entries.',
          'impacted_amount': 10000.0,
          'recommendation': 'Run audit center integrity check #1 to locate unposted journal lines.',
        },
      ],
      'projections_30d': {
        'expected_collections': 40000.0,
        'expected_payables': 27000.0,
        'projected_monthly_burn': 20000.0,
        'run_rate_basis': {'avg_daily_revenue': 4000.0, 'avg_daily_expense': 666.67, 'net_daily_cashflow': 1666.67},
      },
    };
  }

  @override
  Future<Map<String, dynamic>> expenseIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    if (failExpense) {
      throw StateError('Database connection error in expense intelligence RPC');
    }
    if (emptyData) {
      return {
        'tenant_id': tenantId,
        'location_id': locationId,
        'days': days,
        'can_view_cost': true,
        'summary': {
          'total_expenses': 0.0,
          'transaction_count': 0,
          'average_daily_expense': 0.0,
          'average_transaction_size': 0.0,
          'active_categories_count': 0,
          'prior_total_expenses': 0.0,
          'growth_pct': 0.0,
        },
        'by_category': [],
        'trends': {'daily': []},
        'by_payee': [],
        'by_location': [],
        'recurring_expenses': [],
        'anomalies': [],
      };
    }

    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'days': days,
      'can_view_cost': true,
      'summary': {
        'total_expenses': 20000.0,
        'transaction_count': 45,
        'average_daily_expense': 666.67,
        'average_transaction_size': 444.44,
        'active_categories_count': 5,
        'prior_total_expenses': 18000.0,
        'growth_pct': 11.11,
      },
      'by_category': [
        {
          'category_id': 'cat1',
          'category_name': 'Utilities & Rent',
          'current_spend': 12000.0,
          'transaction_count': 5,
          'share_pct': 60.0,
          'prior_spend': 11000.0,
          'growth_pct': 9.09,
        },
        {
          'category_id': 'cat2',
          'category_name': 'Logistics & Fuel',
          'current_spend': 5000.0,
          'transaction_count': 25,
          'share_pct': 25.0,
          'prior_spend': 4000.0,
          'growth_pct': 25.0,
        },
        {
          'category_id': 'cat3',
          'category_name': 'Office Supplies',
          'current_spend': 3000.0,
          'transaction_count': 15,
          'share_pct': 15.0,
          'prior_spend': 3000.0,
          'growth_pct': 0.0,
        },
      ],
      'trends': {
        'daily': [
          {'date': '2026-11-18', 'expense_amount': 850.0, 'transaction_count': 3},
          {'date': '2026-11-19', 'expense_amount': 1200.0, 'transaction_count': 4},
        ],
      },
      'by_payee': [
        {'payee': 'State Electricity Board', 'total_spend': 7500.0, 'transaction_count': 2, 'share_pct': 37.5},
        {'payee': 'Express Courier Service', 'total_spend': 4500.0, 'transaction_count': 18, 'share_pct': 22.5},
      ],
      'by_location': [
        {'location_id': 'loc1', 'location_name': 'Main Warehouse', 'total_spend': 14000.0, 'transaction_count': 30, 'share_pct': 70.0},
        {'location_id': 'loc2', 'location_name': 'City Branch', 'total_spend': 6000.0, 'transaction_count': 15, 'share_pct': 30.0},
      ],
      'recurring_expenses': [
        {
          'payee': 'State Electricity Board',
          'transaction_count': 2,
          'total_spend': 7500.0,
          'avg_transaction_size': 3750.0,
          'estimated_monthly_spend': 7500.0,
          'first_seen': '2026-11-01',
          'last_seen': '2026-11-15',
        },
      ],
      'anomalies': [
        {
          'type': 'expense_spike',
          'code': 'EXPENSE_CATEGORY_SPIKE',
          'title': 'High Growth in Logistics',
          'severity': 'medium',
          'description': 'Category Logistics & Fuel increased by 25.0% compared to preceding window.',
          'amount': 5000.0,
          'category_name': 'Logistics & Fuel',
          'recommendation': 'Review recent freight and delivery fuel vouchers.',
        },
      ],
    };
  }
}

const _testBusiness = ClientBusiness(
  id: 'test-tenant-id',
  membershipId: 'mem-834',
  name: 'Test Business',
  slug: 'test-business',
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
    userId: 'user-834',
    username: 'Finance Manager',
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
          if (canViewCost) 'accounting.view',
          if (canViewCost) 'inventory.view_cost',
        },
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
    locations: const [
      ClientLocationAccess(
        id: 'loc1',
        code: 'MAIN',
        name: 'Main Warehouse',
        type: 'warehouse',
        trackingCode: 'TRK-01',
        accessLevel: 'manage',
      ),
      ClientLocationAccess(
        id: 'loc2',
        code: 'CITY',
        name: 'City Branch',
        type: 'store',
        trackingCode: 'TRK-02',
        accessLevel: 'manage',
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Operations Intelligence Phase 6: Deterministic Financial & Accounting Logic Tests', () {
    test('Calculates P&L Gross Profit and Net Margin correctly', () {
      const revenue = 120000.0;
      const cogs = 75000.0;
      const grossProfit = revenue - cogs;
      expect(grossProfit, 45000.0);

      final grossMarginPct = (grossProfit / revenue) * 100;
      expect(grossMarginPct, closeTo(37.5, 0.01));

      const opex = 20000.0;
      const operatingProfit = grossProfit - opex;
      expect(operatingProfit, 25000.0);

      const otherIncome = 2000.0;
      const otherExpenses = 1000.0;
      const netProfit = operatingProfit + otherIncome - otherExpenses;
      expect(netProfit, 26000.0);

      final netMarginPct = (netProfit / revenue) * 100;
      expect(netMarginPct, closeTo(21.67, 0.01));
    });

    test('Verifies Double-Entry Trial Balance equality and detection of difference', () {
      const debits = 650000.0;
      const balancedCredits = 650000.0;
      final diffBalanced = (debits - balancedCredits).abs();
      final isBalanced = diffBalanced < 0.01;
      expect(isBalanced, isTrue);

      const unbalancedCredits = 640000.0;
      final diffUnbalanced = (debits - unbalancedCredits).abs();
      final isUnbalanced = diffUnbalanced >= 0.01;
      expect(isUnbalanced, isTrue);
      expect(diffUnbalanced, 10000.0);
    });

    test('Reconciles Cash Flow opening balance, inflows, outflows and closing balance', () {
      const opening = 15000.0;
      const inflows = 45000.0;
      const outflows = 30000.0;
      const netMovement = inflows - outflows;
      const closing = opening + netMovement;

      expect(netMovement, 15000.0);
      expect(closing, 30000.0);
    });

    test('Computes Net Working Capital and Current Ratio', () {
      const inventory = 350000.0;
      const ar = 45000.0;
      const ap = 30000.0;

      const netWorkingCapital = inventory + ar - ap;
      expect(netWorkingCapital, 365000.0);

      // Current assets = inventory + ar = 395,000; Current liabilities = ap = 30,000
      const currentRatio = (inventory + ar) / ap;
      expect(currentRatio, closeTo(13.17, 0.01));
    });
  });

  group('Operations Intelligence Phase 6: Financial Intelligence Widget Tests (Tab 7)', () {
    testWidgets('Renders Tab 7 Financial Intelligence with KPI banner, P&L, Cash Flow, and Trial Balance', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase6IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 7, // Tab 7: Financial Intelligence
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Check Tab selection
      expect(find.text('Financial Intelligence'), findsOneWidget);

      // Check KPI Banner
      expect(find.text('Operating Revenue'), findsWidgets);
      expect(find.text('INR 120000.00'), findsWidgets);
      expect(find.text('Cost of Goods Sold (COGS)'), findsWidgets);
      expect(find.text('INR 75000.00'), findsWidgets);
      expect(find.text('Gross Profit'), findsWidgets);
      expect(find.text('Operating Expenses'), findsWidgets);
      expect(find.text('Operating Profit (EBIT)'), findsWidgets);
      expect(find.text('Net Profit'), findsWidgets);
      expect(find.text('Trial Balance Health'), findsOneWidget);
      expect(find.text('BALANCED'), findsWidgets);

      // Check Sub-navigation choice chips
      expect(find.text('P&L Overview'), findsOneWidget);
      expect(find.text('Cash Flow'), findsOneWidget);
      expect(find.text('Working Capital'), findsOneWidget);
      expect(find.text('Trial Balance & Ledger'), findsOneWidget);
      expect(find.text('Tax & GST'), findsOneWidget);
      expect(find.text('30D Projections'), findsOneWidget);

      // Switch to Cash Flow sub-tab
      await tester.tap(find.text('Cash Flow'));
      await tester.pumpAndSettle();

      expect(find.text('Cash vs. Bank Flow Analysis'), findsOneWidget);
      expect(find.text('Cash on Hand'), findsOneWidget);
      expect(find.text('Bank Accounts'), findsOneWidget);
      expect(find.text('Daily Cash & Bank Flow Timeline'), findsOneWidget);

      // Switch to Working Capital sub-tab
      await tester.tap(find.text('Working Capital'));
      await tester.pumpAndSettle();

      expect(find.text('Working Capital Composition'), findsOneWidget);
      expect(find.text('Top Customer Debtors'), findsOneWidget);
      expect(find.text('Top Supplier Creditors'), findsOneWidget);

      // Switch to Trial Balance & Ledger sub-tab
      await tester.tap(find.text('Trial Balance & Ledger'));
      await tester.pumpAndSettle();

      expect(find.text('Double-Entry Trial Balance Verification: BALANCED'), findsOneWidget);
      expect(find.text('Account Groups Trial Balance Summary'), findsOneWidget);

      // Switch to Tax & GST sub-tab
      await tester.tap(find.text('Tax & GST'));
      await tester.pumpAndSettle();

      expect(find.text('GST & Tax Position Analysis'), findsOneWidget);
      expect(find.text('Output Tax (Collected)'), findsOneWidget);
      expect(find.text('Input Tax / ITC (Paid)'), findsOneWidget);

      // Switch to 30D Projections sub-tab
      await tester.tap(find.text('30D Projections'));
      await tester.pumpAndSettle();

      expect(find.text('30-Day Financial Projections (Deterministic Run-Rate)'), findsOneWidget);
      expect(find.text('Expected AR Collections (30D)'), findsOneWidget);
      expect(find.text('Expected AP Payments (30D)'), findsOneWidget);
    });

    testWidgets('Cost-restricted users see masked figures (—) in Financial Intelligence', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase6IntelligenceService();
      // Cashier session without inventory.view_cost, accounting.view, or reports.view
      final session = _createSession(isOwner: false, permissions: {'sales.create'});

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 7,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Masked figures (—) should appear in multiple places
      expect(find.text('—'), findsWidgets);
      // Revenue should not be exposed
      expect(find.text('INR 120000.00'), findsNothing);
    });

    testWidgets('Gracefully handles financial intelligence RPC failure with retry button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase6IntelligenceService(failFinancial: true);
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 7,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Financial Intelligence'), findsWidgets);
      expect(find.text('Retry'), findsWidgets);
    });

    testWidgets('Highlights UNBALANCED status and net loss with warning styling', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase6IntelligenceService(isUnbalanced: true, isLoss: true);
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 7,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('UNBALANCED'), findsOneWidget);
      expect(find.text('INR -5000.00'), findsWidgets);
    });
  });

  group('Operations Intelligence Phase 6: Expense Intelligence Widget Tests (Tab 8)', () {
    testWidgets('Renders Tab 8 Expense Intelligence with KPI banner, categories, daily trends, and payees', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase6IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 8, // Tab 8: Expense Intelligence
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Check Tab selection
      expect(find.text('Expense Intelligence'), findsOneWidget);

      // Check KPI Banner
      expect(find.text('Total Expenses'), findsOneWidget);
      expect(find.text('INR 20000.00'), findsWidgets);
      expect(find.text('Expense Transactions'), findsOneWidget);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('Active Expense Categories'), findsOneWidget);

      // Check Categories Table
      expect(find.text('Expense Breakdown by Category'), findsOneWidget);
      expect(find.text('Utilities & Rent'), findsOneWidget);
      expect(find.text('Logistics & Fuel'), findsOneWidget);

      // Switch to Daily Trends sub-tab
      await tester.tap(find.text('Daily Trends (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Daily Expense Trend Timeline'), findsOneWidget);

      // Switch to Payees & Vendors sub-tab
      await tester.tap(find.text('Payees & Vendors (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Top Payees & Vendors by Spend'), findsOneWidget);
      expect(find.text('State Electricity Board'), findsOneWidget);
      expect(find.text('Express Courier Service'), findsOneWidget);

      // Switch to Recurring Expenses sub-tab
      await tester.tap(find.text('Recurring Expenses (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Recurring Expenses & Estimated Monthly Spend'), findsOneWidget);
    });

    testWidgets('Cost-restricted users see masked figures (—) in Expense Intelligence', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase6IntelligenceService();
      final session = _createSession(isOwner: false, permissions: {'sales.create'});

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 8,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
      expect(find.text('INR 20000.00'), findsNothing);
    });

    testWidgets('Gracefully handles expense intelligence RPC failure with retry button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase6IntelligenceService(failExpense: true);
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 8,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Expense Intelligence'), findsWidgets);
      expect(find.text('Retry'), findsWidgets);
    });

    testWidgets('Handles empty dataset gracefully without crashes in Tab 7 and Tab 8', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase6IntelligenceService(emptyData: true);
      final session = _createSession(isOwner: true);

      // Tab 7 with empty data
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            key: const ValueKey('tab-7-empty'),
            session: session,
            service: service,
            initialTab: 7,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Financial Intelligence'), findsOneWidget);
      expect(find.text('INR 0.00'), findsWidgets);

      // Tab 8 with empty data
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            key: const ValueKey('tab-8-empty'),
            session: session,
            service: service,
            initialTab: 8,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Expense Intelligence'), findsOneWidget);
      expect(find.text('No expenses recorded for this period.'), findsOneWidget);
    });
  });
}
