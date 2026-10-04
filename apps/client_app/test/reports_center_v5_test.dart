import 'dart:async';
import 'dart:convert';

import 'package:client_app/models/client_session.dart';
import 'package:client_app/models/report_document.dart';
import 'package:client_app/screens/reports_center_v500_screen.dart';
import 'package:client_app/services/location_scope_service.dart';
import 'package:client_app/services/report_file_builder.dart';
import 'package:client_app/services/reports_center_service.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const session = ClientSession(
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
  canViewAllLocations: true,
  locations: [
    ClientLocationAccess(
      id: 'yard',
      code: 'Y',
      name: 'Material Yard',
      type: 'store',
      trackingCode: null,
      accessLevel: 'manage',
    ),
  ],
);

Map<String, dynamic> fixture({
  String number = 'INV-1',
  bool complete = false,
  int count = 1,
}) => {
  'definition': {
    'key': 'sales_register',
    'title':
        'Sales Register with saved material load, driver and payment details',
    'category': 'Sales',
    'description': 'Saved invoices, payments and all driver and load evidence.',
    'basis': 'period',
    'columns': [
      {
        'key': 'sale_number',
        'label': 'Invoice Number',
        'type': 'text',
        'width': 180,
      },
      {
        'key': 'grand_total',
        'label': 'Invoice Total',
        'type': 'money',
        'width': 180,
      },
    ],
  },
  'columns': [
    {
      'key': 'sale_number',
      'label': 'Invoice Number',
      'type': 'text',
      'width': 180,
    },
    {
      'key': 'grand_total',
      'label': 'Invoice Total',
      'type': 'money',
      'width': 180,
    },
  ],
  'rows': [
    for (var i = 0; i < count; i++)
      {
        'sale_number': count == 1 ? number : 'INV-$i',
        'grand_total': i + 0.25,
        'notes': 'All entered notes remain available.',
        'saved_evidence': {
          'driver': 'Saved Driver',
          'payments': [
            {'amount': 10.25, 'reference': 'PAY-REF'},
          ],
        },
        if (i == count - 1) 'late_column': 'LAST_FIELD',
      },
  ],
  'context': {
    'company': 'THQ Yard',
    'currency': 'INR',
    'location': 'All authorized stores',
    'from': '2026-10-01',
    'to': '2026-10-04',
    'summary_basis': 'All matching records, including undisplayed pages',
  },
  'summary': [
    {
      'key': 'grand_total',
      'label': 'Invoice Total',
      'value': 0.25,
      'type': 'money',
    },
  ],
  'total_rows': count,
  'offset': 0,
  'complete': complete,
};

class FakeReports extends ReportsCenterService {
  final requests = <ReportRequest>[];
  Future<ReportDocument> Function(ReportRequest)? handler;
  @override
  Future<List<ReportDefinition>> catalog(String tenantId) async => [
    ReportDefinition.fromMap(reportMap(fixture()['definition'])),
  ];
  @override
  Future<ReportDocument> run(ReportRequest request) async {
    requests.add(request);
    return handler == null
        ? ReportDocument.fromMap(fixture())
        : handler!(request);
  }
}

