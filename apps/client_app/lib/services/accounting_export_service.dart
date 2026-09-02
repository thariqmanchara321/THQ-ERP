import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/accounting_summary.dart';

class AccountingExportService {
  String _safe(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  String _fileName(
    String business,
    String section,
    DateTime from,
    DateTime to,
  ) {
    final d = DateFormat('yyyyMMdd');
    return '${_safe(business)}_${_safe(section)}_${d.format(from)}_${d.format(to)}';
  }

  List<Map<String, dynamic>> _statementRows(Map<String, dynamic> statement) =>
      (statement['rows'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  List<List<String>> _summaryRows(
    AccountingSummary? summary,
    Map<String, dynamic> gst,
    String currency,
  ) {
    if (summary == null) return const [];
    String money(dynamic value) {
      final n = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0;
      return '$currency ${n.toStringAsFixed(2)}';
    }

    return [
      ['Revenue', money(summary.revenue)],
      ['COGS', money(summary.costOfGoodsSold)],
      ['Gross Profit', money(summary.grossProfit)],
      ['Operating Expenses', money(summary.operatingExpenses)],
      ['Net Profit', money(summary.netOperatingProfit)],
      ['Receivables', money(summary.receivables)],
      ['Payables', money(summary.payables)],
      ['Inventory', money(summary.inventoryValue)],
      ['Taxable Sales', money(gst['taxable_sales'])],
      ['Output GST', money(gst['output_gst'])],
      ['Input GST', money(gst['input_gst'])],
      ['Net GST', money(gst['net_gst_payable'])],
    ];
  }

  List<Map<String, dynamic>> _rowsFor({
    required String section,
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic> statement,
  }) {
    if (section == 'accounts') return accounts;
    if (const {
      'trial_balance',
      'profit_loss',
      'balance_sheet',
      'cash_flow',
    }.contains(section)) {
      return _statementRows(statement);
    }
    return rows;
  }

  List<String> _columns(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const [];
    const preferred = [
      'entry_date',
      'date',
      'reference',
      'invoice_number',
      'sale_number',
      'purchase_number',
      'code',
      'name',
      'account_name',
      'party_name',
      'description',
      'account_type',
      'debit',
      'credit',
      'balance',
      'amount',
      'inflow',
      'outflow',
      'net_change',
      'status',
    ];
    final keys = <String>{};
    for (final row in rows.take(100)) {
      for (final key in row.keys) {
        final value = row[key];
        if (value is! Map && value is! List) keys.add(key);
      }
    }
    final ordered = <String>[
      ...preferred.where(keys.remove),
      ...keys.toList()..sort(),
    ];
    return ordered.take(12).toList();
  }

  String _value(dynamic value) {
    if (value == null) return '';
    if (value is num) return value.toStringAsFixed(2);
    final text = value.toString();
    return text.length > 80 ? '${text.substring(0, 77)}…' : text;
  }

  Future<Uint8List> buildPdf({
    required String businessName,
    required String currencyCode,
    required String section,
    required String sectionLabel,
    required DateTime from,
    required DateTime to,
    required AccountingSummary? summary,
    required Map<String, dynamic> gst,
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic> statement,
  }) async {
    final doc = pw.Document();
    final period =
        '${DateFormat('dd MMM yyyy').format(from)} – ${DateFormat('dd MMM yyyy').format(to)}';
    final sourceRows = _rowsFor(
      section: section,
      accounts: accounts,
      rows: rows,
      statement: statement,
    );
    final columns = _columns(sourceRows);
    final statementSummary = statement['summary'] is Map
        ? Map<String, dynamic>.from(statement['summary'] as Map)
        : const <String, dynamic>{};

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              businessName,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '$sectionLabel • $period',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) {
          if (section == 'overview') {
            return [
              pw.TableHelper.fromTextArray(
                headers: const ['Metric', 'Value'],
                data: _summaryRows(summary, gst, currencyCode),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.indigo700,
                ),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
                cellStyle: const pw.TextStyle(fontSize: 8),
              ),
            ];
          }
          final widgets = <pw.Widget>[];
          if (statementSummary.isNotEmpty) {
            widgets.add(
              pw.Wrap(
                spacing: 12,
                runSpacing: 6,
                children: statementSummary.entries
                    .where(
                      (entry) => entry.value is! Map && entry.value is! List,
                    )
                    .map(
                      (entry) => pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(3),
                        ),
                        child: pw.Text(
                          '${entry.key.replaceAll('_', ' ')}: ${_value(entry.value)}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
            widgets.add(pw.SizedBox(height: 10));
          }
          if (sourceRows.isEmpty || columns.isEmpty) {
            widgets.add(pw.Text('No records in this period.'));
          } else {
            widgets.add(
              pw.TableHelper.fromTextArray(
                headers: columns
                    .map((key) => key.replaceAll('_', ' ').toUpperCase())
                    .toList(),
                data: sourceRows
                    .map(
                      (row) => columns.map((key) => _value(row[key])).toList(),
                    )
                    .toList(),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.indigo700,
                ),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 7,
                ),
                cellStyle: const pw.TextStyle(fontSize: 6.6),
                cellPadding: const pw.EdgeInsets.all(3),
              ),
            );
          }
          return widgets;
        },
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ),
      ),
    );
    return doc.save();
  }

  Future<void> printReport({required Uint8List bytes, required String name}) =>
      Printing.layoutPdf(name: name, onLayout: (_) async => bytes);

  Future<void> savePdf({
    required Uint8List bytes,
    required String businessName,
    required String section,
    required DateTime from,
    required DateTime to,
  }) => FileSaver.instance.saveFile(
    name: _fileName(businessName, section, from, to),
    bytes: bytes,
    fileExtension: 'pdf',
    mimeType: MimeType.pdf,
  );

  Future<void> saveExcel({
    required String businessName,
    required String currencyCode,
    required String section,
    required String sectionLabel,
    required DateTime from,
    required DateTime to,
    required AccountingSummary? summary,
    required Map<String, dynamic> gst,
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic> statement,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Accounting') {
      excel.rename(defaultSheet, 'Accounting');
    }
    final sheet = excel['Accounting'];
    sheet.appendRow([TextCellValue(businessName)]);
    sheet.appendRow([TextCellValue(sectionLabel)]);
    sheet.appendRow([
      TextCellValue(
        '${DateFormat('dd MMM yyyy').format(from)} - ${DateFormat('dd MMM yyyy').format(to)}',
      ),
    ]);
    sheet.appendRow(<CellValue?>[]);
    if (section == 'overview') {
      sheet.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
      for (final row in _summaryRows(summary, gst, currencyCode)) {
        sheet.appendRow(row.map((value) => TextCellValue(value)).toList());
      }
    } else {
      final sourceRows = _rowsFor(
        section: section,
        accounts: accounts,
        rows: rows,
        statement: statement,
      );
      final columns = _columns(sourceRows);
      if (columns.isNotEmpty) {
        sheet.appendRow(
          columns
              .map((key) => TextCellValue(key.replaceAll('_', ' ')))
              .toList(),
        );
        for (final row in sourceRows) {
          sheet.appendRow(
            columns.map((key) => TextCellValue(_value(row[key]))).toList(),
          );
        }
      }
    }
    final raw = excel.save();
    if (raw == null) throw Exception('Could not generate accounting workbook.');
    await FileSaver.instance.saveFile(
      name: _fileName(businessName, section, from, to),
      bytes: Uint8List.fromList(raw),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }
}
