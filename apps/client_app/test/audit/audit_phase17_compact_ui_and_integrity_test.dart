import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_screen.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_service.dart';
import 'package:client_app/features/audit_intelligence/integrity_reconciliation_view.dart';
import 'package:client_app/features/audit_intelligence/models/audit_integrity_models.dart';
import 'package:client_app/models/client_session.dart';
import 'package:thq_ui/thq_ui.dart';

const _testSession = ClientSession(
  business: ClientBusiness(
    id: 'a659b6de-885d-44ed-9fa7-93eefa7d47d2',
    membershipId: 'mem-101',
    name: 'THQ Main Enterprise',
    slug: 'thq-main',
    businessType: 'retail',
    status: 'active',
  ),
  modules: [],
  roles: {'admin'},
  permissions: {
    'audit_center.view',
    'audit_center.configure',
    'audit_history.view_sensitive',
  },
  currencyCode: 'INR',
  timezone: 'UTC',
  locale: 'en',
  canViewAllLocations: true,
);

class MockPhase17AuditService extends AuditIntelligenceService {
  MockPhase17AuditService();

  @override
  Future<Map<String, dynamic>> workspace({
    required String tenantId,
    required String view,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? query,
    String? severity,
    String? status,
    String? sort,
    bool descending = true,
    int offset = 0,
    int limit = 50,
    String? sourceType,
  }) async {
    return {
      'rows': [
        {
          'id': 'f-001',
          'finding_id': 'f-001',
          'date': '2026-11-20T10:00:00Z',
          'reference': 'INV-1001',
          'title': 'Negative stock balance on SKU-99',
          'description': 'Quantity fell below zero without recorded receipt.',
          'severity': 'high_risk',
          'status': 'open',
          'priority': 'high',
          'financial_exposure': 1500.0,
          'risk_score': 85,
          'entity_type': 'sales',
          'entity_id': 's-100',
          'actor': 'Cashier 1',
          'location': 'Main Branch',
          'device': 'POS-01',
          'rule': 'INV_NEG_STOCK',
        }
      ],
      'total_rows': 1,
      'summary': {
        'high_risk': 1,
        'needs_review': 0,
        'open_attention': 1,
        'total_findings': 1,
      },
    };
  }

  @override
  Future<AuditIntegrityResult> integrityChecks({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? category,
  }) async {
    return AuditIntegrityResult.fromJson({
      'total_rows': 4,
      'generated_at': '2026-11-26T12:00:00Z',
      'basis': 'Authoritative ERP integrity engine.',
      'rows': [
        {
          'id': 'accounting_unbalanced_journals',
          'category': 'accounting',
          'reference': 'Journal balance',
          'title': 'Unbalanced journal entries (Debits != Credits)',
          'count': 0,
          'status': 'Passed',
          'severity': 'critical',
          'dataset': 'journal_entries',
          'is_actionable': true,
          'basis': 'Debits must equal credits.',
          'explanation': 'Every posted entry balances.',
        },
        {
          'id': 'trial_balance',
          'category': 'accounting',
          'reference': 'Trial balance',
          'title': 'Period debits minus credits variance',
          'amount': 0.0,
          'difference': 0.0,
          'count': 0,
          'status': 'Passed',
          'severity': 'critical',
          'dataset': 'accounts',
          'is_actionable': true,
          'basis': 'Trial balance variance across active accounts.',
          'explanation': 'Balanced.',
        },
        {
          'id': 'negative_cash',
          'category': 'accounting',
          'reference': 'Cash on hand',
          'title': 'Cash closing balance negative review',
          'amount': -66669.52,
          'count': 1,
          'status': 'Needs review',
          'severity': 'medium',
          'dataset': 'accounts',
          'is_actionable': true,
          'basis': 'Effective posted cash ledger.',
          'explanation': 'Negative cash closing balance indicates missing float.',
        },
        {
          'id': 'ops_cross_tenant_references',
          'category': 'operational',
          'reference': 'Tenant boundary',
          'title': 'Foreign key references crossing tenant boundary',
          'count': 0,
          'status': 'Passed',
          'severity': 'critical',
          'dataset': 'tenants',
          'is_actionable': true,
          'basis': 'Verified 286 foreign keys.',
          'explanation': 'No leaks.',
        },
      ],
    });
  }
}

void main() {
  group('Phase 17: Audit Center UI & Integrity Evaluation Tests', () {
    testWidgets('Tapping date button opens ThqCompactDateRangeDialog', (tester) async {
      final service = MockPhase17AuditService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditIntelligenceScreen(
              session: _testSession,
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the date range button in header
      final dateBtn = find.byIcon(Icons.date_range).first;
      expect(dateBtn, findsOneWidget);

      await tester.tap(dateBtn);
      await tester.pumpAndSettle();

      // Verify compact date range dialog is displayed
      expect(find.byType(ThqCompactDateRangeDialog), findsOneWidget);
      expect(find.text('Select Audit Period'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);

      // Tapping Today selects the preset
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      // Apply
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.byType(ThqCompactDateRangeDialog), findsNothing);
    });

    testWidgets('Integrity & reconciliation view renders and filters correctly', (tester) async {
      final service = MockPhase17AuditService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuditIntelligenceScreen(
              session: _testSession,
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Integrity & reconciliation section
      final sectionDropdown = find.byKey(const ValueKey('Audit section-findings'));
      await tester.tap(sectionDropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Integrity & reconciliation').last);
      await tester.pumpAndSettle();

      // Verify IntegrityReconciliationView is visible
      expect(find.byType(IntegrityReconciliationView), findsOneWidget);

      // Verify summary cards
      expect(find.text('Total Checks'), findsOneWidget);
      expect(find.text('Passed'), findsWidgets);
      expect(find.text('Needs Review'), findsWidgets);

      // Verify check titles
      expect(find.text('Cash closing balance negative review'), findsOneWidget);
      expect(find.text('Period debits minus credits variance'), findsOneWidget);

      // Test status filter
      final statusDropdown = find.text('All statuses');
      await tester.tap(statusDropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Needs review').last);
      await tester.pumpAndSettle();

      // Only negative cash should remain
      expect(find.text('Cash closing balance negative review'), findsOneWidget);
      expect(find.text('Period debits minus credits variance'), findsNothing);
    });

    testWidgets('Responsive layouts across all specified viewports render without overflow', (tester) async {
      final service = MockPhase17AuditService();
      final viewports = [
        const Size(1920, 1080), // Desktop Full HD
        const Size(1366, 768),  // Standard Laptop
        const Size(1024, 768),  // Tablet Landscape
        const Size(768, 1024),  // Tablet Portrait
        const Size(400, 800),   // Mobile Medium
        const Size(360, 800),   // Mobile Compact
      ];

      for (final size in viewports) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AuditIntelligenceScreen(
                session: _testSession,
                service: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify zero RenderFlex overflows
        expect(tester.takeException(), isNull, reason: 'Layout overflow at $size');
      }
    });
  });
}
