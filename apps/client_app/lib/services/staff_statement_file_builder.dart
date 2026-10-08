import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/record_presentation.dart';
import '../models/staff_statement.dart';
import 'report_file_builder.dart';

/// The screen, workbook and PDF use one complete, dated statement response.
class StaffStatementFileBuilder {
  static const ledgerKeys = [
    'date',
    'document_reference',
    'location_name',
    'description',
    'earning',
    'payment',
    'balance',
  ];
  static const ledgerLabels = [
    'Date',
    'Document',
    'Store',
    'Description',
    'Earnings',
    'Payments',
    'Running balance',
  ];
  static Uint8List excel(
    StaffStatement s, {
    required String company,
    required String location,
  }) {
    final book = Excel.createExcel();
    book.rename(book.getDefaultSheet()!, 'Statement');
    final sheet = book['Statement'];
    void append(Sheet target, List<CellValue?> row) {
      if (target.maxRows >= 1048576) {
        throw StateError(
          'Excel row limit reached. Use the complete JSON export.',
        );
      }
      target.appendRow(row);
    }

    for (final row in [
      ['Staff statement', company],
      ['Staff ID', s.staffCode],
      ['Staff name', s.name],
      ['Period', s.period],
      ['Store scope', location],
      ['Currency', s.currency],
      ['Balance basis', StaffStatement.balanceNote],
    ]) {
      append(sheet, row.map(TextCellValue.new).toList());
    }
    for (final e in s.summary.entries) {
      append(sheet, [
        TextCellValue(RecordPresentation.label(e.key)),
        ReportFileBuilder.excelValue(e.value),
      ]);
    }
    append(sheet, []);
    final headerRow = sheet.maxRows;
    append(sheet, ledgerLabels.map(TextCellValue.new).toList());
    for (final row in s.rows('ledger')) {
      append(
        sheet,
        ledgerKeys
            .map((key) => ReportFileBuilder.excelValue(row[key]))
            .toList(),
      );
    }
    for (var i = 0; i < ledgerKeys.length; i++) {
      sheet.setColumnWidth(i, i == 3 ? 35 : 24);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: headerRow))
          .cellStyle = CellStyle(
        bold: true,
      );
    }
    // Detail sheets retain every business field and split long notes safely.
    final data = s.report;
    for (final section in {
      'Profile': 'profile',
      'Store balances': 'balances_by_location',
      'Payslips': 'earnings',
      'Payments': 'payments',
      'Load allocations': 'load_allocations',
      'History': 'history',
    }.entries) {
      final target = book[section.key];
      append(target, [
        TextCellValue('Record'),
        TextCellValue('Field'),
        TextCellValue('Part'),
        TextCellValue('Value'),
      ]);
      final value = data[section.value];
      final records = value is List ? value : [value];
      for (var index = 0; index < records.length; index++) {
        for (final field in ReportFileBuilder.leaves(records[index])) {
          final parts = field.value is String
              ? ReportFileBuilder.chunks(field.value, 30000).toList()
              : [field.value];
          for (var part = 0; part < parts.length; part++) {
            append(target, [
              IntCellValue(index + 1),
              TextCellValue(RecordPresentation.label(field.key)),
              IntCellValue(part + 1),
              ReportFileBuilder.excelValue(parts[part]),
            ]);
          }
        }
      }
      target.setColumnWidth(1, 48);
      target.setColumnWidth(3, 65);
    }
    final bytes = book.save();
    if (bytes == null) throw StateError('Could not generate Staff statement.');
    return Uint8List.fromList(bytes);
  }

  static Future<Uint8List> pdf(
    StaffStatement s, {
    required String company,
    required String location,
    required ByteData regular,
    required ByteData bold,
    List<ByteData> fallback = const [],
  }) async {
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
        fontFallback: fallback.map(pw.Font.ttf).toList(),
      ),
    );
    pw.Widget text(String value, {bool heading = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: heading ? 12 : 8,
          fontWeight: heading ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
    final widgets = <pw.Widget>[
      text(company, heading: true),
      text('Staff statement', heading: true),
      text('${s.name} • Staff ID: ${s.staffCode}'),
      text('${s.period} • $location • ${s.currency}'),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headerCount: 0,
        data: [
          for (final pair in [
            ['opening_balance', 'closing_balance'],
            ['period_earnings', 'period_payments'],
            ['closing_due', 'closing_advance'],
            ['current_due', 'current_advance'],
          ])
            [
              for (final key in pair)
                '${RecordPresentation.label(key)}: ${s.text(key, s.summary[key])}',
            ],
        ],
        cellPadding: const pw.EdgeInsets.all(6),
        cellStyle: const pw.TextStyle(fontSize: 9),
      ),
      text(StaffStatement.balanceNote),
      text(
        'Current balances can include transactions after the selected period.',
      ),
      text('Transaction statement (${s.rows('ledger').length})', heading: true),
    ];
    final ledger = s.rows('ledger');
    if (ledger.isEmpty) {
      widgets.add(
        text(
          'No transactions in this period. Opening balance carries forward.',
        ),
      );
    } else {
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: ledgerLabels,
          data: [
            for (final row in ledger)
              [for (final key in ledgerKeys) s.text(key, row[key])],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xff123a52),
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.all(5),
          columnWidths: const {
            0: pw.FixedColumnWidth(65),
            1: pw.FixedColumnWidth(95),
            2: pw.FlexColumnWidth(),
            3: pw.FlexColumnWidth(),
            4: pw.FixedColumnWidth(85),
            5: pw.FixedColumnWidth(85),
            6: pw.FixedColumnWidth(95),
          },
          cellAlignments: const {
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
          },
        ),
      );
    }
    // Details are separate paragraphs so long records paginate without clipping.
    final data = s.report;
    for (final section in {
      'Balances by store': 'balances_by_location',
      'Staff profile': 'profile',
      'Earnings / payslips': 'earnings',
      'Payments and allocations': 'payments',
      'Salary allocations to loads (informational)': 'load_allocations',
      'Activity history': 'history',
    }.entries) {
      final value = data[section.value];
      final records = value is List ? value : [value];
      if (records.isEmpty) {
        widgets.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [text(section.key, heading: true), text('No records.')],
            ),
          ),
        );
      }
      for (var index = 0; index < records.length; index++) {
        final paragraphs = <pw.Widget>[];
        for (final field in ReportFileBuilder.leaves(records[index])) {
          final key = field.key.split('.').last;
          final full =
              '${RecordPresentation.label(field.key)}: ${s.text(key, field.value)}';
          paragraphs.addAll(
            ReportFileBuilder.chunks(full, 320).map((part) => text(part)),
          );
        }
        widgets.add(
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (index == 0) text(section.key, heading: true),
                if (value is List) text('Record ${index + 1}', heading: true),
                ...paragraphs.take(1),
              ],
            ),
          ),
        );
        widgets.addAll(paragraphs.skip(1));
      }
    }
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        maxPages: 1000,
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Staff ID: ${s.staffCode} • ${s.period}',
              style: const pw.TextStyle(fontSize: 7),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
        build: (_) => widgets,
      ),
    );
    return doc.save();
  }
}
