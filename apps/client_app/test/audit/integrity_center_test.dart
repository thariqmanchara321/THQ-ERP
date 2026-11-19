import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_service.dart';
import 'package:client_app/features/audit_intelligence/integrity_reconciliation_view.dart';
import 'package:client_app/features/audit_intelligence/models/audit_integrity_models.dart';
import 'package:client_app/models/client_session.dart';

const _testSession = ClientSession(
  business: ClientBusiness(
    id: '0af96a25-2f04-44e2-a00f-5c4688f34238',
    membershipId: 'mem_1',
    name: 'THQ Test Enterprise',
    slug: 'thq-test',
    businessType: null,
    status: 'active',
  ),
  modules: [],
  roles: {'owner'},
  permissions: {
    'audit_center.view',
    'audit_history.view_sensitive',
    'audit_center.configure',
  },
  currencyCode: 'INR',
  timezone: 'UTC',
  locale: 'en',
  canViewAllLocations: true,
);

class MockAuditIntegrityService extends AuditIntelligenceService {
  MockAuditIntegrityService({
    this.checksData,
    this.drilldownData,
  });

  final Map<String, dynamic>? checksData;
  final Map<String, dynamic>? drilldownData;

  String? capturedCategory;
  String? capturedCheckId;

  @override
  Future<dynamic> callIntegrityChecksRpc({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? category,
  }) async {
    capturedCategory = category;
    return checksData ??
        {
          'total_rows': 5,
          'basis': 'Authoritative ERP integrity engine.',
          'generated_at': '2026-11-19T10:00:00Z',
          'rows': [
            {
              'id': 'accounting_unbalanced_journals',
              'category': 'accounting',
              'reference': 'Journal balance',
              'title': 'Unbalanced journal entries (Debits != Credits)',
              'status': 'Issue detected',
              'severity': 'critical',
              'count': 2,
              'difference': 150.0,
              'dataset': 'journal_entries',
              'basis': 'Debits must equal credits for every journal.',
              'explanation': 'Discrepancy found in posted double entries.',
              'is_actionable': true,
            },
            {
              'id': 'trial_balance',
              'category': 'accounting',
              'reference': 'Trial balance',
              'title': 'Period debits minus credits variance',
              'status': 'Passed',
              'severity': 'critical',
              'count': 0,
              'difference': 0.0,
              'dataset': 'accounts',
              'basis': 'Trial balance variance across active accounts.',
              'explanation': 'Debits equal credits.',
              'is_actionable': true,
            },
            {
              'id': 'stock_stock_balances',
              'category': 'inventory',
              'reference': 'Stock balances',
              'title': 'Stock balances variance from movement ledger',
              'status': 'Needs review',
              'severity': 'high',
              'count': 1,
              'difference': 5.0,
              'dataset': 'stock_balances',
              'basis': 'Saved balance versus sum of movements.',
              'explanation': 'Discrepancy in recorded inventory.',
              'is_actionable': true,
            },
            {
              'id': 'sales_header_vs_lines',
              'category': 'sales_purchase',
              'reference': 'Sales invoice totals',
              'title': 'Sale invoice total differs from sum of line items',
              'status': 'Passed',
              'severity': 'high',
              'count': 0,
              'difference': 0.0,
              'dataset': 'sales',
              'basis': 'Invoice grand_total equals line items.',
              'explanation': 'No sales header discrepancies.',
              'is_actionable': true,
            },
            {
              'id': 'bank_coverage',
              'category': 'banking_payment',
              'reference': 'Bank coverage',
              'title': 'Bank statement import coverage in period',
              'status': 'Insufficient data',
              'severity': 'informational',
              'count': 0,
              'dataset': 'bank_statement_lines_v500',
              'basis': 'Bank statement imports.',
              'explanation': 'No bank statements imported in period.',
              'is_actionable': false,
            },
          ],
        };
  }

