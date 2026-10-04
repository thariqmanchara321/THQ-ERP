import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/staff_screen.dart';
import 'package:client_app/services/staff_load_service.dart';
import 'package:client_app/widgets/staff_statement_view.dart';
import 'support/staff_statement_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = ClientSession(
  business: ClientBusiness(
    id: 'tenant',
    membershipId: 'owner',
    name: 'THQ Yard',
    slug: 'yard',
    businessType: 'material_yard',
    status: 'active',
  ),
  modules: [],
  roles: {'owner'},
  permissions: {},
  currencyCode: 'INR',
  timezone: 'Asia/Kolkata',
  locale: 'en_IN',
  locations: [
    ClientLocationAccess(
      id: 'yard',
      code: 'MAIN',
      name: 'Main Yard',
      type: 'store',
      trackingCode: null,
      accessLevel: 'manage',
    ),
  ],
);

class _StaffService extends StaffLoadService {
  final String basis;
  final calls = <Map<String, dynamic>>[];
  _StaffService([this.basis = 'daily']);
  @override
  Future<Map<String, dynamic>> staff({
    required String tenantId,
    required String action,
    String? locationId,
    Map<String, dynamic> data = const {},
  }) async {
    calls.add({'action': action, ...data});
    if (action == 'statement') {
      return {
        ...staffStatementFixture(),
        'attendance': [
          {'hours': 8},
        ],
        'history': [
          {'action': 'attendance.save'},
          {'action': 'earning.post'},
        ],
      };
    }
    if (!['report', 'detail', 'list'].contains(action)) {
      return {'recorded': true};
    }
    // A legacy response must not reintroduce attendance or payroll suggestions.
    return {
      'staff': [
        {
          'id': 'staff',
          'name': 'Amina',
          'staff_code': 'STF-1',
          'active': true,
          'job_role': 'staff',
          'wage_basis': basis,
          'location_id': 'yard',
          'base_rate': 700,
          'overtime_rate': 100,
          'outstanding': 250,
          'advance_balance': 0,
        },
      ],
      'attendance': [
        {
          'staff_id': 'staff',
          'status': 'present',
          'hours': 8,
          'overtime_hours': 4,
        },
      ],
      'history': [
        {'action': 'attendance.save'},
        {'action': 'earning.post'},
      ],
      'earnings': [
        {
          'staff_name': 'Amina',
          'earning_date': '2026-10-04',
          'kind': 'payroll',
          'amount': 700,
          'paid_amount': 450,
          'outstanding': 250,
        },
      ],
      'payments': [
        {
          'staff_name': 'Amina',
          'payment_date': '2026-10-04',
          'amount': 450,
          'payment_method': 'cash',
          'advance_amount': 0,
        },
      ],
    };
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> _open(WidgetTester tester, _StaffService service) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: StaffScreen(session: _session, service: service),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('old attendance calls fail before a database request', () async {
    await expectLater(
      StaffLoadService().staff(tenantId: 'tenant', action: 'attendance'),
      throwsStateError,
    );
  });

  testWidgets('Staff keeps payroll and payments with no attendance controls', (
    tester,
  ) async {
    final service = _StaffService();
    await _open(tester, service);
    expect(find.byType(Tab), findsNWidgets(3));
    expect(find.textContaining('Attendance'), findsNothing);
    await tester.tap(find.text('Earnings / payroll'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paid INR 450.00'), findsOneWidget);
    await tester.tap(find.text('Payments / advances'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cash'), findsOneWidget);
    expect(service.calls.every((c) => c['action'] != 'attendance'), isTrue);
  });

  for (final basis in ['daily', 'hourly', 'monthly']) {
    testWidgets('$basis payroll uses explicit units and allowances', (
      tester,
    ) async {
      final service = _StaffService(basis);
      await _open(tester, service);
      await tester.tap(find.text('Post salary / wages'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(_field('Payable months / days / hours'))
            .controller!
            .text,
        basis == 'monthly' ? '1.0' : '0.0',
      );
      expect(
        tester
            .widget<TextField>(_field('Allowances including overtime'))
            .controller!
            .text,
        '0',
      );
      await tester.enterText(_field('Payable months / days / hours'), '3');
      await tester.enterText(_field('Allowances including overtime'), '50');
      await tester.tap(find.text('Post earning'));
      await tester.pumpAndSettle();
      final posted = service.calls.singleWhere((c) => c['action'] == 'payroll');
      expect(posted['units'], 3);
      expect(posted['rate'], 700);
      expect(posted['allowances'], 50);
      expect(posted.containsKey('hours'), isFalse);
      expect(posted.containsKey('overtime_hours'), isFalse);
    });
  }

  testWidgets(
    'Staff statements exclude old attendance while retaining earnings',
    (tester) async {
      await _open(tester, _StaffService());
      await tester.tap(find.textContaining('Amina • STF-1'));
      await tester.pumpAndSettle();
      final record = tester
          .widget<StaffStatementView>(find.byType(StaffStatementView))
          .statement
          .data;
      expect(record.containsKey('attendance'), isFalse);
      expect(record['earnings'], isNotEmpty);
      expect(record['payments'], isNotEmpty);
      expect(record['history'], [
        {'action': 'earning.post'},
      ]);
    },
  );
}
