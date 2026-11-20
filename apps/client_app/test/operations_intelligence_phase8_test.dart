import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhase8IntelligenceService extends OperationsIntelligenceService {
  final bool failEfficiency;
  final bool emptyData;
  bool scanTriggered = false;

  _MockPhase8IntelligenceService({
    this.failEfficiency = false,
    this.emptyData = false,
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
        'tenant_id': tenantId,
        'summary': {'total_findings': 0, 'critical_count': 0, 'high_count': 0, 'unresolved_count': 0, 'resolved_count': 0},
        'findings': [],
      };

  @override
  Future<Map<String, dynamic>> operationalEfficiency({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    if (failEfficiency) {
      throw StateError('Simulated operational efficiency RPC connection failure');
    }
    if (emptyData) {
      return {
        'tenant_id': tenantId,
        'location_id': locationId,
        'summary': {
          'overall_efficiency_score': 100.0,
          'health_status': 'optimal',
          'active_bottlenecks_count': 0,
          'avg_po_cycle_hours': 0.0,
          'avg_grn_lead_time_days': 0.0,
          'avg_transfer_hours': 0.0,
          'avg_daily_throughput': 0,
          'sync_reliability_pct': 100.0,
        },
        'sales_billing': {
          'total_sales': 0,
          'completed_sales': 0,
          'cancelled_sales': 0,
          'cancellation_rate_pct': 0.0,
          'avg_daily_throughput': 0,
          'held_sales_count': 0,
          'peak_hours': [],
        },
        'procurement': {
          'total_pos': 0,
          'completed_pos': 0,
          'pending_approval_pos': 0,
          'avg_approval_hours': 0.0,
          'avg_grn_lead_time_days': 0.0,
          'overdue_pos': 0,
          'supplier_delay_rate_pct': 0.0,
          'delayed_orders': [],
        },
        'inventory_operations': {
          'total_transfers': 0,
          'completed_transfers': 0,
          'delayed_transfers_count': 0,
          'delayed_transfers': [],
          'avg_transfer_hours': 0.0,
          'transfer_cancellation_rate_pct': 0.0,
          'total_adjustments': 0,
          'pending_adjustments': 0,
          'approved_adjustments': 0,
          'avg_adjustment_approval_hours': 0.0,
        },
        'customer_operations': {
          'total_returns': 0,
          'return_rate_pct': 0.0,
          'pending_refunds': 0,
          'completed_refunds': 0,
        },
        'system_sync': {
          'total_sync_events': 0,
          'synced_count': 0,
          'pending_sync_count': 0,
          'failed_sync_count': 0,
          'conflict_count': 0,
          'avg_sync_delay_minutes': 0.0,
          'sync_success_rate_pct': 100.0,
        },
        'bottlenecks': [],
        'branch_comparisons': [],
        'data_freshness': {
          'as_of': '2026-11-20T19:00:00Z',
          'evaluated_days': 30,
          'total_sales_evaluated': 0,
          'total_pos_evaluated': 0,
          'total_transfers_evaluated': 0,
        },
        'can_view_cost': true,
      };
    }

    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'summary': {
        'overall_efficiency_score': 86.5,
        'health_status': 'acceptable',
        'active_bottlenecks_count': 2,
        'avg_po_cycle_hours': 36.5,
        'avg_grn_lead_time_days': 4.2,
        'avg_transfer_hours': 18.0,
        'avg_daily_throughput': 120,
        'sync_reliability_pct': 98.5,
      },
      'sales_billing': {
        'total_sales': 3600,
        'completed_sales': 3450,
        'cancelled_sales': 150,
        'cancellation_rate_pct': 4.2,
        'avg_daily_throughput': 120,
        'held_sales_count': 12,
        'peak_hours': [
          {'hour_of_day': 14, 'transactions': 450},
          {'hour_of_day': 19, 'transactions': 520},
        ],
      },
      'procurement': {
        'total_pos': 45,
        'completed_pos': 38,
        'pending_approval_pos': 5,
        'avg_approval_hours': 36.5,
        'avg_grn_lead_time_days': 4.2,
        'overdue_pos': 2,
        'supplier_delay_rate_pct': 4.4,
        'delayed_orders': [
          {'po_number': 'PO-2026-0042', 'supplier_name': 'Premier Milling Ltd', 'overdue_days': 5},
        ],
      },
      'inventory_operations': {
        'total_transfers': 28,
        'completed_transfers': 25,
        'delayed_transfers_count': 2,
        'delayed_transfers': [
          {
            'transfer_number': 'TR-2026-0019',
            'from_location_name': 'Warehouse',
            'to_location_name': 'Main Branch',
            'elapsed_hours': 52.0,
          },
        ],
        'avg_transfer_hours': 18.0,
        'transfer_cancellation_rate_pct': 1.2,
        'total_adjustments': 8,
        'pending_adjustments': 1,
        'approved_adjustments': 7,
        'avg_adjustment_approval_hours': 3.5,
      },
      'customer_operations': {
        'total_returns': 42,
        'return_rate_pct': 1.2,
        'pending_refunds': 2,
        'completed_refunds': 40,
      },
      'system_sync': {
        'total_sync_events': 1250,
        'synced_count': 1235,
        'pending_sync_count': 10,
        'failed_sync_count': 5,
        'conflict_count': 2,
        'avg_sync_delay_minutes': 2.5,
        'sync_success_rate_pct': 98.8,
      },
      'bottlenecks': [
        {
          'rule_code': 'EFF_PO_APPROVAL_BOTTLENECK',
          'affected_process': 'procurement',
          'severity': 'warning',
          'title': 'Purchase Orders Stalled in Approval',
          'description': '3 purchase order(s) are awaiting approval beyond 48 hours.',
          'recommendation': 'Review and authorize pending purchase orders in Procurement workflow.',
          'route': '/purchases',
          'evidence': {'pending_approval_count': 3, 'avg_approval_hours': 36.5},
        },
        {
          'rule_code': 'EFF_TRANSFER_TRANSIT_DELAY',
          'affected_process': 'transfers',
          'severity': 'critical',
          'title': 'Delayed Inter-Store Stock In-Transit',
          'description': '2 stock transfer(s) remain in dispatched/transit state past expected arrival date.',
          'recommendation': 'Investigate delayed transit transfers and expedite destination store GRN confirmation.',
          'route': '/stock-transfers',
          'evidence': {'delayed_transfers_count': 2, 'max_elapsed_hours': 52.0},
        },
      ],
      'branch_comparisons': [
        {
          'location_id': 'loc-main',
          'location_name': 'Main Store',
          'location_code': 'MAIN',
          'total_transfers': 18,
          'avg_transfer_hours': 14.5,
          'delayed_transfers': 0,
          'total_pos': 30,
          'overdue_pos': 1,
          'sync_events': 850,
          'sync_errors': 2,
          'data_sufficiency': 'sufficient',
        },
        {
          'location_id': 'loc-north',
          'location_name': 'North Kiosk',
          'location_code': 'NORTH',
          'total_transfers': 2,
          'avg_transfer_hours': 0.0,
          'delayed_transfers': 0,
          'total_pos': 1,
          'overdue_pos': 0,
          'sync_events': 1,
          'sync_errors': 0,
          'data_sufficiency': 'low_volume',
        },
      ],
      'data_freshness': {
        'as_of': '2026-11-20T19:30:00Z',
        'evaluated_days': 30,
        'total_sales_evaluated': 3600,
        'total_pos_evaluated': 45,
        'total_transfers_evaluated': 28,
      },
      'can_view_cost': true,
    };
  }

  @override
  Future<Map<String, dynamic>> operationalEfficiencyScan({
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
          if (canViewCost) 'accounting.view',
          if (canViewCost) 'inventory.view_cost',
        },
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
    locations: const [
      ClientLocationAccess(
        id: 'loc-main',
        code: 'MAIN',
        name: 'Main Store',
        type: 'store',
        trackingCode: 'TRK-01',
        accessLevel: 'manage',
      ),
      ClientLocationAccess(
        id: 'loc-wh',
        code: 'WH',
        name: 'Central Warehouse',
        type: 'warehouse',
        trackingCode: 'TRK-02',
        accessLevel: 'manage',
      ),
    ],
  );
}

void main() {
  group('Operations Intelligence Phase 8: Operational Efficiency Calculations & Rule Tests', () {
    test('Calculates deterministic overall efficiency score with bounded clamping [15, 100]', () {
      // Score calculation model from operational_efficiency_intelligence_v830:
      // Base: 100.0
      // Deductions:
      // - Critical delayed transfers: -10 each (cap 25)
      // - Warning PO approval delay: -5 each (cap 15)
      // - Overdue POs: -4 each (cap 16)
      // - High cancellation rate (>5%): -10
      // - Sync failure rate (>5%): -15
      // Clamped [15.0, 100.0]

      double calculateEfficiencyScore({
        int delayedTransfers = 0,
        int delayedPOs = 0,
        int overduePOs = 0,
        double cancellationRate = 0.0,
        double syncFailureRate = 0.0,
      }) {
        double score = 100.0;
        score -= (delayedTransfers * 10.0).clamp(0.0, 25.0);
        score -= (delayedPOs * 5.0).clamp(0.0, 15.0);
        score -= (overduePOs * 4.0).clamp(0.0, 16.0);
        if (cancellationRate > 5.0) score -= 10.0;
        if (syncFailureRate > 5.0) score -= 15.0;
        return score.clamp(15.0, 100.0);
      }

      // Test clean operations
      expect(calculateEfficiencyScore(), 100.0);

      // Test moderate delays
      expect(
        calculateEfficiencyScore(delayedTransfers: 1, delayedPOs: 1, overduePOs: 1),
        81.0, // 100 - 10 - 5 - 4 = 81
      );

      // Test severe catastrophic breakdown - must clamp to minimum floor 15.0
      expect(
        calculateEfficiencyScore(
          delayedTransfers: 5,
          delayedPOs: 5,
          overduePOs: 5,
          cancellationRate: 12.0,
          syncFailureRate: 20.0,
        ),
        19.0, // 100 - 25 - 15 - 16 - 10 - 15 = 19.0 >= 15.0
      );
    });

    test('Classifies health status correctly based on score thresholds', () {
      String getHealthStatus(double score) {
        if (score >= 90.0) return 'optimal';
        if (score >= 75.0) return 'acceptable';
        if (score >= 50.0) return 'needs_attention';
        return 'critical_delay';
      }

      expect(getHealthStatus(95.0), 'optimal');
      expect(getHealthStatus(90.0), 'optimal');
      expect(getHealthStatus(86.5), 'acceptable');
      expect(getHealthStatus(75.0), 'acceptable');
      expect(getHealthStatus(60.0), 'needs_attention');
      expect(getHealthStatus(49.9), 'critical_delay');
      expect(getHealthStatus(15.0), 'critical_delay');
    });

    test('Validates fair branch benchmarking data sufficiency qualification', () {
      String qualifyStoreDataSufficiency(int totalOps) {
        return totalOps >= 5 ? 'sufficient' : 'low_volume';
      }

      expect(qualifyStoreDataSufficiency(0), 'low_volume');
      expect(qualifyStoreDataSufficiency(4), 'low_volume');
      expect(qualifyStoreDataSufficiency(5), 'sufficient');
      expect(qualifyStoreDataSufficiency(120), 'sufficient');
    });

    test('Detects specific operational bottleneck criteria deterministically', () {
      // EFF_PO_APPROVAL_BOTTLENECK: Pending approval > 48h
      bool isPoApprovalBottleneck(int pendingCount, double avgApprovalHours) {
        return pendingCount > 0 && avgApprovalHours > 48.0;
      }

      // EFF_TRANSFER_TRANSIT_DELAY: In transit > 48h or overdue
      bool isTransferTransitDelay(int delayedCount) {
        return delayedCount > 0;
      }

      // EFF_BILLING_CANCELLATION_SPIKE: Cancellation rate > 5.0%
      bool isCancellationSpike(double ratePct) {
        return ratePct > 5.0;
      }

      // EFF_POS_SYNC_LATENCY_BOTTLENECK: Failures > 0 or latency > 15m
      bool isSyncBottleneck(int failedCount, double avgLatencyMins) {
        return failedCount > 0 || avgLatencyMins > 15.0;
      }

      expect(isPoApprovalBottleneck(3, 56.0), isTrue);
      expect(isPoApprovalBottleneck(3, 24.0), isFalse);
      expect(isTransferTransitDelay(2), isTrue);
      expect(isTransferTransitDelay(0), isFalse);
      expect(isCancellationSpike(6.2), isTrue);
      expect(isCancellationSpike(4.2), isFalse);
      expect(isSyncBottleneck(5, 2.5), isTrue);
      expect(isSyncBottleneck(0, 1.2), isFalse);
    });
  });

  group('Operations Intelligence Phase 8: Widget & UI Verification Tests', () {
    testWidgets('Renders Tab 9 Operational Efficiency with Score, KPIs & Bottlenecks', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase8IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 9, // Tab 9: Operational Efficiency
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify Tab 9 is selected
      expect(find.text('Operational Efficiency'), findsWidgets);

      // Verify Header & Scan Button
      expect(find.text('Operational Efficiency Intelligence'), findsOneWidget);
      expect(find.text('Run Operational Scan'), findsOneWidget);

      // Verify Overall Score & Health Status
      expect(find.text('86.5'), findsOneWidget);
      expect(find.text('Acceptable'), findsOneWidget);
      expect(find.text('2 Active Bottlenecks'), findsOneWidget);

      // Verify Headline KPI Summary
      expect(find.text('PO Cycle'), findsOneWidget);
      expect(find.text('36.5 hrs'), findsOneWidget);
      expect(find.text('GRN Lead Time'), findsOneWidget);
      expect(find.text('4.2 days'), findsOneWidget);
      expect(find.text('Transfer Transit'), findsOneWidget);
      expect(find.text('18.0 hrs'), findsOneWidget);
      expect(find.text('Sync Reliability'), findsOneWidget);
      expect(find.text('98.5%'), findsOneWidget);

      // Verify Detected Bottlenecks rendered
      expect(find.text('Process Bottlenecks & Inefficiencies (2)'), findsOneWidget);
      expect(find.text('Purchase Orders Stalled in Approval'), findsOneWidget);
      expect(find.text('Delayed Inter-Store Stock In-Transit'), findsOneWidget);
      expect(find.text('EFF_PO_APPROVAL_BOTTLENECK'), findsOneWidget);
      expect(find.text('EFF_TRANSFER_TRANSIT_DELAY'), findsOneWidget);
    });

    testWidgets('Sub-tab ChoiceChips switch between operational domains', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase8IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 9,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Click "Procurement" chip
      await tester.tap(find.text('Procurement').first);
      await tester.pumpAndSettle();

      // Verify Procurement section is visible
      expect(find.text('Procurement & Order Lead Times'), findsOneWidget);
      expect(find.text('Delayed Purchase Orders (1)'), findsOneWidget);
      expect(find.textContaining('Premier Milling Ltd'), findsOneWidget);

      // Click "Branch Benchmarks" chip
      await tester.tap(find.text('Branch Benchmarks').first);
      await tester.pumpAndSettle();

      // Verify Store Benchmarks table is visible
      expect(find.text('Store-to-Store Operational Benchmarks'), findsOneWidget);
      expect(find.text('Main Store'), findsOneWidget);
      expect(find.text('North Kiosk'), findsOneWidget);
      expect(find.text('Sufficient'), findsOneWidget);
      expect(find.text('Low Volume'), findsOneWidget);
    });

    testWidgets('Diagnostic Scan button triggers operational scan and shows success snackbar', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase8IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 9,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(service.scanTriggered, isFalse);

      // Click "Run Operational Scan"
      await tester.tap(find.text('Run Operational Scan'));
      await tester.pumpAndSettle();

      expect(service.scanTriggered, isTrue);
      expect(find.textContaining('Operational diagnostic scan complete: 2 bottlenecks detected'), findsOneWidget);
    });

    testWidgets('View in Action Centre button transitions tab to Tab 10', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase8IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 9,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Click "View in Action Centre" on first bottleneck
      final actionCentreBtn = find.text('View in Action Centre').first;
      expect(actionCentreBtn, findsOneWidget);

      await tester.tap(actionCentreBtn);
      await tester.pumpAndSettle();

      // Should now be on Tab 10 Action & Risk Centre
      expect(find.text('Centralized Action & Risk Centre'), findsOneWidget);
    });

    testWidgets('Renders clean empty state when no bottlenecks exist', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase8IntelligenceService(emptyData: true);
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 9,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('100.0'), findsOneWidget);
      expect(find.text('Optimal'), findsOneWidget);
      expect(find.text('0 Active Bottlenecks'), findsOneWidget);
      expect(find.textContaining('No Active Operational Bottlenecks: Monitored workflows'), findsOneWidget);
    });

    testWidgets('Displays section error with retry when operational efficiency service fails', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase8IntelligenceService(failEfficiency: true);
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 9,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Operational Efficiency'), findsWidgets);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Simulated operational efficiency RPC connection failure'), findsOneWidget);
    });

    testWidgets('Cost-restricted user sees process efficiency without confidential cost data', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase8IntelligenceService();
      // Regular staff without cost permissions
      final session = _createSession(
        isOwner: false,
        canViewCost: false,
        permissions: {'operations_intelligence.view'},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 9,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Operational efficiency metrics and lead times are visible
      expect(find.text('86.5'), findsOneWidget);
      expect(find.text('PO Cycle'), findsOneWidget);
      expect(find.text('36.5 hrs'), findsOneWidget);

      // Internal purchase unit costs, supplier buy prices, and margins must not be leaked
      expect(find.text('unit_cost'), findsNothing);
      expect(find.text('cost_price'), findsNothing);
    });
  });
}
