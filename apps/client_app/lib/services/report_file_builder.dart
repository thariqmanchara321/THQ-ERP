import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/report_document.dart';
import '../models/record_presentation.dart';

/// Pure builders shared by saved files and printing. No screen/plugin state.
class ReportFileBuilder {
  static Iterable<MapEntry<String, dynamic>> leaves(
    dynamic value, [
    String path = '',
  ]) sync* {
    if (value is Map && value.isNotEmpty) {
      for (final entry in value.entries) {
        yield* leaves(
          entry.value,
          path.isEmpty ? '${entry.key}' : '$path.${entry.key}',
        );
      }
    } else if (value is List && value.isNotEmpty) {
      for (var index = 0; index < value.length; index++) {
        yield* leaves(value[index], '$path[${index + 1}]');
      }
    } else {
      yield MapEntry(path, value);
    }
  }

  static List<String> getColumns(ReportDocument report) => [
    ...report.columns
        .where((c) => !RecordPresentation.internal(c.key))
        .map((c) => c.key),
    ...report.rows
        .expand((r) => r.entries)
        .where(
          (e) =>
              e.value is! Map &&
              e.value is! List &&
              !RecordPresentation.internal(e.key),
        )
        .map((e) => e.key)
        .toSet()
        .difference(report.columns.map((c) => c.key).toSet())
        .toList()
      ..sort(),
  ];

  static Map<String, dynamic> metadata(ReportDocument report) => {
    'Company': report.context['company'],
    'Store': report.context['location'],
    'Period': '${report.context['from']} to ${report.context['to']}',
    'Basis': report.definition.dateBasis,
    'Currency / date timezone':
        '${report.currency} / ${report.context['timezone']}',
    if ((report.context['query']?.toString() ?? '').isNotEmpty)
      'Search': report.context['query'],
    if (report.context['sort_key'] != null)
      'Sort':
          '${report.context['sort_key']} (${report.context['sort_desc'] == true ? 'descending' : 'ascending'})',
    'Generated': report.context['generated_at'],
    'Totals basis': report.context['summary_basis'],
  };

