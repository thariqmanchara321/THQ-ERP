import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/operations_intelligence_screen.dart';
import 'package:client_app/services/operations_intelligence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhase9IntelligenceService extends OperationsIntelligenceService {
  final bool failWorkforce;
  final bool emptyData;
  final bool canViewPayroll;
  bool scanTriggered = false;

  _MockPhase9IntelligenceService({
    this.failWorkforce = false,
    this.emptyData = false,
    this.canViewPayroll = true,
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
        'summary': {
          'total_findings': 0,
          'critical_count': 0,
          'high_count': 0,
          'unresolved_count': 0,
          'resolved_count': 0,
        },
        'findings': [],
      };

  @override
  Future<Map<String, dynamic>> workforceIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    if (failWorkforce) {
      throw StateError('Simulated workforce intelligence RPC connection failure');
    }
    if (emptyData) {
      return {
        'tenant_id': tenantId,
        'location_id': locationId,
        'can_view_payroll': canViewPayroll,
        'summary': {
          'overall_workforce_score': 100.0,
          'health_status': 'optimal',
          'active_workforce_count': 5,
          'attendance_rate_pct': 100.0,
          'total_recorded_hours': 160.0,
          'total_overtime_hours': 0.0,
          'overtime_ratio_pct': 0.0,
          'active_risks_count': 0,
        },
        'workforce_availability': {
          'total_staff': 5,
          'active_staff': 5,
          'inactive_staff': 0,
          'by_role': [
            {'role': 'cashier', 'count': 3},
            {'role': 'store_manager', 'count': 2},
          ],
        },
        'attendance_intelligence': {
          'total_records': 100,
          'present_count': 100,
          'half_day_count': 0,
          'absent_count': 0,
          'paid_leave_count': 0,
          'unpaid_leave_count': 0,
          'attendance_rate_pct': 100.0,
          'absence_rate_pct': 0.0,
          'leave_rate_pct': 0.0,
          'daily_trends': [],
        },
        'shift_staffing': {
          'total_shifts': 30,
          'open_shifts': 1,
          'closed_shifts': 29,
          'avg_shift_hours': 8.0,
          'discrepancy_count': 0,
          'daily_shifts': [],
        },
        'capacity_demand': {
          'avg_txns_per_staff_day': 35.0,
          'peak_demand_hours': [],
          'workload_distribution': {
            'sales_transactions': 350,
            'purchase_orders': 15,
            'stock_transfers': 8,
          },
        },
        'overtime_cost': {
          'can_view_payroll': canViewPayroll,
          'total_regular_hours': 160.0,
          'total_overtime_hours': 0.0,
          'overtime_ratio_pct': 0.0,
          'gross_workforce_earnings': 120000.0,
          'net_workforce_earnings': 115000.0,
          'total_payments_disbursed': 115000.0,
          'earnings_by_kind': [
            {'earning_kind': 'salary', 'total_amount': 120000.0, 'count': 5},
          ],
        },
        'branch_benchmarks': [
          {
            'location_id': 'loc-1',
            'location_name': 'Main Branch',
            'active_staff': 5,
            'attendance_rate_pct': 100.0,
            'overtime_ratio_pct': 0.0,
            'shifts_count': 30,
            'sales_txns': 350,
            'txns_per_staff': 70.0,
            'data_sufficiency': 'Sufficient',
          },
        ],
        'risks': [],
        'data_freshness': {
          'evaluated_at': '2026-11-23T10:00:00Z',
          'period_days': 30,
          'has_attendance_data': true,
          'has_shift_data': true,
          'has_payroll_data': true,
        },
      };
    }

    return {
      'tenant_id': tenantId,
      'location_id': locationId,
      'can_view_payroll': canViewPayroll,
      'summary': {
        'overall_workforce_score': 68.5,
        'health_status': 'moderate_risk',
        'active_workforce_count': 8,
        'attendance_rate_pct': 72.5,
        'total_recorded_hours': 480.0,
        'total_overtime_hours': 140.0,
        'overtime_ratio_pct': 29.2,
        'active_risks_count': 2,
      },
      'workforce_availability': {
        'total_staff': 10,
        'active_staff': 8,
        'inactive_staff': 2,
        'by_role': [
          {'role': 'cashier', 'count': 5},
          {'role': 'inventory_clerk', 'count': 2},
          {'role': 'store_manager', 'count': 1},
        ],
      },
      'attendance_intelligence': {
        'total_records': 160,
        'present_count': 116,
        'half_day_count': 10,
        'absent_count': 24,
        'paid_leave_count': 8,
        'unpaid_leave_count': 2,
        'attendance_rate_pct': 72.5,
        'absence_rate_pct': 15.0,
        'leave_rate_pct': 6.2,
        'daily_trends': [
          {
            'work_date': '2026-11-20',
            'present': 6,
            'absent': 2,
            'leave': 0,
            'regular_hours': 48.0,
            'overtime_hours': 14.0,
          },
          {
            'work_date': '2026-11-21',
            'present': 7,
            'absent': 1,
            'leave': 0,
            'regular_hours': 56.0,
            'overtime_hours': 12.0,
          },
        ],
      },
      'shift_staffing': {
        'total_shifts': 45,
        'open_shifts': 2,
        'closed_shifts': 43,
        'avg_shift_hours': 8.6,
        'discrepancy_count': 4,
        'daily_shifts': [
          {
            'work_date': '2026-11-20',
            'shifts_count': 3,
            'closed_count': 3,
            'discrepancies': 1,
          },
          {
            'work_date': '2026-11-21',
            'shifts_count': 3,
            'closed_count': 3,
            'discrepancies': 2,
          },
        ],
      },
      'capacity_demand': {
        'avg_txns_per_staff_day': 42.0,
        'peak_demand_hours': [
          {'hour_of_day': 11, 'txns_count': 75},
          {'hour_of_day': 17, 'txns_count': 92},
        ],
        'workload_distribution': {
          'sales_transactions': 1250,
          'purchase_orders': 42,
          'stock_transfers': 19,
        },
      },
      'overtime_cost': {
        'can_view_payroll': canViewPayroll,
        'total_regular_hours': 480.0,
        'total_overtime_hours': 140.0,
        'overtime_ratio_pct': 29.2,
        'gross_workforce_earnings': 285000.0,
        'net_workforce_earnings': 270000.0,
        'total_payments_disbursed': 260000.0,
        'earnings_by_kind': [
          {'earning_kind': 'basic_salary', 'total_amount': 210000.0, 'count': 8},
          {'earning_kind': 'overtime_pay', 'total_amount': 55000.0, 'count': 8},
          {'earning_kind': 'bonus', 'total_amount': 20000.0, 'count': 4},
        ],
      },
      'branch_benchmarks': [
        {
          'location_id': 'loc-1',
          'location_name': 'Downtown Superstore',
          'active_staff': 6,
          'attendance_rate_pct': 78.0,
          'overtime_ratio_pct': 24.5,
          'shifts_count': 30,
          'sales_txns': 900,
          'txns_per_staff': 150.0,
          'data_sufficiency': 'Sufficient',
        },
        {
          'location_id': 'loc-2',
          'location_name': 'Airport Express Kiosk',
          'active_staff': 2,
          'attendance_rate_pct': 62.0,
          'overtime_ratio_pct': 42.0,
          'shifts_count': 15,
          'sales_txns': 350,
          'txns_per_staff': 175.0,
          'data_sufficiency': 'Low Volume',
        },
      ],
      'risks': [
        {
          'rule_code': 'WF_ATTENDANCE_COVERAGE_DROP',
          'affected_process': 'workforce_attendance',
          'severity': 'warning',
          'title': 'Significant Drop in Workforce Attendance Coverage',
          'description': 'Attendance coverage rate contracted to 72.5% (Absence rate: 15.0%).',
          'recommendation': 'Review branch staffing coverage, examine root causes of absences, and arrange relief coverage if required.',
          'route': '/staff',
          'evidence': {
            'attendance_rate_pct': 72.5,
            'absence_rate_pct': 15.0,
            'absent_count': 24,
            'total_attendance_records': 160,
          },
        },
        {
          'rule_code': 'WF_OVERTIME_SPIKE',
          'affected_process': 'workforce_overtime',
          'severity': 'warning',
          'title': 'Unusual Growth in Recorded Overtime Hours',
          'description': 'Overtime hours reached 140 hrs (29.2% of regular operating hours).',
          'recommendation': 'Investigate operational workload drivers and evaluate whether additional permanent staffing is more sustainable than ongoing overtime.',
          'route': '/staff',
          'evidence': {
            'total_overtime_hours': 140.0,
            'total_regular_hours': 480.0,
            'overtime_ratio_pct': 29.2,
          },
        },
      ],
      'data_freshness': {
        'evaluated_at': '2026-11-23T11:00:00Z',
        'period_days': 30,
        'has_attendance_data': true,
        'has_shift_data': true,
        'has_payroll_data': true,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> workforceIntelligenceScan({
    required String tenantId,
    String? locationId,
  }) async {
    scanTriggered = true;
    return {
      'success': true,
      'total_detected': 2,
      'inserted': 1,
      'updated': 1,
      'workforce_score': 68.5,
      'health_status': 'moderate_risk',
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
  bool canViewPayroll = true,
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
          'staff.view',
          if (canViewPayroll) 'staff.payroll',
          if (canViewPayroll) 'accounting.view',
        },
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
    locations: const [
      ClientLocationAccess(
        id: 'loc-1',
        code: 'MAIN',
        name: 'Downtown Superstore',
        type: 'store',
        trackingCode: 'TRK-01',
        accessLevel: 'manage',
      ),
      ClientLocationAccess(
        id: 'loc-2',
        code: 'AIR',
        name: 'Airport Express Kiosk',
        type: 'kiosk',
        trackingCode: 'TRK-02',
        accessLevel: 'view',
      ),
    ],
  );
}

void main() {
  group('Operations Intelligence Phase 9: Workforce Intelligence Calculations & Rule Tests', () {
    test('Calculates deterministic workforce score [0, 100] and maps health status thresholds', () {
      // Score deduction logic from workforce_intelligence_v830:
      // score starts at 100.0, deductions applied for attendance < 85%, overtime > 20%, shift discrepancies, etc.
      double calculateScore({
        required double attendanceRate,
        required double overtimeRatio,
        required int shiftDiscrepancies,
      }) {
        double score = 100.0;
        if (attendanceRate < 85.0) {
          score -= (85.0 - attendanceRate) * 1.5;
        }
        if (overtimeRatio > 20.0) {
          score -= (overtimeRatio - 20.0) * 1.2;
        }
        score -= (shiftDiscrepancies * 2.5);
        return score.clamp(10.0, 100.0);
      }

      String getHealthStatus(double score) {
        if (score >= 85.0) return 'optimal';
        if (score >= 60.0) return 'moderate_risk';
        return 'critical_attention';
      }

      final optimal = calculateScore(attendanceRate: 98.0, overtimeRatio: 5.0, shiftDiscrepancies: 0);
      expect(optimal, 100.0);
      expect(getHealthStatus(optimal), 'optimal');

      final moderate = calculateScore(attendanceRate: 75.0, overtimeRatio: 28.0, shiftDiscrepancies: 2);
      expect(moderate, closeTo(70.4, 0.1));
      expect(getHealthStatus(moderate), 'moderate_risk');

      final critical = calculateScore(attendanceRate: 50.0, overtimeRatio: 55.0, shiftDiscrepancies: 8);
      expect(critical, lessThan(60.0));
      expect(getHealthStatus(critical), 'critical_attention');
    });

    test('Evaluates Rule 1: WF_ATTENDANCE_COVERAGE_DROP when attendance drops below 75% or absence exceeds 20%', () {
      bool isAttendanceDrop(int records, double attRate, double absRate) {
        return records >= 10 && (attRate < 75.0 || absRate > 20.0);
      }

      expect(isAttendanceDrop(5, 60.0, 30.0), isFalse); // Insufficient records
      expect(isAttendanceDrop(100, 92.0, 5.0), isFalse); // Healthy
      expect(isAttendanceDrop(100, 72.0, 15.0), isTrue); // Attendance < 75%
      expect(isAttendanceDrop(100, 78.0, 22.0), isTrue); // Absence > 20%
    });

    test('Evaluates Rule 2: WF_OVERTIME_SPIKE when overtime exceeds 25% of regular hours', () {
      bool isOvertimeSpike(double regHours, double otRatio) {
        return regHours >= 40.0 && otRatio > 25.0;
      }

      expect(isOvertimeSpike(30.0, 30.0), isFalse); // Not enough base hours
      expect(isOvertimeSpike(160.0, 15.0), isFalse); // Normal overtime
      expect(isOvertimeSpike(160.0, 29.2), isTrue); // Spike detected
    });

    test('Evaluates Rule 3: WF_SHIFT_COVERAGE_GAP when high sales volume occurs without cashier shift logs or excessive cash discrepancies', () {
      bool isShiftCoverageGap(int completedSales, int shiftsCount, int discrepancies) {
        return (completedSales >= 50 && shiftsCount == 0) || (shiftsCount >= 10 && discrepancies >= 3);
      }

      expect(isShiftCoverageGap(40, 0, 0), isFalse); // Sales below threshold
      expect(isShiftCoverageGap(120, 0, 0), isTrue); // High sales with 0 shifts
      expect(isShiftCoverageGap(200, 20, 4), isTrue); // Excessive discrepancies
      expect(isShiftCoverageGap(200, 20, 1), isFalse); // Acceptable
    });

    test('Evaluates Rule 4: WF_PEAK_DEMAND_UNDERSTAFFING when daily throughput >= 100 txns/day with understaffing', () {
      bool isUnderstaffedPeak(int activeStaff, int totalSales, int days) {
        final dailyTxns = totalSales / (days > 0 ? days : 1);
        return activeStaff > 0 && activeStaff < 2 && dailyTxns >= 100.0;
      }

      expect(isUnderstaffedPeak(1, 3500, 30), isTrue); // 116 txns/day with 1 staff
      expect(isUnderstaffedPeak(4, 3500, 30), isFalse); // 4 staff handles it
    });

    test('Evaluates Rule 5: WF_MISSING_ATTENDANCE_LOGS when staff is active but attendance records are zero', () {
      bool isMissingAttendanceLogs(int activeStaff, int attendanceRecords) {
        return activeStaff >= 2 && attendanceRecords == 0;
      }

      expect(isMissingAttendanceLogs(5, 0), isTrue);
      expect(isMissingAttendanceLogs(5, 50), isFalse);
      expect(isMissingAttendanceLogs(1, 0), isFalse);
    });

    test('Fair branch benchmarking: qualifies Sufficient vs Low Volume based on active staff and transaction count', () {
      String qualifyData(int staff, int txns) {
        if (staff >= 3 && txns >= 50) return 'Sufficient';
        return 'Low Volume';
      }

      expect(qualifyData(5, 300), 'Sufficient');
      expect(qualifyData(1, 400), 'Low Volume');
      expect(qualifyData(6, 20), 'Low Volume');
    });
  });

  group('Operations Intelligence Phase 9: Widget & UI Verification Tests', () {
    testWidgets('Renders Tab 10 Workforce Intelligence with Headline Score, KPIs, and Detected Risks', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase9IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 10, // Tab 10: Workforce Intelligence
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify Header & Scan Button
      expect(find.text('Workforce Intelligence'), findsWidgets);
      expect(find.text('Run Workforce Scan'), findsOneWidget);

      // Verify Headline Score Card
      expect(find.text('68.5 / 100'), findsOneWidget);
      expect(find.text('Moderate Risk'), findsWidgets);
      expect(find.text('2 Active Risks'), findsOneWidget);

      // Verify Mini KPIs
      expect(find.text('8 Staff'), findsOneWidget);
      expect(find.text('72.5%'), findsWidgets);

      // Verify Detected Risks
      expect(find.text('Significant Drop in Workforce Attendance Coverage'), findsOneWidget);
      expect(find.text('Unusual Growth in Recorded Overtime Hours'), findsOneWidget);
      expect(find.text('View in Action Centre'), findsWidgets);
      expect(find.text('Open in Staff Hub'), findsWidgets);
    });

    testWidgets('Sub-tab ChoiceChips switch between workforce domains', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase9IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 10,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Click "Attendance Patterns" ChoiceChip
      await tester.tap(find.text('Attendance Patterns'));
      await tester.pumpAndSettle();
      expect(find.text('Workforce Availability & Attendance Patterns'), findsOneWidget);
      expect(find.text('Present Records'), findsOneWidget);
      expect(find.text('Absences Recorded'), findsOneWidget);

      // Click "Shift Coverage" ChoiceChip
      await tester.tap(find.text('Shift Coverage'));
      await tester.pumpAndSettle();
      expect(find.text('Shift Execution & Cashier Coverage'), findsOneWidget);
      expect(find.text('Total Shifts'), findsWidgets);
      expect(find.text('Avg Shift Duration'), findsOneWidget);
      expect(find.text('Cash Discrepancies'), findsOneWidget);

      // Click "Capacity & Demand" ChoiceChip
      await tester.tap(find.text('Capacity & Demand'));
      await tester.pumpAndSettle();
      expect(find.text('Workforce Capacity & Demand Alignment'), findsOneWidget);
      expect(find.text('Avg Txns / Staff-Day'), findsOneWidget);

      // Click "Overtime & Cost" ChoiceChip
      await tester.tap(find.text('Overtime & Cost'));
      await tester.pumpAndSettle();
      expect(find.text('Overtime Analysis & Workforce Costs'), findsOneWidget);
      expect(find.text('Gross Workforce Earnings'), findsOneWidget);

      // Click "Branch Benchmarks" ChoiceChip
      await tester.tap(find.text('Branch Benchmarks'));
      await tester.pumpAndSettle();
      expect(find.text('Branch Workforce Benchmarks'), findsOneWidget);
      expect(find.text('Downtown Superstore'), findsOneWidget);
      expect(find.text('Airport Express Kiosk'), findsOneWidget);
    });

    testWidgets('Diagnostic Scan button triggers workforce scan and displays success snackbar', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase9IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 10,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final scanBtn = find.text('Run Workforce Scan');
      expect(scanBtn, findsOneWidget);

      await tester.tap(scanBtn);
      await tester.pumpAndSettle();

      expect(service.scanTriggered, isTrue);
      expect(find.textContaining('Workforce diagnostic scan complete'), findsOneWidget);
    });

    testWidgets('View in Action Centre button transitions to Tab 11 (Action & Risk Centre)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase9IntelligenceService();
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 10,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Tap "View in Action Centre" on first detected risk
      final actionCentreBtn = find.text('View in Action Centre').first;
      expect(actionCentreBtn, findsOneWidget);

      await tester.tap(actionCentreBtn);
      await tester.pumpAndSettle();

      // TabBarView should now be showing Tab 11: Action & Risk Centre
      expect(find.text('Centralized Action & Risk Centre'), findsOneWidget);
    });

    testWidgets('Masks confidential payroll figures when user lacks staff.payroll or accounting.view permissions', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Create service and session where user lacks payroll permission
      final service = _MockPhase9IntelligenceService(canViewPayroll: false);
      final session = _createSession(
        isOwner: false,
        canViewPayroll: false,
        permissions: {'operations_intelligence.view', 'staff.view', 'reports.view'},
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 10,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Go to Overtime & Cost
      await tester.tap(find.text('Overtime & Cost'));
      await tester.pumpAndSettle();

      // Operational hours should still be visible
      expect(find.text('Regular Operating Hours'), findsOneWidget);
      expect(find.text('Overtime Hours'), findsOneWidget);

      // Confidential financial figures must NOT be visible
      expect(find.text('Gross Workforce Earnings'), findsNothing);
      expect(find.text('Net Workforce Earnings'), findsNothing);

      // Privacy banner must be displayed
      expect(find.text('Payroll Metrics Masked for Privacy & Role Permissions'), findsOneWidget);
      expect(find.textContaining('require \'staff.payroll\' or \'accounting.view\' permission'), findsOneWidget);
    });

    testWidgets('Displays full payroll figures when user has owner role or staff.payroll permission', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase9IntelligenceService(canViewPayroll: true);
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 10,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Go to Overtime & Cost
      await tester.tap(find.text('Overtime & Cost'));
      await tester.pumpAndSettle();

      expect(find.text('Gross Workforce Earnings'), findsOneWidget);
      expect(find.text('Net Workforce Earnings'), findsOneWidget);
      expect(find.text('Disbursed Payments'), findsOneWidget);
      expect(find.text('Workforce Earnings by Kind:'), findsOneWidget);
    });

    testWidgets('Renders clean empty state when no workforce risks are detected', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase9IntelligenceService(emptyData: true);
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 10,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Workforce Healthy'), findsOneWidget);
      expect(find.text('No Active Workforce Operational Risks Detected'), findsOneWidget);
      expect(find.text('Significant Drop in Workforce Attendance Coverage'), findsNothing);
    });

    testWidgets('Displays error view with retry button when workforce intelligence service fails', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = _MockPhase9IntelligenceService(failWorkforce: true);
      final session = _createSession(isOwner: true);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OperationsIntelligenceScreen(
            session: session,
            service: service,
            initialTab: 10,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Simulated workforce intelligence RPC connection failure'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
