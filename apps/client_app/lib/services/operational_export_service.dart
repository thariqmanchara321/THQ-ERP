import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class OperationalExportService {
  Map<String, dynamic> _flatten(Map<String, dynamic> record) {
    final output = <String, dynamic>{};
    void walk(String key, dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          walk(key.isEmpty ? '${entry.key}' : '$key.${entry.key}', entry.value);
        }
      } else {
        output[key] = value is List ? jsonEncode(value) : value;
      }
    }

    walk('', record);
    return output;
  }

  Future<void> saveJson(String name, Map<String, dynamic> dataset) async {
    await FileSaver.instance.saveFile(
      name: name,
      bytes: Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(dataset)),
      ),
      fileExtension: 'json',
      mimeType: MimeType.json,
    );
  }

  Future<void> saveExcel(String name, Map<String, dynamic> dataset) async {
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet();
    if (defaultName != null) excel.rename(defaultName, 'Overview');
    excel['Overview'].appendRow([
      TextCellValue(name),
      TextCellValue(DateTime.now().toIso8601String()),
    ]);
    final overview = _flatten({
      for (final entry in dataset.entries)
        if (entry.value is! List) entry.key: entry.value,
    });
    for (final entry in overview.entries) {
      excel['Overview'].appendRow([
        TextCellValue(entry.key),
        TextCellValue(entry.value?.toString() ?? ''),
      ]);
    }
    for (final entry in dataset.entries) {
      final data = entry.value;
      if (data is! List || data.isEmpty) continue;
      final rows = data
          .whereType<Map>()
          .map((r) => _flatten(Map<String, dynamic>.from(r)))
          .toList();
      final columns = rows.expand((r) => r.keys).toSet().toList();
      final sheet =
          excel[entry.key
              .replaceAll('_', ' ')
              .substring(0, entry.key.length > 30 ? 30 : entry.key.length)];
      sheet.appendRow(columns.map(TextCellValue.new).toList());
      for (final row in rows) {
        sheet.appendRow(
          columns.map((key) {
            final value = row[key];
            if (value is bool) return BoolCellValue(value);
            if (value is int) return IntCellValue(value);
            if (value is num) return DoubleCellValue(value.toDouble());
            final text = value?.toString() ?? '';
            if (text.length > 32767) {
              throw StateError(
                'A saved field exceeds Excel’s cell limit. Use the complete JSON export.',
              );
            }
            return TextCellValue(text);
          }).toList(),
        );
      }
    }
    final bytes = excel.save();
    if (bytes == null) throw StateError('Could not generate the report.');
    await FileSaver.instance.saveFile(
      name: name,
      bytes: Uint8List.fromList(bytes),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  Future<void> printDataset(String title, Map<String, dynamic> dataset) async {
    final document = pw.Document();
    final widgets = <pw.Widget>[
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 12),
    ];
    void walk(String key, dynamic value) {
      if (value is Map) {
        widgets.add(
          pw.Text(
            key.replaceAll('_', ' '),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        );
        for (final entry in value.entries) {
          walk('${entry.key}', entry.value);
        }
      } else if (value is List) {
        widgets.add(
          pw.Text(
            key.replaceAll('_', ' '),
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        );
        for (var i = 0; i < value.length; i++) {
          walk('${key.replaceAll('_', ' ')} ${i + 1}', value[i]);
          widgets.add(pw.SizedBox(height: 8));
        }
      } else {
        final text = '${key.replaceAll('_', ' ')}: ${value ?? '—'}';
        for (var start = 0; start < text.length; start += 600) {
          widgets.add(
            pw.Text(
              text.substring(
                start,
                start + 600 > text.length ? text.length : start + 600,
              ),
              style: const pw.TextStyle(fontSize: 9),
            ),
          );
        }
      }
    }

    for (final entry in dataset.entries) {
      walk(entry.key, entry.value);
    }
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        build: (_) => widgets,
      ),
    );
    final bytes = await document.save();
    await Printing.layoutPdf(name: title, onLayout: (_) async => bytes);
  }
}