  static Uint8List json(ReportDocument report) {
    report.requireComplete();
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(report.data)),
    );
  }

  static Iterable<String> chunks(String value, int length) sync* {
    if (value.isEmpty) {
      yield '';
      return;
    }
    for (var index = 0; index < value.length;) {
      var end = index + length;
      if (end > value.length) end = value.length;
      if (end < value.length &&
          value.codeUnitAt(end - 1) >= 0xD800 &&
          value.codeUnitAt(end - 1) <= 0xDBFF) {
        end--;
      }
      yield value.substring(index, end);
      index = end;
    }
  }

  static CellValue excelValue(dynamic value) {
    if (value is int) return IntCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    if (value is bool) return BoolCellValue(value);
    // TextCellValue is stored explicitly as a string, never as a formula.
    return TextCellValue(
      value == null
          ? ''
          : value is Map || value is List
          ? jsonEncode(value)
          : value.toString(),
    );
  }

  static Uint8List excel(ReportDocument report) {
    report.requireComplete();
    final book = Excel.createExcel();
    book.rename(book.getDefaultSheet()!, 'Report');
    final sheet = book['Report'];
    final fields = getColumns(report);
    final labels = {
      for (final column in report.columns) column.key: column.label,
    };
    void append(Sheet target, List<CellValue?> values) {
      if (target.maxRows >= 1048576) {
        throw StateError(
          'Excel row limit reached. Use the complete JSON export.',
        );
      }
      target.appendRow(values);
    }

    append(sheet, [TextCellValue(report.definition.title)]);
    append(sheet, [TextCellValue(report.definition.description)]);
    for (final entry in metadata(report).entries) {
      append(sheet, [TextCellValue(entry.key), excelValue(entry.value)]);
    }
    append(sheet, [
      TextCellValue('Matching records'),
      IntCellValue(report.totalRows),
    ]);
    append(sheet, [
      TextCellValue('Long fields and nested saved data'),
      TextCellValue(
        'Evidence sheet: record number, field path and numbered parts; no omitted content.',
      ),
    ]);
    append(sheet, []);
    final headerRow = sheet.maxRows;
    append(
      sheet,
      fields
          .map((k) => TextCellValue(labels[k] ?? k.replaceAll('_', ' ')))
          .toList(),
    );
    for (var index = 0; index < fields.length; index++) {
      sheet
          .cell(
            CellIndex.indexByColumnRow(columnIndex: index, rowIndex: headerRow),
          )
          .cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('FF123A52'),
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
      );
      sheet.setColumnWidth(
        index,
        report.columns.any((c) => c.key == fields[index] && c.numeric)
            ? 20
            : 30,
      );
    }
    final evidence = book['Evidence'];
    append(evidence, [
      TextCellValue('Record'),
      TextCellValue('Field path'),
      TextCellValue('Part'),
      TextCellValue('Value'),
    ]);
    for (var index = 0; index < report.rows.length; index++) {
      final row = RecordPresentation.report(report.rows[index]);
      append(
        sheet,
        fields.map((key) {
          final value = row[key];
          if (value is String && value.length > 30000) {
            return TextCellValue(
              'Full text in Evidence: record ${index + 1}, $key',
            );
          }
          return excelValue(value);
        }).toList(),
      );
      for (final field in leaves(RecordPresentation.report(row))) {
        final parts = field.value is String
            ? chunks(field.value, 30000).toList()
            : [field.value];
        for (var part = 0; part < parts.length; part++) {
          append(evidence, [
            IntCellValue(index + 1),
            TextCellValue(field.key),
            IntCellValue(part + 1),
            excelValue(parts[part]),
          ]);
        }
      }
    }
    evidence.setColumnWidth(1, 50);
    evidence.setColumnWidth(3, 65);
    final summary = book['Summary'];
    append(summary, [
      TextCellValue(report.context['summary_basis']?.toString() ?? ''),
    ]);
    for (final metric in report.summary) {
      append(summary, [
        TextCellValue(metric['label']?.toString() ?? ''),
        excelValue(metric['value']),
        TextCellValue(metric['type']?.toString() ?? ''),
      ]);
    }
    final bytes = book.save();
    if (bytes == null) throw StateError('Could not generate the workbook.');
    return Uint8List.fromList(bytes);
  }

  static Future<Uint8List> pdf(
    ReportDocument report, {
    required ByteData regular,
    required ByteData bold,
    List<ByteData> fallback = const [],
    bool evidence = false,
    int maxPages = 1000,
  }) async {
    report.requireComplete();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
        fontFallback: fallback.map(pw.Font.ttf).toList(),
      ),
    );
    final widgets = <pw.Widget>[];
    pw.Widget paragraph(String text, {bool heading = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: heading ? 11 : 8,
          fontWeight: heading ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
    widgets.add(paragraph(report.definition.title, heading: true));
    widgets.add(paragraph(report.definition.description));
    for (final entry in metadata(report).entries) {
      widgets.addAll(
        chunks(
          '${entry.key.replaceAll('_', ' ')}: ${entry.value}',
          350,
        ).map(paragraph),
      );
    }
    widgets.add(
      paragraph(
        '${report.totalRows} matching records • ${report.currency}',
        heading: true,
      ),
    );
    if (report.summary.isNotEmpty) {
      widgets.add(
        pw.TableHelper.fromTextArray(
          headerCount: 0,
          data: [
            for (var index = 0; index < report.summary.length; index += 2)
              [
                '${report.summary[index]['label']}: ${report.format(report.summary[index]['value'], report.summary[index]['type']?.toString() ?? 'text')}',
                if (index + 1 < report.summary.length)
                  '${report.summary[index + 1]['label']}: ${report.format(report.summary[index + 1]['value'], report.summary[index + 1]['type']?.toString() ?? 'text')}'
                else
                  '',
              ],
          ],
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.all(4),
          columnWidths: const {
            0: pw.FlexColumnWidth(),
            1: pw.FlexColumnWidth(),
          },
        ),
      );
    }
    final columns = report.columns
        .where((c) => !RecordPresentation.internal(c.key))
        .toList();
    // A stable record number and document reference link every column band.
    if (columns.isEmpty) {
      throw StateError('This report has no defined columns.');
    }
    final identifier = columns.firstWhere(
      (c) => const {
        'sale_number',
        'purchase_number',
        'return_number',
        'load_number',
        'entry_number',
        'source_number',
        'staff_code',
        'code',
      }.contains(c.key),
      orElse: () => columns.first,
    );
    for (var start = 0; start < columns.length; start += 4) {
      final fields = columns.skip(start).take(4).toList();
      final band = [
        if (start > 0 && !fields.any((c) => c.key == identifier.key))
          identifier,
        ...fields,
      ];
      if (start > 0) widgets.add(pw.NewPage());
      widgets.add(
        paragraph(
          'Report columns ${start + 1}–${(start + 4).clamp(0, columns.length)}',
          heading: true,
        ),
      );
      final table = <List<String>>[];
      for (var index = 0; index < report.rows.length; index++) {
        final row = RecordPresentation.report(report.rows[index]);
        table.add([
          '${index + 1}',
          ...band.map((c) {
            final text = report.cell(row, c).replaceAll('\n', ' ');
            return text.length > 75
                ? '${text.substring(0, 75)}… [record detail]'
                : text;
          }),
        ]);
      }
      if (table.isEmpty) {
        widgets.add(paragraph('No matching records.'));
      } else {
        widgets.add(
          pw.TableHelper.fromTextArray(
            headers: ['#', ...band.map((c) => c.label)],
            data: table,
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xff123a52),
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellPadding: const pw.EdgeInsets.all(4),
            columnWidths: {
              for (var index = 0; index <= band.length; index++)
                index: index == 0
                    ? const pw.FixedColumnWidth(34)
                    : const pw.FlexColumnWidth(),
            },
            cellAlignments: {
              for (var index = 0; index <= band.length; index++)
                index: index > 0 && band[index - 1].numeric
                    ? pw.Alignment.centerRight
                    : pw.Alignment.centerLeft,
            },
          ),
        );
      }
    }
    final details = <MapEntry<int, List<MapEntry<String, dynamic>>>>[];
    for (var index = 0; index < report.rows.length; index++) {
      final row = RecordPresentation.report(report.rows[index]);
      final fields = evidence
          ? leaves(RecordPresentation.report(row)).toList()
          : [
              for (final column in columns)
                if (report.cell(row, column).length > 75)
                  MapEntry(column.label, row[column.key]),
            ];
      if (fields.isNotEmpty) details.add(MapEntry(index + 1, fields));
    }
    if (details.isNotEmpty) {
      widgets.add(pw.NewPage());
      widgets.add(
        paragraph(
          evidence
              ? 'Complete saved record details'
              : 'Full text for longer report fields',
          heading: true,
        ),
      );
      for (final record in details) {
        widgets.add(paragraph('Record ${record.key}', heading: true));
        for (final field in record.value) {
          final text =
              '${field.key}: ${field.value is Map || field.value is List ? jsonEncode(field.value) : field.value ?? '—'}';
          for (final part in chunks(text, 320)) {
            final wrap = part.replaceAllMapped(
              RegExp(r'\S{55,}'),
              (m) => chunks(m[0]!, 45).join(' '),
            );
            widgets.add(paragraph(wrap));
          }
        }
      }
    }
    try {
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          maxPages: maxPages,
          header: (context) {
            if (context.pageNumber > maxPages) {
              throw StateError(
                'This PDF exceeds $maxPages pages. Use complete Excel/JSON or a narrower date range.',
              );
            }
            return pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    report.context['company']?.toString() ?? '',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    report.context['location']?.toString() ?? '',
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              ],
            );
          },
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${report.definition.title} • Saved report snapshot',
                style: const pw.TextStyle(fontSize: 7),
              ),
              pw.Text(
                'Page ${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 7),
              ),
            ],
          ),
          build: (_) => widgets,
        ),
      );
    } on pw.TooManyPagesException {
      throw StateError(
        'The PDF could not paginate this saved content. Use complete Excel/JSON or a narrower date range.',
      );
    }
    return document.save();
  }
}
