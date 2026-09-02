import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class TerminalDayExportService {
  Future<Uint8List> buildPdf({
    required String businessName,
    required String terminalLabel,
    required DateTime day,
    required String currency,
    required Map<String, dynamic> data,
  }) async {
    String money(dynamic value) {
      final amount = value is num
          ? value.toDouble()
          : double.tryParse('$value') ?? 0;
      return '$currency ${amount.toStringAsFixed(2)}';
    }

    final shift = data['shift_summary'] is Map
        ? Map<String, dynamic>.from(data['shift_summary'] as Map)
        : <String, dynamic>{};
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(
            businessName,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Terminal Daily Summary • ${DateFormat('dd MMM yyyy').format(day)} • $terminalLabel',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Read-only report. Cashier shifts are managed separately.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          _pdfSection('Sales', [
            ['Invoices', '${data['invoice_count'] ?? 0}'],
            ['Gross sales', money(data['gross_sales'])],
            ['Discount', money(data['sales_discount'])],
            ['Tax', money(data['sales_tax'])],
            ['Sales returns', money(data['sales_returns'])],
            ['Net sales', money(data['net_sales'])],
            ['Invoice payments', money(data['sales_paid'])],
            ['Current outstanding', money(data['sales_outstanding'])],
            ['Held invoices', '${data['held_count'] ?? 0}'],
          ]),
          pw.SizedBox(height: 12),
          _pdfSection('Collections & Payments', [
            ['Cash sales', money(data['cash'])],
            ['UPI sales', money(data['upi'])],
            ['Card sales', money(data['card'])],
            ['Bank sales', money(data['bank'])],
            ['Other sales payments', money(data['other_payments'])],
            ['Customer receipts', money(data['customer_receipts'])],
            ['Total collected', money(data['total_collected'])],
          ]),
          pw.SizedBox(height: 12),
          _pdfSection('Other Terminal Activity', [
            ['Purchases', money(data['purchases'])],
            ['Purchase count', '${data['purchase_count'] ?? 0}'],
            ['Purchase discount', money(data['purchase_discount'])],
            ['Purchase tax', money(data['purchase_tax'])],
            ['Purchase returns', money(data['purchase_returns'])],
            ['Net purchases', money(data['net_purchases'])],
            ['Purchase paid', money(data['purchase_paid'])],
            ['Purchase outstanding', money(data['purchase_outstanding'])],
            ['Expenses', money(data['expenses'])],
            ['Cash in', money(data['cash_in'])],
            ['Cash out', money(data['cash_out'])],
          ]),
          pw.SizedBox(height: 12),
          _pdfSection('Customer Receipt Breakdown', [
            ['Cash', money(data['customer_receipts_cash'])],
            ['UPI', money(data['customer_receipts_upi'])],
            ['Card', money(data['customer_receipts_card'])],
            ['Bank', money(data['customer_receipts_bank'])],
            ['Other', money(data['customer_receipts_other'])],
          ]),
          pw.SizedBox(height: 12),
          _pdfSection('Cashier Shift Summary', [
            ['Shift count', '${shift['shift_count'] ?? 0}'],
            ['Still open', '${shift['open_shift_count'] ?? 0}'],
            ['First start', _timestamp(shift['first_start'])],
            ['Last end', _timestamp(shift['last_end'])],
            ['Opening cash', money(shift['opening_cash'])],
            ['Closing cash', money(shift['closing_cash'])],
            ['Difference', money(shift['difference'])],
          ]),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfSection(String title, List<List<String>> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.TableHelper.fromTextArray(
          headers: const ['Metric', 'Value'],
          data: rows,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
        ),
      ],
    );
  }

  Future<void> savePdf({
    required String businessName,
    required String terminalLabel,
    required DateTime day,
    required String currency,
    required Map<String, dynamic> data,
  }) async {
    final bytes = await buildPdf(
      businessName: businessName,
      terminalLabel: terminalLabel,
      day: day,
      currency: currency,
      data: data,
    );
    await FileSaver.instance.saveFile(
      name: 'Terminal_Daily_${DateFormat('yyyyMMdd').format(day)}',
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> saveExcel({
    required String businessName,
    required String terminalLabel,
    required DateTime day,
    required Map<String, dynamic> data,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Summary') {
      excel.rename(defaultSheet, 'Summary');
    }
    final summary = excel['Summary'];
    summary.appendRow([TextCellValue('THQ Terminal Daily Summary')]);
    summary.appendRow([TextCellValue('Business'), TextCellValue(businessName)]);
    summary.appendRow([
      TextCellValue('Terminal'),
      TextCellValue(terminalLabel),
    ]);
    summary.appendRow([
      TextCellValue('Date'),
      TextCellValue(DateFormat('yyyy-MM-dd').format(day)),
    ]);
    summary.appendRow([
      TextCellValue('Mode'),
      TextCellValue('Read-only report'),
    ]);

    void section(String title, List<String> keys) {
      summary.appendRow([]);
      summary.appendRow([TextCellValue(title)]);
      summary.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
      for (final key in keys) {
        summary.appendRow([TextCellValue(_label(key)), _cell(data[key])]);
      }
    }

    section('Sales', [
      'invoice_count',
      'gross_sales',
      'sales_discount',
      'sales_tax',
      'sales_returns',
      'net_sales',
      'sales_paid',
      'sales_outstanding',
      'held_count',
    ]);
    section('Collections & Payments', [
      'cash',
      'upi',
      'card',
      'bank',
      'other_payments',
      'customer_receipts',
      'total_collected',
    ]);
    section('Other Terminal Activity', [
      'purchases',
      'purchase_count',
      'purchase_discount',
      'purchase_tax',
      'purchase_returns',
      'net_purchases',
      'purchase_paid',
      'purchase_outstanding',
      'expenses',
      'cash_in',
      'cash_out',
    ]);
    section('Customer Receipt Breakdown', [
      'customer_receipts_cash',
      'customer_receipts_upi',
      'customer_receipts_card',
      'customer_receipts_bank',
      'customer_receipts_other',
    ]);

    final shift = data['shift_summary'] is Map
        ? Map<String, dynamic>.from(data['shift_summary'] as Map)
        : <String, dynamic>{};
    if (shift.isNotEmpty) {
      summary.appendRow([]);
      summary.appendRow([TextCellValue('Cashier Shift Summary')]);
      summary.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
      for (final key in [
        'shift_count',
        'open_shift_count',
        'first_start',
        'last_end',
        'opening_cash',
        'closing_cash',
        'difference',
      ]) {
        summary.appendRow([TextCellValue(_label(key)), _cell(shift[key])]);
      }
    }

    final bytes = excel.save();
    if (bytes == null) throw Exception('Could not generate Excel report.');
    await FileSaver.instance.saveFile(
      name: 'Terminal_Daily_${DateFormat('yyyyMMdd').format(day)}',
      bytes: Uint8List.fromList(bytes),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  Future<void> printReport({
    required String businessName,
    required String terminalLabel,
    required DateTime day,
    required String currency,
    required Map<String, dynamic> data,
  }) async {
    final bytes = await buildPdf(
      businessName: businessName,
      terminalLabel: terminalLabel,
      day: day,
      currency: currency,
      data: data,
    );
    await Printing.layoutPdf(
      name: 'Terminal Daily ${DateFormat('yyyy-MM-dd').format(day)}',
      onLayout: (_) async => bytes,
    );
  }

  CellValue _cell(dynamic value) {
    if (value == null) return TextCellValue('');
    if (value is int) return IntCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue(value.toString());
  }

  String _label(String key) => key
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');

  static String _timestamp(dynamic value) {
    if (value == null) return '-';
    final parsed = DateTime.tryParse(value.toString())?.toLocal();
    return parsed == null
        ? value.toString()
        : DateFormat('dd MMM yyyy hh:mm a').format(parsed);
  }
}
