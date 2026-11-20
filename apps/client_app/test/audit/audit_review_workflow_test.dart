import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_app/features/audit_intelligence/audit_detail_dialogs.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_screen.dart';
import 'package:client_app/features/audit_intelligence/audit_intelligence_service.dart';
import 'package:client_app/features/audit_intelligence/models/audit_review_models.dart';
import 'package:client_app/models/client_session.dart';

const _testSession = ClientSession(
  business: ClientBusiness(
    id: '11111111-1111-1111-1111-111111111111',
    membershipId: 'member-1',
    name: 'Acme Test Corp',
    slug: 'acme-test',
    businessType: 'retail',
    status: 'active',
  ),
  modules: [],
  roles: {'owner'},
  permissions: {
    'audit_center.view',
    'audit_center.review',
    'audit_center.resolve',
    'audit_center.configure',
  },
  currencyCode: 'INR',
  timezone: 'UTC',
  locale: 'en',
  canViewAllLocations: true,
);

class MockAuditReviewService extends AuditIntelligenceService {
  MockAuditReviewService() : super();

  int scanCalls = 0;
  int assignCalls = 0;
  int statusCalls = 0;
  int noteCalls = 0;

  @override
  Future<Map<String, dynamic>> workspace({
    required String tenantId,
    required String view,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String query = '',
    String severity = '',
    String status = '',
    String sort = 'date',
    bool descending = true,
    int offset = 0,
    String sourceType = '',
  }) async {
    return {
      'rows': [
        {
          'id': 'finding-101',
          'finding_id': 'finding-101',
          'title': 'Duplicate Supplier Bill Reference',
          'reference': 'BILL-9988',
          'severity': 'critical',
          'priority': 'critical',
          'status': 'open',
          'financial_exposure': 45000.0,
          'entity_type': 'purchase',
          'entity_id': 'purch-1',
          'assigned_name': 'Unassigned',
          'due_date': '2026-11-25',
          'date': '2026-11-19T10:00:00Z',
        },
      ],
      'total_rows': 1,
      'summary': {'open_attention': 1, 'high_risk': 1},
    };
  }

