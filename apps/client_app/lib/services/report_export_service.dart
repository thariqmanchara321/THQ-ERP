import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportExportService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Map<String, dynamic>> dataset({
    required String tenantId,
    required DateTime from,
    required DateTime to,
    String? locationId,
  }) async {
    final results = await Future.wait<dynamic>([
      _supabase.rpc(
        'reports_export_dataset_v44',
        params: {
          'p_tenant_id': tenantId,
          'p_from': DateFormat('yyyy-MM-dd').format(from),
          'p_to': DateFormat('yyyy-MM-dd').format(to),
          'p_location_id': locationId,
        },
      ),
      _supabase.rpc(
        'returns_register_v45',
        params: {
          'p_tenant_id': tenantId,
          'p_from': DateFormat('yyyy-MM-dd').format(from),
          'p_to': DateFormat('yyyy-MM-dd').format(to),
          'p_location_id': locationId,
          'p_type': 'all',
          'p_query': null,
        },
      ),
    ]);
    final base = results.first is Map
        ? Map<String, dynamic>.from(results.first as Map)
        : <String, dynamic>{};
    base['returns'] = results[1] is List ? results[1] : const <dynamic>[];
    return base;
  }

  Future<void> saveExcel({
    required String tenantId,
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? locationLabel,
  }) async {
    final data = await dataset(
      tenantId: tenantId,
      from: from,
      to: to,
      locationId: locationId,
    );
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Summary') {
      excel.rename(defaultSheet, 'Summary');
    }

    _writeSummarySheet(
      excel['Summary'],
      businessName: businessName,
      currencyCode: currencyCode,
      from: from,
      to: to,
      locationLabel: locationLabel,
      summary: _map(data['summary']),
      gst: _map(data['gst']),
    );
    _writeRows(excel['Sales'], _rows(data['sales']));
    _writeRows(excel['Purchases'], _rows(data['purchases']));
    _writeRows(excel['Expenses'], _rows(data['expenses']));
    _writeRows(excel['Returns'], _rows(data['returns']));
    _writeRows(excel['Top Products'], _rows(data['top_products']));
    _writeRows(excel['Top Customers'], _rows(data['top_customers']));

    final raw = excel.save();
    if (raw == null) throw Exception('Could not generate XLSX report.');
    final bytes = Uint8List.fromList(raw);
    final name = _fileBase(businessName, from, to);
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    await _log(tenantId, 'summary', 'xlsx', from, to, locationId);
  }

  Future<Uint8List> buildPdf({
    required String tenantId,
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? locationLabel,
  }) async {
    final data = await dataset(
      tenantId: tenantId,
      from: from,
      to: to,
      locationId: locationId,
    );
    final summary = _map(data['summary']);
    final gst = _map(data['gst']);
    final sales = _rows(data['sales']);
    final purchases = _rows(data['purchases']);
    final expenses = _rows(data['expenses']);
    final returns = _rows(data['returns']);
    final topProducts = _rows(data['top_products']);
    final topCustomers = _rows(data['top_customers']);
    final document = pw.Document();
    final period =
        '${DateFormat('dd MMM yyyy').format(from)} – ${DateFormat('dd MMM yyyy').format(to)}';

    String money(dynamic value) {
      final amount = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0;
      return '$currencyCode ${amount.toStringAsFixed(2)}';
    }

    final metrics = <List<String>>[
      ['Sales', money(summary['sales'])],
      ['Purchases', money(summary['purchases'])],
      ['Expenses', money(summary['expenses'])],
      ['Gross profit', money(summary['gross_profit'])],
      ['Net profit', money(summary['net_profit'])],
      ['Receivables', money(summary['receivables'])],
      ['Payables', money(summary['payables'])],
      ['Stock value', money(summary['stock_value'])],
      ['Output GST', money(gst['output_gst'])],
      ['Input GST', money(gst['input_gst'])],
      ['Net GST payable', money(gst['net_gst_payable'])],
    ];

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              businessName,
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'THQ Business Report • $period${locationLabel == null || locationLabel.isEmpty ? '' : ' • $locationLabel'}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        build: (_) => [
          _pdfSectionTitle('Summary'),
          pw.TableHelper.fromTextArray(
            headers: const ['Metric', 'Value'],
            data: metrics,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 16),
          if (topProducts.isNotEmpty) ...[
            _pdfSectionTitle('Top products'),
            _pdfDynamicTable(
              topProducts,
              preferred: const [
                'product_name',
                'sku',
                'quantity',
                'revenue',
                'gross_profit',
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          if (topCustomers.isNotEmpty) ...[
            _pdfSectionTitle('Top customers'),
            _pdfDynamicTable(
              topCustomers,
              preferred: const [
                'customer_name',
                'sale_count',
                'revenue',
                'balance_due',
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          if (sales.isNotEmpty) ...[
            _pdfSectionTitle('Sales register'),
            _pdfDynamicTable(
              sales,
              preferred: const [
                'reference',
                'sale_number',
                'sale_date',
                'customer_name',
                'grand_total',
                'status',
                'location_name',
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          if (purchases.isNotEmpty) ...[
            _pdfSectionTitle('Purchase register'),
            _pdfDynamicTable(
              purchases,
              preferred: const [
                'reference',
                'purchase_number',
                'purchase_date',
                'supplier_name',
                'grand_total',
                'status',
                'location_name',
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          if (expenses.isNotEmpty) ...[
            _pdfSectionTitle('Expenses'),
            _pdfDynamicTable(
              expenses,
              preferred: const [
                'expense_number',
                'expense_date',
                'category_name',
                'payee',
                'total_amount',
                'status',
                'location_name',
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          if (returns.isNotEmpty) ...[
            _pdfSectionTitle('Sales & purchase returns'),
            _pdfDynamicTable(
              returns,
              preferred: const [
                'return_type',
                'return_number',
                'return_date',
                'reference',
                'party',
                'grand_total',
                'status',
                'location_name',
              ],
            ),
          ],
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
      ),
    );
    return document.save();
  }

  Future<void> savePdf({
    required String tenantId,
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? locationLabel,
  }) async {
    final bytes = await buildPdf(
      tenantId: tenantId,
      businessName: businessName,
      currencyCode: currencyCode,
      from: from,
      to: to,
      locationId: locationId,
      locationLabel: locationLabel,
    );
    await FileSaver.instance.saveFile(
      name: _fileBase(businessName, from, to),
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
    await _log(tenantId, 'summary', 'pdf', from, to, locationId);
  }

  Future<void> printReport({
    required String tenantId,
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationId,
    String? locationLabel,
  }) async {
    final bytes = await buildPdf(
      tenantId: tenantId,
      businessName: businessName,
      currencyCode: currencyCode,
      from: from,
      to: to,
      locationId: locationId,
      locationLabel: locationLabel,
    );
    await Printing.layoutPdf(
      name: '${businessName}_report.pdf',
      onLayout: (_) async => bytes,
    );
    await _log(tenantId, 'summary', 'print', from, to, locationId);
  }

  void _writeSummarySheet(
    Sheet sheet, {
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    required String? locationLabel,
    required Map<String, dynamic> summary,
    required Map<String, dynamic> gst,
  }) {
    sheet.appendRow([TextCellValue('THQ Business Report')]);
    sheet.appendRow([TextCellValue('Business'), TextCellValue(businessName)]);
    sheet.appendRow([
      TextCellValue('Period'),
      TextCellValue(
        '${DateFormat('yyyy-MM-dd').format(from)} to ${DateFormat('yyyy-MM-dd').format(to)}',
      ),
    ]);
    sheet.appendRow([
      TextCellValue('Location'),
      TextCellValue(
        locationLabel?.isNotEmpty == true ? locationLabel! : 'All Stores',
      ),
    ]);
    sheet.appendRow([TextCellValue('Currency'), TextCellValue(currencyCode)]);
    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
    final merged = <String, dynamic>{...summary, ...gst};
    const preferred = [
      'sales',
      'sales_tax',
      'purchases',
      'purchase_tax',
      'expenses',
      'gross_profit',
      'net_profit',
      'receivables',
      'payables',
      'stock_value',
      'taxable_sales',
      'output_gst',
      'taxable_purchases',
      'input_gst',
      'net_gst_payable',
      'sale_count',
      'purchase_count',
      'expense_count',
    ];
    for (final key in preferred) {
      if (!merged.containsKey(key)) continue;
      sheet.appendRow([TextCellValue(_label(key)), _cell(merged[key])]);
    }
  }

  void _writeRows(Sheet sheet, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      sheet.appendRow([TextCellValue('No records')]);
      return;
    }
    final keys = <String>[];
    for (final row in rows) {
      for (final key in row.keys) {
        if (!keys.contains(key)) keys.add(key);
      }
    }
    sheet.appendRow(keys.map((e) => TextCellValue(_label(e))).toList());
    for (final row in rows) {
      sheet.appendRow(keys.map((key) => _cell(row[key])).toList());
    }
  }

  CellValue _cell(dynamic value) {
    if (value == null) return TextCellValue('');
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    if (value is bool) return BoolCellValue(value);
    return TextCellValue(value.toString());
  }

  pw.Widget _pdfSectionTitle(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
  );

  pw.Widget _pdfDynamicTable(
    List<Map<String, dynamic>> rows, {
    required List<String> preferred,
  }) {
    if (rows.isEmpty) return pw.SizedBox();
    final available = <String>{};
    for (final row in rows) {
      available.addAll(row.keys);
    }
    var keys = preferred.where(available.contains).toList();
    if (keys.isEmpty) keys = available.take(7).toList();
    final data = rows
        .take(150)
        .map((row) => keys.map((key) => _short(row[key])).toList())
        .toList();
    return pw.TableHelper.fromTextArray(
      headers: keys.map(_label).toList(),
      data: data,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 6.5),
      cellPadding: const pw.EdgeInsets.all(3),
    );
  }

  Future<void> _log(
    String tenantId,
    String reportKey,
    String format,
    DateTime from,
    DateTime to,
    String? locationId,
  ) async {
    try {
      await _supabase.rpc(
        'report_export_log_v44',
        params: {
          'p_tenant_id': tenantId,
          'p_report_key': reportKey,
          'p_format': format,
          'p_from': DateFormat('yyyy-MM-dd').format(from),
          'p_to': DateFormat('yyyy-MM-dd').format(to),
          'p_location_id': locationId,
          'p_device_id': null,
        },
      );
    } catch (_) {
      // The file is already generated; telemetry must never block the user.
    }
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  String _fileBase(String businessName, DateTime from, DateTime to) =>
      '${businessName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_Report_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}';
  String _label(String key) => key
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
  String _short(dynamic value) {
    final text = value?.toString() ?? '';
    return text.length <= 34 ? text : '${text.substring(0, 31)}...';
  }
}