Future<void> open(
  WidgetTester tester,
  FakeReports service,
  Size size, {
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  LocationScopeService.selectedLocationId.value = null;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: ReportsCenterV500Screen(session: session, service: service),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(1366, 768),
    const Size(320, 700),
    const Size(640, 480),
  ]) {
    testWidgets('report selector and table fit ${size.width}x${size.height}', (
      tester,
    ) async {
      await open(tester, FakeReports(), size);
      expect(tester.takeException(), isNull);
      expect(find.text('INV-1'), findsOneWidget);
      expect(find.text('INR 0.25'), findsWidgets);
      expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
      await tester.tap(find.text('INV-1'));
      await tester.pumpAndSettle();
      expect(find.text('All entered notes remain available.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('larger text fits a narrow report', (tester) async {
    await open(tester, FakeReports(), const Size(360, 800), scale: 1.5);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending search disables export and ignores an older response', (
    tester,
  ) async {
    final service = FakeReports();
    await open(tester, service, const Size(1366, 768));
    final first = Completer<ReportDocument>();
    final second = Completer<ReportDocument>();
    service.handler = (r) => r.query == 'first' ? first.future : second.future;
    final search = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == 'Search all saved fields',
    );
    await tester.enterText(search, 'first');
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .enabled,
      isFalse,
    );
    await tester.enterText(search, 'second');
    await tester.pump(const Duration(milliseconds: 450));
    second.complete(ReportDocument.fromMap(fixture(number: 'LATEST')));
    await tester.pumpAndSettle();
    first.complete(ReportDocument.fromMap(fixture(number: 'OLD')));
    await tester.pumpAndSettle();
    expect(find.text('LATEST'), findsOneWidget);
    expect(find.text('OLD'), findsNothing);
    expect(service.requests.last.query, 'second');
  });
  testWidgets('changing the shared store scope reloads with the new store', (
    tester,
  ) async {
    final service = FakeReports();
    await open(tester, service, const Size(1366, 768));
    LocationScopeService.selectedLocationId.value = 'yard';
    await tester.pumpAndSettle();
    expect(service.requests.last.locationId, 'yard');
    await tester.pumpWidget(const SizedBox());
    LocationScopeService.selectedLocationId.value = null;
    expect(tester.takeException(), isNull);
  });
  test(
    'export preserves more than 5000 rows, late columns and numeric money',
    () {
      final report = ReportDocument.fromMap(
        fixture(complete: true, count: 5007),
      );
      final workbook = Excel.decodeBytes(ReportFileBuilder.excel(report));
      final rows = workbook['Report'].rows;
      final header = rows.indexWhere(
        (r) => r.any((c) => c?.value.toString() == 'Invoice Number'),
      );
      expect(rows.length - header - 1, 5007);
      expect(rows[header + 1][1]?.value, isA<DoubleCellValue>());
      expect(rows.last.any((c) => c?.value.toString() == 'LAST_FIELD'), isTrue);
      expect(
        workbook['Evidence'].rows.any(
          (r) => r.any((c) => c?.value.toString() == 'Saved Driver'),
        ),
        isTrue,
      );
    },
  );
  test('long Unicode evidence and formula-like text are preserved as text', () {
    final data = fixture(complete: true);
    final rows = reportMaps(data['rows']);
    final note = List.filled(20000, '😀 Receipt detail. ').join();
    rows.first['notes'] = note;
    rows.first['sale_number'] = '=1+1';
    data['rows'] = rows;
    final workbook = Excel.decodeBytes(
      ReportFileBuilder.excel(ReportDocument.fromMap(data)),
    );
    final notes = workbook['Evidence'].rows
        .where((r) => r.length > 3 && r[1]?.value.toString() == 'notes')
        .map((r) => r[3]?.value.toString() ?? '')
        .join();
    expect(notes, note);
    expect(
      workbook['Report'].rows.any(
        (r) => r.any(
          (c) => c?.value is TextCellValue && c?.value.toString() == '=1+1',
        ),
      ),
      isTrue,
    );
  });
  test('incomplete datasets cannot be exported', () {
    final report = ReportDocument.fromMap(fixture());
    expect(() => ReportFileBuilder.json(report), throwsStateError);
    expect(() => ReportFileBuilder.excel(report), throwsStateError);
  });
  test(
    'money, zero and invoice count format correctly without false quantity totals',
    () {
      final report = ReportDocument.fromMap(fixture(complete: true));
      expect(report.format(0, 'money'), 'INR 0.00');
      expect(
        report.cell({
          'metric': 'Posted invoices',
          'amount': 7,
        }, const ReportColumn('amount', 'Amount', 'money', 160)),
        '7',
      );
      expect(
        jsonDecode(
          utf8.decode(ReportFileBuilder.json(report)),
        )['rows'][0]['grand_total'],
        0.25,
      );
      final request = ReportRequest(
        tenantId: 'tenant',
        key: 'sales_register',
        from: DateTime(2026),
        to: DateTime(2026, 10),
        query: 'saved driver',
        offset: 100,
      );
      expect(request.exportRequest().parameters['p_limit'], 0);
      expect(request.exportRequest().parameters['p_offset'], 0);
      expect(request.exportRequest().query, 'saved driver');
    },
  );
}
