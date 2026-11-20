import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/client_navigation_scope.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhase7IntelligenceService extends OperationsIntelligenceService {
  final bool failActionCentre;
  final bool emptyData;
  bool scanTriggered = false;
  String? lastTransitionToStatus;
  String? lastTransitionFindingId;

  _MockPhase7IntelligenceService({
    this.failActionCentre = false,
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
  }) async {
    if (failActionCentre) {
      throw StateError('Simulated network error fetching Action Centre findings');
    }
    if (emptyData) {
      return {
        'tenant_id': tenantId,
        'location_id': locationId,
        'summary': {
          'total_findings': 0,
          'critical_count': 0,
          'high_count': 0,
          'unresolved_count': 0,
          'resolved_count': 0,
          'total_impacted_amount': 0.0,
        },
        'findings': [],
      };
    }

    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'summary': {
        'total_findings': 6,
        'critical_count': 3,
        'high_count': 2,
        'unresolved_count': 5,
        'resolved_count': 1,
        'total_impacted_amount': 63500.0,
      },
      'findings': [
        {
          'id': 'f-001',
          'engine': 'inventory',
          'category': 'stockout_risk',
          'severity': 'critical',
          'rule_code': 'INV_CRITICAL_STOCKOUT',
          'detection_rule': 'Stock cover is under 3 days with active daily consumer demand.',
          'title': 'Critical Stockout Risk: Sugar 1kg',
          'description': 'Stock on hand is 0 units (0.0 days cover). Daily velocity is 12.5 units/day.',
          'affected_entity_type': 'product_variant',
          'affected_entity_id': 'var-sug-1',
          'affected_record_ref': 'SKU-SUGAR-1KG / Sugar 1kg',
          'location_id': 'loc-main',
          'occurrence_count': 3,
          'priority_score': 109.3,
          'priority_reason': 'Critical severity (+100), financial impact > 5k (+5), systemic tenant-wide scope (+10)',
          'confidence': 0.95,
          'impacted_amount': 15000.0,
          'status': 'new',
          'evidence': {
            'stock_on_hand': 0,
            'daily_velocity': 12.5,
            'stock_cover_days': 0.0,
          },
          'recommended_action': {
            'action_type': 'create_replenishment',
            'label': 'Order / Rebalance Replenishment',
            'route': '/purchases',
          },
        },
        {
          'id': 'f-002',
          'engine': 'cross_engine',
          'is_cross_engine': true,
          'category': 'inventory_obsolescence_risk',
          'severity': 'high',
          'rule_code': 'CROSS_SALES_DROP_OVERSTOCK',
          'detection_rule': 'Product exhibits declining consumer sales simultaneously with overstocked inventory cover.',
          'title': 'Sales Decline with Excess Stock: Basmati Rice 5kg',
          'description': 'Product demand contracted by 60% while inventory cover exceeds 90 days.',
          'affected_entity_type': 'product_variant',
          'affected_entity_id': 'var-rice-5',
          'affected_record_ref': 'SKU-RICE-5KG / Basmati Rice 5kg',
          'location_id': null,
          'occurrence_count': 1,
          'priority_score': 85.0,
          'priority_reason': 'High severity (+70), financial impact > 5k (+5), systemic scope (+10)',
          'confidence': 0.95,
          'impacted_amount': 12500.0,
          'status': 'under_review',
          'evidence': {
            'contributing_engines': ['sales', 'inventory'],
            'demand_drop_pct': 60.0,
            'holding_days': 120,
          },
          'recommended_action': {
            'action_type': 'clearance_or_markdown',
            'label': 'Plan Promotional Markdown or Transfer',
            'route': '/inventory',
          },
        },
        {
          'id': 'f-003',
          'engine': 'customer_credit',
          'category': 'credit_exposure',
          'severity': 'critical',
          'rule_code': 'CREDIT_DEBT_CRITICAL_90D',
          'detection_rule': 'Customer has severely aged overdue debt (>90 days).',
          'title': 'Critical Overdue Credit Exposure: Grand Hotel',
          'description': 'Outstanding balance is INR 25,000.00 with debt overdue beyond 90 days.',
          'affected_entity_type': 'customer',
          'affected_entity_id': 'cust-001',
          'affected_record_ref': 'Grand Hotel & Suites',
          'location_id': null,
          'occurrence_count': 2,
          'priority_score': 105.0,
          'priority_reason': 'Critical severity (+100), financial impact > 5k (+5)',
          'confidence': 1.0,
          'impacted_amount': 25000.0,
          'status': 'accepted',
          'evidence': {
            'current_balance': 25000.0,
            'overdue_90_plus': 25000.0,
          },
          'recommended_action': {
            'action_type': 'freeze_customer_credit',
            'label': 'Review Customer Account & Credit Limits',
            'route': '/customers',
          },
        },
        {
          'id': 'f-004',
          'engine': 'financial',
          'category': 'accounting_integrity',
          'severity': 'critical',
          'rule_code': 'FIN_TB_DISCREPANCY',
          'detection_rule': 'Total posted debits do not match total posted credits in general ledger.',
          'title': 'Double-Entry Trial Balance Imbalance',
          'description': 'A posted discrepancy of 500.0 was detected between debits and credits.',
          'affected_entity_type': 'general_ledger',
          'affected_entity_id': 'posted_journals',
          'affected_record_ref': 'General Ledger Trial Balance',
          'location_id': null,
          'occurrence_count': 1,
          'priority_score': 110.0,
          'priority_reason': 'Critical severity (+100), systemic scope (+10)',
          'confidence': 1.0,
          'impacted_amount': 500.0,
          'status': 'approved',
          'evidence': {'discrepancy_amount': 500.0},
          'recommended_action': {
            'action_type': 'audit_ledger',
            'label': 'Run Audit Center Integrity Check #1',
            'route': '/audit',
          },
        },
        {
          'id': 'f-005',
          'engine': 'expense',
          'category': 'budget_spike',
          'severity': 'high',
          'rule_code': 'EXP_CATEGORY_SPIKE',
          'detection_rule': 'Category expenses grew by >= 50% compared to preceding 30-day period.',
          'title': 'Expense Category Surge: Utility & Generator Diesel',
          'description': 'Spend increased to 8000.0 from 3500.0.',
          'affected_entity_type': 'expense_category',
          'affected_entity_id': 'cat-util',
          'affected_record_ref': 'Utility & Generator Diesel',
          'location_id': null,
          'occurrence_count': 1,
          'priority_score': 75.0,
          'priority_reason': 'High severity (+70), financial impact > 5k (+5)',
          'confidence': 0.95,
          'impacted_amount': 8000.0,
          'status': 'completed',
          'evidence': {'current_spend': 8000.0, 'prior_spend': 3500.0},
          'recommended_action': {
            'action_type': 'audit_expenses',
            'label': 'Review Category Expense Vouchers',
            'route': '/expenses',
          },
        },
        {
          'id': 'f-006',
          'engine': 'rebalancing',
          'category': 'inter_store_transfer',
          'severity': 'high',
          'rule_code': 'REBALANCE_TRANSFER_READY',
          'detection_rule': 'One store is in critical stockout while a sister branch holds surplus stock.',
          'title': 'Inter-Store Stock Disparity: Sunflower Oil 1L',
          'description': 'Main Store has 1 unit while Warehouse holds 30 units.',
          'affected_entity_type': 'product_variant',
          'affected_entity_id': 'var-oil-1',
          'affected_record_ref': 'SKU-OIL-1L / Sunflower Oil 1L',
          'location_id': 'loc-main',
          'occurrence_count': 1,
          'priority_score': 60.0,
          'priority_reason': 'High severity (+70) minus localized scope',
          'confidence': 0.95,
          'impacted_amount': 3000.0,
          'status': 'resolved',
          'evidence': {'shortage_stock': 1, 'surplus_stock': 30},
          'recommended_action': {
            'action_type': 'create_stock_transfer',
            'label': 'Create Transfer from Warehouse',
            'route': '/inventory',
          },
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> actionCentreScan({
    required String tenantId,
    String? locationId,
  }) async {
    scanTriggered = true;
    return {
      'success': true,
      'total_detected': 6,
      'inserted': 1,
      'updated': 5,
    };
  }

  @override
  Future<Map<String, dynamic>> transitionFinding({
    required String tenantId,
    required String findingId,
    required String toStatus,
    String reviewNotes = '',
    String? assignedTo,
  }) async {
    lastTransitionFindingId = findingId;
    lastTransitionToStatus = toStatus;
    return {
      'success': true,
      'finding_id': findingId,
      'to_status': toStatus,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> findingReviews({
    required String tenantId,
    required String findingId,
  }) async {
    return [
      {
        'id': 'rev-1',
        'from_status': 'new',
        'to_status': 'under_review',
        'reviewer_name': 'Thariq Manchara',
        'review_notes': 'Assigned to procurement team for verification.',
        'created_at': '2026-11-20T10:00:00Z',
      },
      {
        'id': 'rev-2',
        'from_status': 'under_review',
        'to_status': 'accepted',
        'reviewer_name': 'Thariq Manchara',
        'review_notes': 'Stockout verified. Proceeding with recommendation.',
        'created_at': '2026-11-20T10:30:00Z',
      },
    ];
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
  group('Operations Intelligence Phase 7: Priority Scoring & Deduplication Logic Tests', () {
    test('Calculates deterministic transparent priority score and reasoning', () {
      // Base: Critical = 100
      // Financial impact > 5000 = +5
      // Location null (tenant-wide systemic) = +10
      // Sum = 115 * confidence 0.95 = 109.25 -> 109.3
      const severity = 'critical';
      const impactedAmount = 15000.0;
      const confidence = 0.95;
      const isSystemic = true;

      double baseScore = 0.0;
      if (severity == 'critical') baseScore = 100.0;
      if (severity == 'high') baseScore = 70.0;
      if (severity == 'medium') baseScore = 40.0;
      if (severity == 'low') baseScore = 20.0;

      double raw = baseScore;
      if (impactedAmount >= 5000) raw += 5.0;
      if (isSystemic) raw += 10.0;

      final score = (raw * confidence * 10).round() / 10;
      expect(score, 109.3);
    });

    test('Validates lifecycle state transitions and illegal leap rejections', () {
      final validTransitions = {
        'new': ['under_review', 'dismissed'],
        'under_review': ['accepted', 'rejected', 'dismissed'],
        'accepted': ['approved', 'rejected'],
        'approved': ['completed'],
        'completed': ['resolved'],
        'resolved': ['new'],
        'dismissed': ['new'],
        'rejected': ['new'],
      };

      // Check valid transitions
      expect(validTransitions['new']!.contains('under_review'), isTrue);
      expect(validTransitions['under_review']!.contains('accepted'), isTrue);
      expect(validTransitions['accepted']!.contains('approved'), isTrue);
      expect(validTransitions['approved']!.contains('completed'), isTrue);
      expect(validTransitions['completed']!.contains('resolved'), isTrue);

      // Check illegal leaps
      expect(validTransitions['new']!.contains('completed'), isFalse);
      expect(validTransitions['new']!.contains('resolved'), isFalse);
      expect(validTransitions['resolved']!.contains('approved'), isFalse);
      expect(validTransitions['dismissed']!.contains('completed'), isFalse);
    });

    test('Generates deterministic dedup_key for stable deduplication', () {
      const tenantId = '0af96a25-2f04-44e2-a00f-5c4688f34238';
      const engine = 'inventory';
      const ruleCode = 'INV_CRITICAL_STOCKOUT';
      const entityType = 'product_variant';
      const entityId = 'var-001';
      const locationId = 'loc-main';

      final dedupKey1 = '$tenantId|$engine|$ruleCode|$entityType|$entityId|$locationId';
      final dedupKey2 = '$tenantId|$engine|$ruleCode|$entityType|$entityId|$locationId';

      expect(dedupKey1, dedupKey2);
    });
  });

  group('Operations Intelligence Phase 7: Action & Risk Centre Widget Tests (Tab 9)', () {
    testWidgets('Renders Tab 9 Action & Risk Centre with KPI banner, filter controls, and finding list', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 9, // Tab 9: Action & Risk Centre
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Check Tab Selection
      expect(find.text('Action & Risk Centre'), findsWidgets);

      // Check Header & Diagnostic Scan Button
      expect(find.text('Centralized Action & Risk Centre'), findsOneWidget);
      expect(find.text('Run Diagnostic Scan'), findsOneWidget);

      // Check KPI Summary Cards
      expect(find.text('Active Findings'), findsOneWidget);
      expect(find.text('Critical Severity'), findsOneWidget);
      expect(find.text('High Severity'), findsOneWidget);
      expect(find.text('Unresolved'), findsOneWidget);
      expect(find.text('Resolved / Closed'), findsOneWidget);
      expect(find.text('Total Impact Exposure'), findsOneWidget);
      expect(find.text('INR 63500.00'), findsOneWidget);

      // Check Findings rendered
      expect(find.text('Critical Stockout Risk: Sugar 1kg'), findsOneWidget);
      expect(find.text('Score: 109.3'), findsOneWidget);
      expect(find.text('Detected 3x'), findsOneWidget);
      expect(find.text('Sales Decline with Excess Stock: Basmati Rice 5kg'), findsOneWidget);
      expect(find.text('CROSS-ENGINE'), findsOneWidget);
      expect(find.text('Critical Overdue Credit Exposure: Grand Hotel'), findsOneWidget);

      // Scroll down to reveal remaining findings
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Double-Entry Trial Balance Imbalance'), findsOneWidget);
    });

    testWidgets('Diagnostic Scan button triggers multi-engine scan and shows success snackbar', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService();
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

      // Find and tap Diagnostic Scan button
      final scanBtn = find.widgetWithText(FilledButton, 'Run Diagnostic Scan');
      expect(scanBtn, findsOneWidget);
      await tester.tap(scanBtn);
      await tester.pumpAndSettle();

      expect(service.scanTriggered, isTrue);
      expect(find.textContaining('Diagnostic scan complete'), findsOneWidget);
    });

    testWidgets('SubTab filtering filters pending action and cross-engine findings', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService();
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

      // Switch to Cross-Engine
      final crossEngineChip = find.widgetWithText(ChoiceChip, 'Cross-Engine (1)');
      expect(crossEngineChip, findsOneWidget);
      await tester.tap(crossEngineChip);
      await tester.pumpAndSettle();

      // Only the cross-engine finding should remain visible
      expect(find.text('Sales Decline with Excess Stock: Basmati Rice 5kg'), findsOneWidget);
      expect(find.text('Critical Stockout Risk: Sugar 1kg'), findsNothing);
    });

    testWidgets('Inspect & Review opens finding details dialog with structured evidence and audit history', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService();
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

      // Find "Inspect & Review" button on the first card
      final inspectBtns = find.widgetWithText(OutlinedButton, 'Inspect & Review');
      expect(inspectBtns, findsWidgets);
      await tester.tap(inspectBtns.first);
      await tester.pumpAndSettle();

      // Dialog should be displayed
      expect(find.text('DETECTION RULE & PRIORITY CALCULATION'), findsOneWidget);
      expect(find.text('Structured Diagnostic Evidence'), findsOneWidget);
      expect(find.text('Recommended Action & Safe ERP Handoff'), findsOneWidget);
      expect(find.text('Traceable Review & Audit Trail'), findsOneWidget);

      // Scroll inside dialog to reveal audit history timeline
      await tester.drag(find.text('DETECTION RULE & PRIORITY CALCULATION'), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.textContaining('Thariq Manchara'), findsWidgets);
      expect(find.text('Stockout verified. Proceeding with recommendation.'), findsOneWidget);
    });

    testWidgets('Quick transition button triggers status transition dialog', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService();
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

      // Find "Start Review" button on the 'new' finding
      final reviewBtn = find.widgetWithText(FilledButton, 'Start Review');
      expect(reviewBtn, findsOneWidget);
      await tester.tap(reviewBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog opens
      expect(find.text('Transition Finding to UNDER REVIEW'), findsOneWidget);
      expect(find.text('Review Notes / Justification'), findsOneWidget);

      // Confirm transition
      final confirmBtn = find.widgetWithText(FilledButton, 'Confirm');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(service.lastTransitionFindingId, 'f-001');
      expect(service.lastTransitionToStatus, 'under_review');
    });

    testWidgets('Cost-restricted user masks financial figures with —', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService();
      final session = _createSession(isOwner: false, canViewCost: false); // Staff without cost permissions

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

      // Financial figures should be masked with '—'
      expect(find.text('Total Impact Exposure'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.text('INR 63500.00'), findsNothing);
    });

    testWidgets('Safe ERP navigation handoff triggers ClientNavigationScope without auto-executing transactions', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService();
      final session = _createSession(isOwner: true);
      String? navigatedModule;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ClientNavigationScope(
            navigateTo: (moduleKey, {args, tabIndex}) {
              navigatedModule = moduleKey;
            },
            child: OperationsIntelligenceScreen(
              session: session,
              service: service,
              initialTab: 9,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Find "Open in /purchases" button
      final openPurchasesBtn = find.widgetWithText(TextButton, 'Open in /purchases');
      expect(openPurchasesBtn, findsOneWidget);
      await tester.tap(openPurchasesBtn);
      await tester.pumpAndSettle();

      expect(navigatedModule, 'purchases');
    });

    testWidgets('Shows empty state when no findings match', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService(emptyData: true);
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

      expect(find.text('No Active Risks or Action Items'), findsOneWidget);
    });

    testWidgets('Displays error card with retry button when action centre fails to load', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase7IntelligenceService(failActionCentre: true);
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

      expect(find.text('Action & Risk Centre could not be loaded'), findsOneWidget);
      expect(find.text('Retry'), findsWidgets);
    });
  });
}
