import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class DailyAccountsExportService {
  final DateFormat _dateFormat = DateFormat('dd-MM-yyyy');
  final DateFormat _timeFormat = DateFormat('dd-MM-yyyy HH:mm');

  String _safe(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  String _pdfCurrency(String code) {
    if (code == '₹' || code == 'INR') return 'INR';
    return code;
  }

  String _m(num value, String currency) {
    return '$currency ${value.toStringAsFixed(2)}';
  }

  Uint8List buildExcel({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> data,
    bool activeOnly = true,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Closing Statement') {
      excel.rename(defaultSheet, 'Closing Statement');
    }

    final cash = Map<String, dynamic>.from(data['cash'] as Map? ?? {});
    final bank = Map<String, dynamic>.from(data['bank'] as Map? ?? {});
    final sales = Map<String, dynamic>.from(data['sales'] as Map? ?? {});
    final purchases = Map<String, dynamic>.from(data['purchases'] as Map? ?? {});
    final receipts = Map<String, dynamic>.from(data['receipts'] as Map? ?? {});
    final payments = Map<String, dynamic>.from(data['payments'] as Map? ?? {});
    final receivables = Map<String, dynamic>.from(data['receivables'] as Map? ?? {});
    final payables = Map<String, dynamic>.from(data['payables'] as Map? ?? {});
    final rawJournals = (data['day_journals'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final journals = activeOnly
        ? rawJournals.where((j) => (j['status']?.toString() ?? 'posted') == 'posted').toList()
        : rawJournals;
    final exceptions = (data['exceptions'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    // 1. Closing Statement Sheet
    final statementSheet = excel['Closing Statement'];
    statementSheet.appendRow([TextCellValue('THQ ERP - DAILY DETAILED ACCOUNTS REPORT')]);
    statementSheet.appendRow([TextCellValue('Business: $businessName')]);
    statementSheet.appendRow([
      TextCellValue('Period: ${_dateFormat.format(from)} to ${_dateFormat.format(to)}'),
    ]);
    statementSheet.appendRow([TextCellValue('Store / Location: ${locationLabel ?? 'All Stores'}')]);
    statementSheet.appendRow([
      TextCellValue('Journal Scope: ${activeOnly ? 'Active Only (Excludes Reversed)' : 'Full Audit History (Includes Reversed)'}'),
    ]);
    statementSheet.appendRow([TextCellValue('Generated At: ${_timeFormat.format(DateTime.now())}')]);
    statementSheet.appendRow([
      TextCellValue('Reconciliation Status: ${data['reconciliation_status'] ?? 'Passed'}'),
    ]);
    statementSheet.appendRow([TextCellValue('')]);
    statementSheet.appendRow([
      TextCellValue('Closing Statement:'),
      TextCellValue(data['closing_statement']?.toString() ?? ''),
    ]);
    statementSheet.appendRow([TextCellValue('')]);
    statementSheet.appendRow([TextCellValue('Core Account Summary'), TextCellValue('Value ($currencyCode)')]);
    statementSheet.appendRow([
      TextCellValue('Opening Cash Balance'),
      DoubleCellValue((cash['opening'] as num? ?? 0).toDouble()),
    ]);
    statementSheet.appendRow([
      TextCellValue('Closing Cash Balance'),
      DoubleCellValue((cash['closing'] as num? ?? 0).toDouble()),
    ]);
    statementSheet.appendRow([
      TextCellValue('Net Cash Movement'),
      DoubleCellValue((cash['net_movement'] as num? ?? 0).toDouble()),
    ]);
    statementSheet.appendRow([
      TextCellValue('Opening Bank Balance'),
      DoubleCellValue((bank['opening'] as num? ?? 0).toDouble()),
    ]);
    statementSheet.appendRow([
      TextCellValue('Closing Bank Balance'),
      DoubleCellValue((bank['closing'] as num? ?? 0).toDouble()),
    ]);
    statementSheet.appendRow([
      TextCellValue('Net Bank Movement'),
      DoubleCellValue((bank['net_movement'] as num? ?? 0).toDouble()),
    ]);

    // 2. Operational Activity Sheet
    final activitySheet = excel['Operational Activity'];
    activitySheet.appendRow([TextCellValue('Activity Metric'), TextCellValue('Amount / Count')]);
    activitySheet.appendRow([
      TextCellValue('Total Sales Value'),
      DoubleCellValue((sales['total'] as num? ?? 0).toDouble()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Sales Invoices Count'),
      IntCellValue((sales['count'] as num? ?? 0).toInt()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Cash Sales'),
      DoubleCellValue((sales['cash'] as num? ?? 0).toDouble()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Credit Sales (Due)'),
      DoubleCellValue((sales['credit'] as num? ?? 0).toDouble()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Bank / Online Sales'),
      DoubleCellValue((sales['bank'] as num? ?? 0).toDouble()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Total Purchases Value'),
      DoubleCellValue((purchases['total'] as num? ?? 0).toDouble()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Purchases Bills Count'),
      IntCellValue((purchases['count'] as num? ?? 0).toInt()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Customer Receipts Received'),
      DoubleCellValue((receipts['customer_receipts'] as num? ?? 0).toDouble()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Supplier Payments Disbursed'),
      DoubleCellValue((payments['supplier_payments'] as num? ?? 0).toDouble()),
    ]);
    activitySheet.appendRow([
      TextCellValue('Operating Expenses Paid'),
      DoubleCellValue((payments['operating_expenses'] as num? ?? 0).toDouble()),
    ]);

    // 3. Receivables & Payables Sheet
    final arApSheet = excel['Receivables & Payables'];
    arApSheet.appendRow([
      TextCellValue('Balance Category'),
      TextCellValue('Opening ($currencyCode)'),
      TextCellValue('Closing ($currencyCode)'),
      TextCellValue('Net Movement ($currencyCode)'),
    ]);
    arApSheet.appendRow([
      TextCellValue('Customer Receivables (AR)'),
      DoubleCellValue((receivables['opening'] as num? ?? 0).toDouble()),
      DoubleCellValue((receivables['closing'] as num? ?? 0).toDouble()),
      DoubleCellValue((receivables['net_movement'] as num? ?? 0).toDouble()),
    ]);
    arApSheet.appendRow([
      TextCellValue('Supplier Payables (AP)'),
      DoubleCellValue((payables['opening'] as num? ?? 0).toDouble()),
      DoubleCellValue((payables['closing'] as num? ?? 0).toDouble()),
      DoubleCellValue((payables['net_movement'] as num? ?? 0).toDouble()),
    ]);

    // 4. Day Journals Sheet
    final journalsSheet = excel['Day Journals'];
    journalsSheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Description'),
      TextCellValue('Party / Payee'),
      TextCellValue('Financial Effect'),
      TextCellValue('Debit ($currencyCode)'),
      TextCellValue('Credit ($currencyCode)'),
      TextCellValue('Posting Status'),
      TextCellValue('Double-Entry Balance'),
      TextCellValue('Entry Number'),
      TextCellValue('Source Reference'),
    ]);
    for (final j in journals) {
      journalsSheet.appendRow([
        TextCellValue(j['entry_date']?.toString() ?? ''),
        TextCellValue(j['description']?.toString() ?? ''),
        TextCellValue(j['party_name']?.toString() ?? ''),
        TextCellValue(j['financial_effect']?.toString() ?? ''),
        DoubleCellValue((j['debit_total'] as num? ?? 0).toDouble()),
        DoubleCellValue((j['credit_total'] as num? ?? 0).toDouble()),
        TextCellValue((j['status']?.toString() ?? 'posted').toUpperCase()),
        TextCellValue(j['is_balanced'] == true ? 'Balanced' : 'Unbalanced'),
        TextCellValue(j['entry_number']?.toString() ?? ''),
        TextCellValue(j['reference']?.toString() ?? ''),
      ]);
    }

    // 5. Exceptions Sheet
    if (exceptions.isNotEmpty) {
      final excSheet = excel['Exceptions'];
      excSheet.appendRow([
        TextCellValue('Type'),
        TextCellValue('Reference'),
        TextCellValue('Description / Note'),
      ]);
      for (final e in exceptions) {
        excSheet.appendRow([
          TextCellValue(e['type']?.toString() ?? ''),
          TextCellValue(e['reference']?.toString() ?? ''),
          TextCellValue(e['note']?.toString() ?? ''),
        ]);
      }
    }

    final bytes = excel.encode();
    return Uint8List.fromList(bytes ?? const []);
  }

  Future<void> saveExcel({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> data,
    bool activeOnly = true,
  }) async {
    final bytes = buildExcel(
      businessName: businessName,
      currencyCode: currencyCode,
      from: from,
      to: to,
      locationLabel: locationLabel,
      data: data,
      activeOnly: activeOnly,
    );
    if (bytes.isNotEmpty) {
      final filename =
          '${_safe(businessName)}_Daily_Accounts_${_dateFormat.format(from)}_${_dateFormat.format(to)}';
      await FileSaver.instance.saveFile(
        name: filename,
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  Future<Uint8List> buildPdf({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> data,
    bool activeOnly = true,
  }) async {
    final pdf = pw.Document();

    final safeCurrency = _pdfCurrency(currencyCode);
    final cash = Map<String, dynamic>.from(data['cash'] as Map? ?? {});
    final bank = Map<String, dynamic>.from(data['bank'] as Map? ?? {});
    final sales = Map<String, dynamic>.from(data['sales'] as Map? ?? {});
    final purchases = Map<String, dynamic>.from(data['purchases'] as Map? ?? {});
    final receipts = Map<String, dynamic>.from(data['receipts'] as Map? ?? {});
    final payments = Map<String, dynamic>.from(data['payments'] as Map? ?? {});
    final receivables = Map<String, dynamic>.from(data['receivables'] as Map? ?? {});
    final payables = Map<String, dynamic>.from(data['payables'] as Map? ?? {});
    final rawJournals = (data['day_journals'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final journals = activeOnly
        ? rawJournals.where((j) => (j['status']?.toString() ?? 'posted') == 'posted').toList()
        : rawJournals;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    businessName,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                  pw.Text(
                    'DAILY DETAILED ACCOUNTS REPORT',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo700,
                    ),
                  ),
                  pw.Text(
                    'Store: ${locationLabel ?? 'All Stores'} | Scope: ${activeOnly ? 'Active Only' : 'Audit History'}',
                    style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Period: ${_dateFormat.format(from)} to ${_dateFormat.format(to)}',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'Status: ${data['reconciliation_status'] ?? 'Passed'}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: data['reconciliation_status'] == 'Passed'
                          ? PdfColors.green800
                          : PdfColors.red800,
                    ),
                  ),
                  pw.Text(
                    'Generated: ${_timeFormat.format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 6),

          // Closing statement banner
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Text(
              data['closing_statement']?.toString() ?? '',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey900),
            ),
          ),
          pw.SizedBox(height: 10),

          // KPI Cards
          pw.Row(
            children: [
              pw.Expanded(
                child: _pdfBox(
                  'Opening Cash',
                  _m(cash['opening'] as num? ?? 0, safeCurrency),
                  'Closing: ${_m(cash['closing'] as num? ?? 0, safeCurrency)}',
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfBox(
                  'Opening Bank',
                  _m(bank['opening'] as num? ?? 0, safeCurrency),
                  'Closing: ${_m(bank['closing'] as num? ?? 0, safeCurrency)}',
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfBox(
                  'Sales (${sales['count'] ?? 0})',
                  _m(sales['total'] as num? ?? 0, safeCurrency),
                  'Cash: ${_m(sales['cash'] as num? ?? 0, safeCurrency)}',
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfBox(
                  'Purchases (${purchases['count'] ?? 0})',
                  _m(purchases['total'] as num? ?? 0, safeCurrency),
                  'Cash: ${_m(purchases['cash'] as num? ?? 0, safeCurrency)}',
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),

          // Cash & Bank Flow Table
          pw.Text(
            'CASH & BANK BALANCES MOVEMENT',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Account Group', 'Opening', 'Total Inflow', 'Total Outflow', 'Closing', 'Net Flow'],
            data: [
              [
                'Cash in Hand & Drawers',
                _m(cash['opening'] as num? ?? 0, safeCurrency),
                _m(cash['received'] as num? ?? 0, safeCurrency),
                _m(cash['paid'] as num? ?? 0, safeCurrency),
                _m(cash['closing'] as num? ?? 0, safeCurrency),
                _m(cash['net_movement'] as num? ?? 0, safeCurrency),
              ],
              [
                'Bank, UPI & Online Accounts',
                _m(bank['opening'] as num? ?? 0, safeCurrency),
                _m(bank['received'] as num? ?? 0, safeCurrency),
                _m(bank['paid'] as num? ?? 0, safeCurrency),
                _m(bank['closing'] as num? ?? 0, safeCurrency),
                _m(bank['net_movement'] as num? ?? 0, safeCurrency),
              ],
              [
                'Total Available Liquid Funds',
                _m((cash['opening'] as num? ?? 0) + (bank['opening'] as num? ?? 0), safeCurrency),
                _m((cash['received'] as num? ?? 0) + (bank['received'] as num? ?? 0), safeCurrency),
                _m((cash['paid'] as num? ?? 0) + (bank['paid'] as num? ?? 0), safeCurrency),
                _m((cash['closing'] as num? ?? 0) + (bank['closing'] as num? ?? 0), safeCurrency),
                _m((cash['net_movement'] as num? ?? 0) + (bank['net_movement'] as num? ?? 0), safeCurrency),
              ],
            ],
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 12),

          // Operational & AR/AP Activity
          pw.Text(
            'OPERATIONAL SETTLEMENTS & DEBTORS / CREDITORS',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Ledger Category', 'Opening', 'Activity Additions', 'Settlements / Receipts', 'Closing', 'Net Change'],
            data: [
              [
                'Customer Receivables (AR)',
                _m(receivables['opening'] as num? ?? 0, safeCurrency),
                _m(sales['credit'] as num? ?? 0, safeCurrency),
                _m(receipts['customer_receipts'] as num? ?? 0, safeCurrency),
                _m(receivables['closing'] as num? ?? 0, safeCurrency),
                _m(receivables['net_movement'] as num? ?? 0, safeCurrency),
              ],
              [
                'Supplier Payables (AP)',
                _m(payables['opening'] as num? ?? 0, safeCurrency),
                _m(purchases['credit'] as num? ?? 0, safeCurrency),
                _m(payments['supplier_payments'] as num? ?? 0, safeCurrency),
                _m(payables['closing'] as num? ?? 0, safeCurrency),
                _m(payables['net_movement'] as num? ?? 0, safeCurrency),
              ],
              [
                'Operating Expenses Paid',
                '-',
                _m(payments['operating_expenses'] as num? ?? 0, safeCurrency),
                '-',
                '-',
                _m(payments['operating_expenses'] as num? ?? 0, safeCurrency),
              ],
            ],
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 12),

          // Day Journals preview
          if (journals.isNotEmpty) ...[
            pw.Text(
              'DAY-WISE JOURNAL POSTINGS (${journals.length} ENTRIES - ${activeOnly ? 'ACTIVE ONLY' : 'FULL AUDIT HISTORY'})',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Description / Reference', 'Party', 'Effect', 'Debit', 'Credit', 'Posting Status', 'Balance'],
              data: journals
                  .map(
                    (j) => [
                      j['entry_date']?.toString() ?? '',
                      '${j['description'] ?? ''}${j['reference'] != null ? ' (${j['reference']})' : ''}'.trim(),
                      (j['party_name']?.toString().isNotEmpty == true) ? j['party_name'].toString() : '-',
                      j['financial_effect']?.toString() ?? 'Adjustment',
                      _m(j['debit_total'] as num? ?? 0, safeCurrency),
                      _m(j['credit_total'] as num? ?? 0, safeCurrency),
                      (j['status']?.toString() ?? 'posted').toUpperCase(),
                      j['is_balanced'] == true ? 'Balanced' : 'Unbalanced',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey600),
              cellStyle: const pw.TextStyle(fontSize: 6.5),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.center,
                7: pw.Alignment.center,
              },
            ),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> savePdf({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> data,
    bool activeOnly = true,
  }) async {
    final bytes = await buildPdf(
      businessName: businessName,
      currencyCode: currencyCode,
      from: from,
      to: to,
      locationLabel: locationLabel,
      data: data,
      activeOnly: activeOnly,
    );
    final filename =
        '${_safe(businessName)}_Daily_Accounts_${_dateFormat.format(from)}_${_dateFormat.format(to)}';
    await FileSaver.instance.saveFile(
      name: filename,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> printReport({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> data,
    bool activeOnly = true,
  }) async {
    final bytes = await buildPdf(
      businessName: businessName,
      currencyCode: currencyCode,
      from: from,
      to: to,
      locationLabel: locationLabel,
      data: data,
      activeOnly: activeOnly,
    );
    final filename =
        '${_safe(businessName)}_Daily_Accounts_${_dateFormat.format(from)}_${_dateFormat.format(to)}';
    await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }

  pw.Widget _pdfBox(String label, String value, String sub) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(sub, style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey600)),
        ],
      ),
    );
  }
}