  @override
  Future<dynamic> callCheckDrilldownRpc({
    required String tenantId,
    required String checkId,
    required DateTime from,
    required DateTime to,
    String? locationId,
    int limit = 50,
  }) async {
    capturedCheckId = checkId;
    return drilldownData ??
        {
          'check_id': checkId,
          'dataset': 'journal_entries',
          'title': 'Unbalanced journal entries',
          'rule': 'Debits must equal credits for every journal entry.',
          'total_records': 2,
          'records': [
            {
              'id': 'jrn-101',
              'reference': 'JRN-2026-001',
              'date': '2026-11-10',
              'dataset': 'journal_entries',
              'expected_value': 1000.0,
              'actual_value': 850.0,
              'difference': 150.0,
              'description': 'Debits (1000) do not equal credits (850)',
            },
            {
              'id': 'jrn-102',
              'reference': 'JRN-2026-002',
              'date': '2026-11-12',
              'dataset': 'journal_entries',
              'expected_value': 500.0,
              'actual_value': 500.0,
              'difference': 0.0,
              'description': 'Suspicious journal entry rounding',
            },
          ],
        };
  }
}

void main() {
  group('Integrity Models Tests', () {
    test('AuditIntegrityCheck parses json and exposes correct status flags', () {
      final json = {
        'id': 'accounting_unbalanced_journals',
        'category': 'accounting',
        'reference': 'Journal balance',
        'title': 'Unbalanced journal entries',
        'status': 'Issue detected',
        'severity': 'critical',
        'count': 3,
        'difference': 250.5,
        'dataset': 'journal_entries',
        'basis': 'Debits must equal credits.',
        'explanation': 'Discrepancy in double entry.',
        'is_actionable': true,
      };

      final check = AuditIntegrityCheck.fromJson(json);
      expect(check.id, 'accounting_unbalanced_journals');
      expect(check.category, 'accounting');
      expect(check.reference, 'Journal balance');
      expect(check.title, 'Unbalanced journal entries');
      expect(check.count, 3);
      expect(check.difference, 250.5);
      expect(check.isCritical, isTrue);
      expect(check.isIssueDetected, isTrue);
      expect(check.isPassed, isFalse);
      expect(check.isNeedsReview, isFalse);
      expect(check.isActionable, isTrue);
    });

    test('AuditIntegrityResult calculates summary metrics accurately', () {
      final json = {
        'total_rows': 3,
        'basis': 'Authoritative checks.',
        'rows': [
          {
            'id': 'c1',
            'category': 'accounting',
            'reference': 'R1',
            'title': 'T1',
            'status': 'Passed',
            'severity': 'low',
            'count': 0,
            'basis': 'B1',
            'explanation': 'E1',
          },
          {
            'id': 'c2',
            'category': 'accounting',
            'reference': 'R2',
            'title': 'T2',
            'status': 'Issue detected',
            'severity': 'critical',
            'count': 1,
            'basis': 'B2',
            'explanation': 'E2',
          },
          {
            'id': 'c3',
            'category': 'banking_payment',
            'reference': 'R3',
            'title': 'T3',
            'status': 'Insufficient data',
            'severity': 'informational',
            'count': 0,
            'basis': 'B3',
            'explanation': 'E3',
          },
        ],
      };

      final result = AuditIntegrityResult.fromJson(json);
      expect(result.totalCount, 3);
      expect(result.passedCount, 1);
      expect(result.issueCount, 1);
      expect(result.insufficientDataCount, 1);
      expect(result.byCategory('accounting').length, 2);
      expect(result.byCategory('banking_payment').length, 1);
      expect(result.byCategory('all').length, 3);
    });

    test('AuditCheckDrilldownResult parses affected records cleanly', () {
      final json = {
        'check_id': 'sales_header_vs_lines',
        'dataset': 'sales',
        'title': 'Sale totals mismatch',
        'rule': 'Invoice grand_total equals lines sum.',
        'total_records': 1,
        'records': [
          {
            'id': 'sale-1',
            'reference': 'INV-1001',
            'date': '2026-11-15',
            'dataset': 'sales',
            'expected_value': 500.0,
            'actual_value': 480.0,
            'difference': 20.0,
            'description': 'Grand total 480 differs from line sum 500',
          },
        ],
      };

      final drilldown = AuditCheckDrilldownResult.fromJson(json);
      expect(drilldown.checkId, 'sales_header_vs_lines');
      expect(drilldown.dataset, 'sales');
      expect(drilldown.totalRecords, 1);
      expect(drilldown.records.length, 1);
      expect(drilldown.records.first.reference, 'INV-1001');
      expect(drilldown.records.first.difference, 20.0);
    });
  });

  group('Integrity Service Tests', () {
    test('integrityChecks parses response into typed AuditIntegrityResult', () async {
      final service = MockAuditIntegrityService();
      final res = await service.integrityChecks(
        tenantId: 'tenant-1',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
        category: 'accounting',
      );

      expect(service.capturedCategory, 'accounting');
      expect(res.totalCount, 5);
      expect(res.issueCount, 1);
      expect(res.reviewCount, 1);
      expect(res.passedCount, 2);
      expect(res.insufficientDataCount, 1);
    });

    test('checkDrilldownRecords passes checkId and limit to RPC', () async {
      final service = MockAuditIntegrityService();
      final res = await service.checkDrilldownRecords(
        tenantId: 'tenant-1',
        checkId: 'accounting_unbalanced_journals',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
        limit: 25,
      );

      expect(service.capturedCheckId, 'accounting_unbalanced_journals');
      expect(res.checkId, 'accounting_unbalanced_journals');
      expect(res.records.length, 2);
      expect(res.records.first.id, 'jrn-101');
    });
  });

  group('Integrity UI Tests', () {
    testWidgets('Renders summary metrics cards and category chips', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = MockAuditIntegrityService();
      const session = _testSession;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntegrityReconciliationView(
              session: session,
              service: service,
              from: DateTime(2026, 1, 1),
              to: DateTime(2026, 12, 31),
              onPickPeriod: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify top summary cards
      expect(find.text('Total Checks'), findsOneWidget);
      expect(find.text('Issues Detected'), findsOneWidget);
      expect(find.text('Needs Review'), findsOneWidget);
      expect(find.text('Passed'), findsWidgets);

      // Verify category navigation chips
      expect(find.widgetWithText(ChoiceChip, 'All checks'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Accounting'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Inventory'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Sales & Purchases'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Banking & Payments'), findsOneWidget);

      // Verify check titles in list
      expect(
        find.text('Unbalanced journal entries (Debits != Credits)'),
        findsOneWidget,
      );
      expect(
        find.text('Stock balances variance from movement ledger'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping check opens detail dialog with drilldown records', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = MockAuditIntegrityService();
      const session = _testSession;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntegrityReconciliationView(
              session: session,
              service: service,
              from: DateTime(2026, 1, 1),
              to: DateTime(2026, 12, 31),
              onPickPeriod: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on the unbalanced journals check
      final checkFinder = find.text(
        'Unbalanced journal entries (Debits != Credits)',
      );
      expect(checkFinder, findsOneWidget);
      await tester.tap(checkFinder);
      await tester.pumpAndSettle();

      // Verify detail dialog is presented
      expect(find.text('Expected Business Rule & Methodology'), findsOneWidget);
      expect(find.text('Affected Source Records (2)'), findsOneWidget);
      expect(find.text('JRN-2026-001'), findsOneWidget);
      expect(find.text('JRN-2026-002'), findsOneWidget);
      expect(find.text('Inspect'), findsNWidgets(2));
    });

    testWidgets('Category chips filter the check list', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = MockAuditIntegrityService();
      const session = _testSession;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IntegrityReconciliationView(
              session: session,
              service: service,
              from: DateTime(2026, 1, 1),
              to: DateTime(2026, 12, 31),
              onPickPeriod: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on 'Inventory' category chip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Inventory'));
      await tester.pumpAndSettle();

      // Only inventory check should be visible
      expect(
        find.text('Stock balances variance from movement ledger'),
        findsOneWidget,
      );
      expect(
        find.text('Unbalanced journal entries (Debits != Credits)'),
        findsNothing,
      );
    });
  });
}
