import 'dart:convert';
import 'dart:io';
import 'package:client_app/models/record_presentation.dart';
import 'package:client_app/models/staff_statement.dart';
import 'package:client_app/models/report_document.dart';
import 'package:client_app/services/report_file_builder.dart';
import 'package:client_app/services/staff_statement_file_builder.dart';
import 'package:client_app/widgets/record_preview.dart';
import 'package:client_app/widgets/staff_statement_dialog.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reports_center_v5_test.dart' as reports;
import 'support/staff_statement_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'human reports hide nested internal IDs and retain business codes without mutating saved data',
    () {
      final saved = staffStatementFixture();
      final before = jsonEncode(saved);
      final clean = RecordPresentation.report(saved);
      expect(jsonEncode(clean), isNot(contains(internalUuid)));
      expect(jsonEncode(clean), contains('STF-001'));
      expect(jsonEncode(clean), contains('JE-1'));
      expect(jsonEncode(clean), contains('LOAD-01'));
      expect(jsonEncode(saved), before);
    },
  );
  test(
    'dated payslips use paid through end and preserve the current saved balances',
    () {
      final s = StaffStatement(staffStatementFixture(), currency: 'INR');
      expect(s.report['earnings'][0]['paid_amount'], 200);
      expect(s.report['earnings'][0]['outstanding'], 300);
      expect(s.data['earnings'][0]['paid_amount'], 300);
      expect(s.data['earnings'][0]['outstanding'], 200);
      expect(s.summary['current_due'], 200);
    },
  );
  test(
    'incomplete statements fail instead of exporting partial financial data',
    () {
      expect(
        () => StaffStatement({
          ...staffStatementFixture(),
          'complete': false,
        }, currency: 'INR'),
        throwsStateError,
      );
      expect(
        () => StaffStatement({'complete': true}, currency: 'INR'),
        throwsStateError,
      );
    },
  );
  test(
    'staff workbook retains every ledger row, numeric amounts and allocation detail',
    () {
      final s = StaffStatement(
        staffStatementFixture(count: 75),
        currency: 'INR',
      );
      final book = Excel.decodeBytes(
        StaffStatementFileBuilder.excel(
          s,
          company: 'THQ Yard',
          location: 'Main Yard',
        ),
      );
      final rows = book['Statement'].rows;
      final header = rows.indexWhere(
        (r) => r.first?.value.toString() == 'Date',
      );
      expect(rows.length - header - 1, 75);
      expect(rows[header + 1][4]?.value, isA<IntCellValue>());
      final all = book.tables.values
          .expand((sheet) => sheet.rows)
          .expand((row) => row)
          .map((c) => c?.value.toString())
          .join('|');
      expect(all, isNot(contains(internalUuid)));
      expect(all, contains('BANK-REF-1'));
      expect(all, contains('LOAD-01'));
      expect(all, contains('STF-001'));
    },
  );
  test(
    'long Staff notes are retained across Excel cells without formula evaluation',
    () {
      final note = '=SUM(A1:A2)${' long saved note ' * 2500}END-OF-NOTE';
      final s = StaffStatement(
        staffStatementFixture(notes: note),
        currency: 'INR',
      );
      final book = Excel.decodeBytes(
        StaffStatementFileBuilder.excel(
          s,
          company: 'Yard',
          location: 'All stores',
        ),
      );
      final parts = book['Payslips'].rows
          .where((r) => r[1]?.value.toString() == 'Notes')
          .map((r) => r[3]!.value.toString())
          .join();
      expect(parts, note);
      expect(
        book['Payslips'].rows
            .where((r) => r[1]?.value.toString() == 'Notes')
            .every((r) => r[3]?.value is TextCellValue),
        isTrue,
      );
    },
  );
  test(
    'shared Reports Excel hides internal IDs while keeping complete JSON intact',
    () {
      final data = reports.fixture(complete: true);
      data['rows'][0]['tenant_id'] = internalUuid;
      data['rows'][0]['saved_evidence']['staff_id'] = internalUuid;
      data['rows'][0]['staff_code'] = 'STF-001';
      final doc = ReportDocument.fromMap(data);
      final book = Excel.decodeBytes(ReportFileBuilder.excel(doc));
      final text = book.tables.values
          .expand((sheet) => sheet.rows)
          .expand((row) => row)
          .map((c) => c?.value.toString())
          .join('|');
      expect(text, isNot(contains(internalUuid)));
      expect(text, contains('STF-001'));
      expect(utf8.decode(ReportFileBuilder.json(doc)), contains(internalUuid));
    },
  );
  for (final size in [
    const Size(1366, 1000),
    const Size(320, 700),
    const Size(640, 480),
  ]) {
    testWidgets('complete Staff statement fits ${size.width}x${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => StaffStatementDialog(
                    session: reports.session,
                    statement: StaffStatement(
                      staffStatementFixture(),
                      currency: 'INR',
                    ),
                  ),
                ),
                child: const Text('Open statement'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open statement'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Staff ID: STF-001'), findsOneWidget);
      expect(find.text('Opening balance'), findsOneWidget);
      expect(find.text('Closing balance'), findsOneWidget);
      expect(find.text('JE-1'), findsOneWidget);
      expect(find.textContaining(internalUuid), findsNothing);
      expect(find.text('Save PDF'), findsOneWidget);
      expect(find.text('Excel statement'), findsOneWidget);
    });
  }
  testWidgets('saved record preview uses readable fields for nested details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecordPreview(
              record: {
                'id': internalUuid,
                'staff_code': 'STF-001',
                'allocations': [
                  {
                    'staff_id': internalUuid,
                    'amount': 250,
                    'entry_number': 'JE-7',
                  },
                ],
              },
              currency: 'INR',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Allocations'));
    await tester.pumpAndSettle();
    expect(find.text('Staff ID:'), findsOneWidget);
    expect(find.text('JE-7'), findsOneWidget);
    expect(find.text('INR 250.00'), findsOneWidget);
    expect(find.textContaining(internalUuid), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
    'Staff PDFs generate all ledger and long detail pages with bundled fonts',
    () async {
      final fonts = [
        await rootBundle.load('assets/report_fonts/ReportSans.ttf'),
        await rootBundle.load('assets/report_fonts/ReportSans-Bold.ttf'),
        await rootBundle.load('assets/report_fonts/NotoSansMalayalam.ttf'),
        await rootBundle.load('assets/report_fonts/NotoSansDevanagari.ttf'),
      ];
      for (final count in [2, 75]) {
        final s = StaffStatement(
          staffStatementFixture(
            count: count,
            notes: count == 2
                ? 'Agreed salary'
                : '${'Long payroll evidence ' * 1200}END-OF-DETAIL',
          ),
          currency: 'INR',
        );
        final bytes = await StaffStatementFileBuilder.pdf(
          s,
          company: 'THQ Yard',
          location: 'Main Yard',
          regular: fonts[0],
          bold: fonts[1],
          fallback: fonts.skip(2).toList(),
        );
        expect(ascii.decode(bytes.take(4).toList()), '%PDF');
        final qa = Platform.environment['THQ_STAFF_QA_DIR'];
        if (qa != null) {
          Directory(qa).createSync(recursive: true);
          File('$qa/staff_statement_$count.pdf').writeAsBytesSync(bytes);
        }
      }
    },
  );
}