  @override
  Future<AuditReviewDashboardSummary> reviewDashboard({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    return const AuditReviewDashboardSummary(
      totalOpen: 12,
      criticalPriority: 4,
      highPriority: 3,
      mediumPriority: 3,
      lowPriority: 2,
      unassigned: 5,
      awaitingInfo: 2,
      underReview: 3,
      escalated: 1,
      overdue: 2,
      resolvedInPeriod: 8,
      dismissedInPeriod: 1,
      totalExposure: 275000.0,
      workload: [
        AuditReviewWorkload(
          userId: 'user-1',
          username: 'auditor_one',
          activeCount: 4,
          criticalCount: 2,
          overdueCount: 1,
        ),
      ],
    );
  }

  @override
  Future<List<AuditAssignableUser>> assignableUsers({
    required String tenantId,
  }) async {
    return const [
      AuditAssignableUser(
        userId: 'user-1',
        username: 'auditor_one',
        email: 'auditor1@example.com',
      ),
      AuditAssignableUser(
        userId: 'user-2',
        username: 'senior_accountant',
        email: 'accountant@example.com',
      ),
    ];
  }

  @override
  Future<AuditFindingReviewDetail> findingDetailV704({
    required String tenantId,
    required String findingId,
  }) async {
    return AuditFindingReviewDetail.fromJson({
      'finding': {
        'id': findingId,
        'title': 'Duplicate Supplier Bill Reference',
        'description':
            'Purchase invoice number BILL-9988 has been entered multiple times.',
        'entity_reference': 'BILL-9988',
        'entity_type': 'purchase',
        'entity_id': 'purch-1',
        'severity': 'critical',
        'priority': 'critical',
        'status': 'open',
        'financial_exposure': 45000.0,
        'risk_score': 92,
        'assigned_to': null,
        'due_date': '2026-11-25',
        'duplicate_group_id': 'BILL-9988',
        'is_duplicate': true,
        'rule_code': 'DUPLICATE_PURCHASE_REFERENCE',
        'rule_version': 1,
        'detected_at': '2026-11-19T10:00:00Z',
        'evidence': {
          'what_happened':
              'Supplier reference BILL-9988 was submitted for ₹45,000 on two separate purchase records.',
          'why_detected':
              'Cross-vendor supplier bill collision detected in purchase registry.',
          'rule_name': 'Duplicate Supplier Bill Reference Detection',
          'investigation_steps':
              '1. Compare physical invoices\n2. Verify with vendor\n3. Void redundant voucher',
          'is_confirmed': true,
          'duplicate_count': 2,
        },
      },
      'assignee': null,
      'notes': [
        {
          'id': 'note-1',
          'author_id': 'user-1',
          'author_name': 'auditor_one',
          'note_type': 'investigation',
          'note': 'Initial review completed. Awaiting physical bill scan.',
          'evidence_references': [
            {'reference': 'PO-9988-SCAN', 'type': 'document'},
          ],
          'created_at': '2026-11-19T11:30:00Z',
        },
      ],
      'history': [
        {
          'id': 'hist-1',
          'action': 'created',
          'actor_id': 'system',
          'actor_name': 'Audit Intelligence Engine',
          'before_state': null,
          'after_state': {'status': 'open', 'priority': 'critical'},
          'reason': 'Detected by automated risk scanner',
          'created_at': '2026-11-19T10:00:00Z',
        },
      ],
      'duplicates': [
        {
          'entity_reference': 'BILL-9988-ALT',
          'status': 'open',
          'severity': 'critical',
          'financial_exposure': 45000.0,
        },
      ],
      'transaction_story': [
        {
          'event_time': '2026-11-19T09:45:00Z',
          'action': 'purchase_created',
          'actor_name': 'purchaser',
          'entity_reference': 'BILL-9988',
        },
      ],
      'sensitive_values_visible': true,
    });
  }

  @override
  Future<Map<String, dynamic>> assignFinding({
    required String tenantId,
    required String findingId,
    required String? assignTo,
    String? priority,
    DateTime? dueDate,
    String? reason,
  }) async {
    assignCalls++;
    return {'assigned': true, 'assigned_to': assignTo};
  }

  @override
  Future<Map<String, dynamic>> updateFindingStatus({
    required String tenantId,
    required String findingId,
    required String status,
    required String note,
    String? resolutionNote,
  }) async {
    statusCalls++;
    return {'status': status, 'updated': true};
  }

  @override
  Future<Map<String, dynamic>> addFindingNote({
    required String tenantId,
    required String findingId,
    required String note,
    String noteType = 'investigation',
    List<Map<String, dynamic>> evidenceRefs = const [],
  }) async {
    noteCalls++;
    return {'id': 'new-note-1', 'note': note};
  }

  @override
  Future<Map<String, dynamic>> scanPeriodRisk({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    scanCalls++;
    return {
      'scanned_period': '2026-10-21 to 2026-11-19',
      'detected_count': 5,
    };
  }
}

void main() {
  group('Phase C & D: Audit Review Models Unit Tests', () {
    test('AuditReviewDashboardSummary parses metrics and reviewer workloads', () {
      final summary = AuditReviewDashboardSummary.fromJson({
        'metrics': {
          'total_open': 15,
          'critical_priority': 5,
          'high_priority': 4,
          'medium_priority': 3,
          'low_priority': 3,
          'unassigned': 6,
          'awaiting_info': 2,
          'under_review': 4,
          'escalated': 1,
          'overdue': 3,
          'resolved_in_period': 10,
          'dismissed_in_period': 2,
          'total_exposure': 350000.5,
        },
        'workload_by_reviewer': [
          {
            'user_id': 'u1',
            'username': 'reviewer1',
            'active_count': 5,
            'critical_count': 2,
            'overdue_count': 1,
          },
        ],
      });

      expect(summary.totalOpen, 15);
      expect(summary.criticalPriority, 5);
      expect(summary.unassigned, 6);
      expect(summary.overdue, 3);
      expect(summary.totalExposure, 350000.5);
      expect(summary.workload.length, 1);
      expect(summary.workload.first.username, 'reviewer1');
      expect(summary.workload.first.criticalCount, 2);
    });

    test('AuditFindingReviewDetail parses structured risk intelligence correctly', () {
      final detail = AuditFindingReviewDetail.fromJson({
        'finding': {
          'id': 'f-1',
          'title': 'Unbalanced Journal Detected',
          'description': 'Debit and credit lines do not balance',
          'entity_reference': 'JV-2026-001',
          'entity_type': 'journal_entry',
          'entity_id': 'jv-1',
          'severity': 'critical',
          'priority': 'critical',
          'status': 'open',
          'financial_exposure': 10000.0,
          'risk_score': 99,
          'rule_code': 'UNBALANCED_JOURNAL_ENTRY',
          'rule_version': 1,
          'duplicate_group_id': 'grp-1',
          'is_duplicate': true,
          'evidence': {
            'what_happened': 'Total debit is ₹20,000 while total credit is ₹10,000.',
            'why_detected': 'Out of balance journal entry detected by ledger verification.',
            'rule_name': 'Unbalanced Journal Integrity Check',
            'investigation_steps': 'Check original transaction lines.',
            'is_confirmed': true,
          },
        },
        'assignee': {'username': 'auditor_lead'},
        'notes': [
          {
            'id': 'n-1',
            'author_id': 'u-1',
            'author_name': 'auditor_lead',
            'note_type': 'internal_note',
            'note': 'Needs correction voucher.',
            'created_at': '2026-11-19T10:00:00Z',
          },
        ],
        'history': [
          {
            'id': 'h-1',
            'action': 'assigned',
            'actor_id': 'u-1',
            'actor_name': 'auditor_lead',
            'before_state': {'assigned_to': null},
            'after_state': {'assigned_to': 'u-1'},
            'reason': 'Self-assigned for investigation',
            'created_at': '2026-11-19T10:05:00Z',
          },
        ],
        'duplicates': [],
        'transaction_story': [],
      });

      expect(detail.id, 'f-1');
      expect(detail.title, 'Unbalanced Journal Detected');
      expect(detail.whatHappened, 'Total debit is ₹20,000 while total credit is ₹10,000.');
      expect(detail.whyDetected, 'Out of balance journal entry detected by ledger verification.');
      expect(detail.isConfirmed, true);
      expect(detail.financialExposure, 10000.0);
      expect(detail.isDuplicate, true);
      expect(detail.notes.length, 1);
      expect(detail.notes.first.noteType, 'internal_note');
      expect(detail.history.length, 1);
      expect(detail.history.first.action, 'assigned');
    });

    test('AuditAssignableUser parses team member info', () {
      final user = AuditAssignableUser.fromJson({
        'user_id': 'u-123',
        'username': 'john_doe',
        'email': 'john@example.com',
      });
      expect(user.userId, 'u-123');
      expect(user.username, 'john_doe');
      expect(user.email, 'john@example.com');
    });
  });

  group('Phase C & D: Audit Review UI Widget Tests', () {
    testWidgets('Dashboard metrics bar renders summary stats in Findings view', (
      tester,
    ) async {
      final service = MockAuditReviewService();
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

      // Verify dashboard metric headers exist
      expect(find.text('Open findings'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Critical / High'), findsOneWidget);
      expect(find.text('7'), findsOneWidget); // 4 critical + 3 high
      expect(find.text('Unassigned'), findsWidgets);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('2'), findsNWidgets(2)); // overdue (2) and awaiting info (2)
      expect(find.text('Resolved in period'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);

      // Verify Run risk scan button exists
      expect(find.text('Run risk scan'), findsOneWidget);
    });

    testWidgets('Run risk scan button triggers service scanPeriodRisk', (
      tester,
    ) async {
      final service = MockAuditReviewService();
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

      await tester.tap(find.text('Run risk scan'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(service.scanCalls, 1);
    });

    testWidgets('Finding dialog opens with 4 tabs and displays risk explanation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final service = MockAuditReviewService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showAuditFindingDialog(
                  context: ctx,
                  service: service,
                  session: _testSession,
                  findingId: 'finding-101',
                  from: DateTime(2026, 11, 1),
                  to: DateTime(2026, 11, 20),
                ),
                child: const Text('Open Finding Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Finding Dialog'));
      await tester.pumpAndSettle();

      // Check header details
      expect(find.text('Duplicate Supplier Bill Reference'), findsOneWidget);
      expect(find.textContaining('BILL-9988'), findsWidgets);

      // Check Tabs
      expect(find.text('Risk intelligence'), findsOneWidget);
      expect(find.text('Notes (1)'), findsOneWidget);
      expect(find.text('Evidence & story'), findsOneWidget);
      expect(find.text('Audit trail (1)'), findsOneWidget);

      // Check structured risk explanation
      expect(
        find.text(
          'Supplier reference BILL-9988 was submitted for ₹45,000 on two separate purchase records.',
        ),
        findsOneWidget,
      );
      expect(find.text('What Happened'), findsOneWidget);
      expect(find.text('Detection Rule & Logic'), findsOneWidget);
      expect(find.text('Confirmed Discrepancy'), findsOneWidget);
      expect(find.text('Recommended Investigation Steps'), findsOneWidget);

      // Check duplicate pattern alert banner
      expect(find.text('Duplicate / Related Pattern Alert'), findsOneWidget);

      // Switch to Notes tab
      await tester.tap(find.text('Notes (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Initial review completed. Awaiting physical bill scan.'), findsOneWidget);
      expect(find.text('Post note'), findsOneWidget);

      // Switch to Audit trail tab
      await tester.tap(find.text('Audit trail (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Audit Intelligence Engine'), findsOneWidget);
      expect(find.text('Detected by automated risk scanner'), findsOneWidget);
    });
  });
}
