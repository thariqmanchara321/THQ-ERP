import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhase4IntelligenceService extends OperationsIntelligenceService {
  final bool failInventory;
  final bool failRebalancing;
  final bool emptyData;

  _MockPhase4IntelligenceService({
    this.failInventory = false,
    this.failRebalancing = false,
    this.emptyData = false,
  });

  @override
  Future<Map<String, dynamic>> operationsSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'days': days,
      'total_monitored_variants': emptyData ? 0 : 5,
      'inventory_value': emptyData ? 0.0 : 425000.0,
      'dead_stock_value': emptyData ? 0.0 : 45000.0,
      'excess_stock_value': emptyData ? 0.0 : 62000.0,
      'rebalancing_opportunities': emptyData ? 0 : 2,
    };
  }

  @override
  Future<Map<String, dynamic>> salesIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    return {
      'can_view_cost': true,
      'from_date': '2026-10-21',
      'to_date': '2026-11-20',
      'performance': {
        'current': {'net_sales': 150000.0},
        'previous': {'net_sales': 130000.0},
        'growth': {'net_sales_pct': 15.38},
      },
      'trends': {'daily': [], 'weekly': [], 'monthly': []},
      'products': {
        'best_selling': [],
        'highest_volume': [],
        'growing_products': [],
        'declining_products': [],
      },
      'categories': [],
      'customer_intelligence': {
        'summary': {},
        'segments': [],
        'top_customers': [],
      },
      'anomalies': [],
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
    if (failInventory) {
      throw StateError('Database connection timeout for inventory RPC');
    }
    if (emptyData) return [];

    return [
      {
        'location_id': 'loc-central',
        'location_name': 'Central Warehouse',
        'product_id': 'prod-01',
        'variant_id': 'var-01',
        'product_name': 'UltraTech 53 Grade Cement',
        'sku': 'SKU-CEM-53',
        'barcode': '8901234001',
        'quantity': 350.0,
        'available': 320.0,
        'reserved_qty': 30.0,
        'incoming_po_qty': 50.0,
        'in_transit_qty': 20.0,
        'net_effective_stock': 390.0,
        'reorder_level': 100.0,
        'max_stock': 250.0,
        'average_cost': 380.0,
        'net_sold_qty': 180.0,
        'sales_value': 75600.0,
        'cumulative_sales_pct': 45.2,
        'avg_daily_sales': 6.0,
        'days_cover': 53.3,
        'turnover_ratio': 0.51,
        'suggested_reorder': 0.0, // Because 320 avail + 70 incoming > 100 reorder
        'stock_value': 121600.0,
        'excess_qty': 70.0,
        'excess_value': 26600.0,
        'status': 'overstock',
        'abc_class': 'A',
        'movement_class': 'fast_moving',
        'days_without_sales': 1,
      },
      {
        'location_id': 'loc-downtown',
        'location_name': 'Downtown Branch',
        'product_id': 'prod-01',
        'variant_id': 'var-01',
        'product_name': 'UltraTech 53 Grade Cement',
        'sku': 'SKU-CEM-53',
        'barcode': '8901234001',
        'quantity': 0.0,
        'available': 0.0,
        'reserved_qty': 0.0,
        'incoming_po_qty': 0.0,
        'in_transit_qty': 0.0,
        'net_effective_stock': 0.0,
        'reorder_level': 60.0,
        'max_stock': 120.0,
        'average_cost': 380.0,
        'net_sold_qty': 90.0,
        'sales_value': 37800.0,
        'cumulative_sales_pct': 67.8,
        'avg_daily_sales': 3.0,
        'days_cover': 0.0,
        'turnover_ratio': 0.0,
        'suggested_reorder': 120.0, // 0 effective stock, reorders to max_stock
        'stock_value': 0.0,
        'excess_qty': 0.0,
        'excess_value': 0.0,
        'status': 'out_of_stock',
        'abc_class': 'A',
        'movement_class': 'fast_moving',
        'days_without_sales': 2,
      },
      {
        'location_id': 'loc-central',
        'location_name': 'Central Warehouse',
        'product_id': 'prod-02',
        'variant_id': 'var-02',
        'product_name': 'TMT Rebar 12mm Fe550D',
        'sku': 'SKU-STL-12MM',
        'barcode': '8901234002',
        'quantity': 25.0,
        'available': 20.0,
        'reserved_qty': 5.0,
        'incoming_po_qty': 10.0,
        'in_transit_qty': 0.0,
        'net_effective_stock': 30.0,
        'reorder_level': 40.0,
        'max_stock': 100.0,
        'average_cost': 550.0,
        'net_sold_qty': 35.0,
        'sales_value': 22750.0,
        'cumulative_sales_pct': 81.4,
        'avg_daily_sales': 1.17,
        'days_cover': 17.1,
        'turnover_ratio': 1.65,
        'suggested_reorder': 70.0, // max (100) - effective (30) = 70
        'stock_value': 11000.0,
        'excess_qty': 0.0,
        'excess_value': 0.0,
        'status': 'low_stock',
        'abc_class': 'B',
        'movement_class': 'normal_moving',
        'days_without_sales': 3,
      },
      {
        'location_id': 'loc-central',
        'location_name': 'Central Warehouse',
        'product_id': 'prod-03',
        'variant_id': 'var-03',
        'product_name': 'Old Batch Texture Paint 20L',
        'sku': 'SKU-PNT-TXT',
        'barcode': '8901234003',
        'quantity': 45.0,
        'available': 45.0,
        'reserved_qty': 0.0,
        'incoming_po_qty': 0.0,
        'in_transit_qty': 0.0,
        'net_effective_stock': 45.0,
        'reorder_level': 10.0,
        'max_stock': 30.0,
        'average_cost': 1000.0,
        'net_sold_qty': 0.0,
        'sales_value': 0.0,
        'cumulative_sales_pct': 100.0,
        'avg_daily_sales': 0.0,
        'days_cover': null,
        'turnover_ratio': 0.0,
        'suggested_reorder': 0.0,
        'stock_value': 45000.0,
        'excess_qty': 15.0,
        'excess_value': 15000.0,
        'status': 'dead_stock',
        'abc_class': 'C',
        'movement_class': 'dead_stock',
        'days_without_sales': 95,
      },
      {
        'location_id': 'loc-downtown',
        'location_name': 'Downtown Branch',
        'product_id': 'prod-04',
        'variant_id': 'var-04',
        'product_name': 'White Synthetic Enamel 1L',
        'sku': 'SKU-PNT-ENM-1L',
        'barcode': '8901234004',
        'quantity': 60.0,
        'available': 60.0,
        'reserved_qty': 0.0,
        'incoming_po_qty': 0.0,
        'in_transit_qty': 0.0,
        'net_effective_stock': 60.0,
        'reorder_level': 20.0,
        'max_stock': 80.0,
        'average_cost': 220.0,
        'net_sold_qty': 6.0,
        'sales_value': 1800.0,
        'cumulative_sales_pct': 98.2,
        'avg_daily_sales': 0.2,
        'days_cover': 300.0,
        'turnover_ratio': 0.14,
        'suggested_reorder': 0.0,
        'stock_value': 13200.0,
        'excess_qty': 0.0,
        'excess_value': 0.0,
        'status': 'healthy',
        'abc_class': 'C',
        'movement_class': 'slow_moving',
        'days_without_sales': 18,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> rebalancing({
    required String tenantId,
    String? locationId,
    int days = 30,
    int limit = 100,
  }) async {
    if (failRebalancing) {
      throw StateError('Rebalancing recommendation engine failure');
    }
    if (emptyData) return [];

    return [
      {
        'variant_id': 'var-01',
        'product_name': 'UltraTech 53 Grade Cement',
        'sku': 'SKU-CEM-53',
        'source_location_id': 'loc-central',
        'source_location_name': 'Central Warehouse',
        'dest_location_id': 'loc-downtown',
        'dest_location_name': 'Downtown Branch',
        'source_available': 320.0,
        'source_excess': 70.0,
        'dest_available': 0.0,
        'dest_shortage': 60.0,
        'suggested_transfer_qty': 60.0,
        'source_stock_after': 260.0,
        'dest_stock_after': 60.0,
        'priority': 'critical',
        'reason':
            'Central Warehouse has 70 surplus units above maximum capacity, while Downtown Branch is stockout with pending demand velocity.',
      },
      {
        'variant_id': 'var-02',
        'product_name': 'TMT Rebar 12mm Fe550D',
        'sku': 'SKU-STL-12MM',
        'source_location_id': 'loc-central',
        'source_location_name': 'Central Warehouse',
        'dest_location_id': 'loc-downtown',
        'dest_location_name': 'Downtown Branch',
        'source_available': 100.0,
        'source_excess': 25.0,
        'dest_available': 5.0,
        'dest_shortage': 15.0,
        'suggested_transfer_qty': 15.0,
        'source_stock_after': 85.0,
        'dest_stock_after': 20.0,
        'priority': 'high',
        'reason':
            'Central Warehouse has 25 transferable units above reorder safety buffer, while Downtown Branch is below safety threshold.',
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> customerCredit({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> supplierPayables({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async => [];

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
}

void main() {
  const testBusiness = ClientBusiness(
    id: 'test-tenant-833',
    membershipId: 'mem-833',
    name: 'THQ Enterprise Retailers',
    slug: 'thq-enterprise',
    businessType: 'retail',
    status: 'active',
  );

  ClientSession createSession({
    bool isOwner = true,
    bool canViewCost = true,
  }) {
    return ClientSession(
      business: testBusiness,
      userId: 'user-833',
      username: 'Inventory Director',
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
        'operations_intelligence.view',
        'inventory.view',
        if (canViewCost) 'inventory.view_cost',
      },
      currencyCode: 'INR',
      timezone: 'Asia/Kolkata',
      locale: 'en_IN',
      locations: const [
        ClientLocationAccess(
          id: 'loc-central',
          code: 'CEN',
          name: 'Central Warehouse',
          type: 'warehouse',
          trackingCode: 'TRK-01',
          accessLevel: 'manage',
        ),
        ClientLocationAccess(
          id: 'loc-downtown',
          code: 'DWN',
          name: 'Downtown Branch',
          type: 'store',
          trackingCode: 'TRK-02',
          accessLevel: 'manage',
        ),
      ],
    );
  }

  Widget createWidget({
    required OperationsIntelligenceService service,
    ClientSession? session,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: OperationsIntelligenceScreen(
          session: session ?? createSession(),
          service: service,
          initialTab: 2, // Direct to Tab 2: Stock Intelligence
        ),
      ),
    );
  }

  group('Operations Intelligence Phase 4: Unit Logic Tests', () {
    test('ABC Pareto cumulative calculation assigns A, B, and C correctly', () {
      final items = [
        {'sku': 'SKU-01', 'sales_val': 7000.0},
        {'sku': 'SKU-02', 'sales_val': 2000.0},
        {'sku': 'SKU-03', 'sales_val': 1000.0},
        {'sku': 'SKU-04', 'sales_val': 0.0},
      ];
      final total = items.fold<double>(0.0, (s, i) => s + (i['sales_val'] as double));
      expect(total, 10000.0);

      double cumulative = 0.0;
      final classified = items.map((i) {
        final val = i['sales_val'] as double;
        cumulative += val;
        final pct = (cumulative / total) * 100.0;
        String abc = 'C';
        if (val > 0 && pct <= 70.001) {
          abc = 'A';
        } else if (val > 0 && pct <= 90.001) {
          abc = 'B';
        }
        return {'sku': i['sku'], 'abc': abc, 'pct': pct};
      }).toList();

      expect(classified[0]['abc'], 'A');
      expect(classified[1]['abc'], 'B');
      expect(classified[2]['abc'], 'C');
      expect(classified[3]['abc'], 'C');
    });

    test('Replenishment calculation deducts incoming PO and in-transit transfers', () {
      // Case 1: Stock is below reorder level, but incoming PO covers it -> NO duplicate order!
      const available = 20.0;
      const incomingPo = 50.0;
      const inTransit = 10.0;
      const reorderLevel = 40.0;
      const maxStock = 100.0;

      const effectiveStock = available + incomingPo + inTransit; // 80
      final suggestedReorder = effectiveStock < reorderLevel
          ? (maxStock - effectiveStock).clamp(0.0, double.infinity)
          : 0.0;

      expect(effectiveStock, 80.0);
      expect(suggestedReorder, 0.0); // Duplicate purchase prevented!

      // Case 2: Effective stock still below reorder level -> Suggest remaining difference
      const lowIncoming = 5.0;
      const lowEffective = available + lowIncoming; // 25 < 40
      final validSuggested = lowEffective < reorderLevel
          ? (maxStock - lowEffective).clamp(0.0, double.infinity)
          : 0.0;

      expect(validSuggested, 75.0);
    });

    test('Inter-store rebalancing ensures source safety buffer retention', () {
      const sourceAvailable = 100.0;
      const sourceMaxStock = 60.0;
      const sourceExcess = sourceAvailable - sourceMaxStock; // 40 transferable surplus

      const destAvailable = 0.0;
      const destReorderLevel = 30.0;
      const destShortage = destReorderLevel - destAvailable; // 30 units needed

      // Suggested transfer quantity is min(sourceExcess, destShortage)
      final suggestedTransfer = (sourceExcess < destShortage ? sourceExcess : destShortage).clamp(0.0, double.infinity);
      expect(suggestedTransfer, 30.0);

      // Verify post-transfer stocks
      final sourceStockAfter = sourceAvailable - suggestedTransfer;
      final destStockAfter = destAvailable + suggestedTransfer;

      expect(sourceStockAfter, 70.0);
      expect(sourceStockAfter >= sourceMaxStock, isTrue); // Buffer preserved!
      expect(destStockAfter, 30.0);
      expect(destStockAfter >= destReorderLevel, isTrue); // Shortage solved!
    });
  });

  group('Operations Intelligence Phase 4: Stock Intelligence Widget Tests', () {
    testWidgets('Renders KPI Banner with Total Valuation, Monitored SKUs, Cover, and Tied Capital', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _MockPhase4IntelligenceService();
      await tester.pumpWidget(createWidget(service: service));
      await tester.pumpAndSettle();

      // Check section header
      expect(find.text('Inventory Performance & Capital Health'), findsOneWidget);

      // Check metric cards
      expect(find.text('Total Stock Value'), findsOneWidget);
      expect(find.text('Monitored Items'), findsOneWidget);
      expect(find.text('Avg Stock Cover'), findsOneWidget);
      expect(find.text('Dead & Slow Capital'), findsOneWidget);
      expect(find.text('Excess Stock Value'), findsOneWidget);
      expect(find.text('Rebalancing Opps'), findsOneWidget);

      // Check values
      expect(find.text('5'), findsOneWidget); // 5 monitored items
      expect(find.text('2'), findsWidgets); // 2 rebalancing opps
    });

    testWidgets('Renders Inter-Store Rebalancing Section with Transfer Suggestions & Reasons', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _MockPhase4IntelligenceService();
      await tester.pumpWidget(createWidget(service: service));
      await tester.pumpAndSettle();

      // Rebalancing Header
      expect(find.text('Inter-Store Stock Rebalancing'), findsOneWidget);
      expect(find.text('2 opportunities'), findsOneWidget);

      // Recommendation details
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('Transfer: 60 units'), findsOneWidget);
      expect(find.text('Transfer: 15 units'), findsOneWidget);

      // Check action buttons
      expect(find.text('Initiate Transfer'), findsNWidgets(2));
    });

    testWidgets('Multi-faceted classification filters: ABC, Velocity, and Health status', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _MockPhase4IntelligenceService();
      await tester.pumpWidget(createWidget(service: service));
      await tester.pumpAndSettle();

      // Check health chips
      expect(find.text('All Health (5)'), findsOneWidget);
      expect(find.text('Out of Stock (1)'), findsOneWidget);
      expect(find.text('Dead Stock (1)'), findsOneWidget);

      // Check ABC chips
      expect(find.text('All ABC'), findsOneWidget);
      expect(find.text('Class A (70% Value) (2)'), findsOneWidget);
      expect(find.text('Class B (20% Value) (1)'), findsOneWidget);
      expect(find.text('Class C (10% & Zero) (2)'), findsOneWidget);

      // Check Velocity chips
      expect(find.text('All Velocity'), findsOneWidget);
      expect(find.text('Fast (2)'), findsOneWidget);
      expect(find.text('Normal (1)'), findsOneWidget);
      expect(find.text('Slow (1)'), findsOneWidget);
      expect(find.text('Dead (1)'), findsOneWidget);

      // Check Smart Inventory button bridge
      expect(find.text('Smart Inventory'), findsOneWidget);

      // Filter by Class A
      await tester.tap(find.text('Class A (70% Value) (2)'));
      await tester.pumpAndSettle();

      // Should now display 2 SKUs in the table
      expect(find.text('Inventory Items (2 SKUs)'), findsOneWidget);
      expect(find.text('UltraTech 53 Grade Cement'), findsWidgets);
      expect(find.text('TMT Rebar 12mm Fe550D'), findsNothing);

      // Filter by Fast Velocity
      await tester.tap(find.text('All ABC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fast (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Inventory Items (2 SKUs)'), findsOneWidget);
      expect(find.text('UltraTech 53 Grade Cement'), findsWidgets);
    });

    testWidgets('Detailed 14-Column table renders incoming stock breakdown and deduplicated suggested reorder', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _MockPhase4IntelligenceService();
      await tester.pumpWidget(createWidget(service: service));
      await tester.pumpAndSettle();

      // Verify table column headers
      expect(find.text('Store'), findsOneWidget);
      expect(find.text('ABC'), findsOneWidget);
      expect(find.text('Velocity'), findsOneWidget);
      expect(find.text('Product'), findsOneWidget);
      expect(find.text('SKU'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Incoming'), findsOneWidget);
      expect(find.text('Reorder'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('Burn Rate'), findsOneWidget);
      expect(find.text('Cover'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      expect(find.text('Stock Value'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);

      // Check incoming breakdown for Central Cement (50 PO + 20 Transit = 70)
      expect(find.text('70'), findsNWidgets(2)); // 70 incoming for cement and 70 suggested reorder for rebar
      expect(find.byTooltip('PO: 50, In-transit: 20'), findsOneWidget);

      // Check suggested reorder:
      // Central Cement: 0 suggested (because 320 avail + 70 incoming > 100 reorder)
      // Downtown Cement: 120 suggested (0 avail + 0 incoming < 60 reorder -> reorders to max 120)
      expect(find.text('120'), findsNWidgets(2)); // Max stock of 120 and suggested reorder of 120
    });

    testWidgets('Cost-restricted users see Hidden/— for inventory values and tied capital', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _MockPhase4IntelligenceService();
      final restrictedSession = createSession(isOwner: false, canViewCost: false);

      await tester.pumpWidget(createWidget(service: service, session: restrictedSession));
      await tester.pumpAndSettle();

      // Check cost restriction badge
      expect(find.text('Cost Restricted'), findsOneWidget);

      // Metric cards should say 'Access restricted'
      expect(find.text('Access restricted'), findsNWidgets(3)); // Total Stock Value, Dead & Slow Capital, Excess Stock Value

      // In the table, Stock Value column must show '—'
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('Graceful error handling when inventory RPC fails', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _MockPhase4IntelligenceService(failInventory: true);
      await tester.pumpWidget(createWidget(service: service));
      await tester.pumpAndSettle();

      // Error banner
      expect(find.text('Stock Intelligence'), findsWidgets);
      expect(find.textContaining('Database connection timeout for inventory RPC'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Graceful handling when rebalancing fails while inventory succeeds', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _MockPhase4IntelligenceService(failRebalancing: true);
      await tester.pumpWidget(createWidget(service: service));
      await tester.pumpAndSettle();

      // Main inventory and table still load!
      expect(find.text('Inventory Performance & Capital Health'), findsOneWidget);
      expect(find.text('Inventory Items (5 SKUs)'), findsOneWidget);
    });

    testWidgets('Handles empty dataset cleanly without division by zero', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = _MockPhase4IntelligenceService(emptyData: true);
      await tester.pumpWidget(createWidget(service: service));
      await tester.pumpAndSettle();

      expect(find.text('No inventory records matching selected filters.'), findsOneWidget);
      expect(find.text('No inter-store transfer opportunities detected for this period. All locations have adequate or balanced stock levels.'), findsOneWidget);
    });
  });
}
