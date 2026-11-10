import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ExpenseReportExportService {
  final DateFormat _dateFormat = DateFormat('dd-MM-yyyy');
  final DateFormat _timeFormat = DateFormat('dd-MM-yyyy HH:mm');

  String _formatMoney(num value, String currency) {
    return '$currency ${value.toStringAsFixed(2)}';
  }

  List<Map<String, dynamic>> buildCategoryAnalysis(
    List<Map<String, dynamic>> expenses, {
    Map<String, dynamic>? prevSummary,
  }) {
    final Map<String, Map<String, dynamic>> map = {};
    double grandTotal = 0;

    for (final e in expenses) {
      final catId = e['category_id']?.toString() ?? 'other';
      final catName = e['category_name']?.toString() ?? 'Other';
      final total = (e['total_amount'] as num? ?? 0).toDouble();
      grandTotal += total;

      if (!map.containsKey(catId)) {
        map[catId] = {
          'category_id': catId,
          'category_name': catName,
          'name': catName,
          'expense_count': 0,
          'count': 0,
          'total': 0.0,
          'tax': 0.0,
          'prior_total': 0.0,
        };
      }
      map[catId]!['expense_count'] =
          (map[catId]!['expense_count'] as int) + 1;
      map[catId]!['count'] = (map[catId]!['count'] as int) + 1;
      map[catId]!['total'] = (map[catId]!['total'] as double) + total;
      map[catId]!['tax'] =
          (map[catId]!['tax'] as double) +
          (e['tax_amount'] as num? ?? 0).toDouble();
    }

    if (prevSummary != null) {
      final prevCats = (prevSummary['categories'] as List? ?? const []);
      for (final pc in prevCats) {
        final pMap = Map<String, dynamic>.from(pc as Map);
        final cId = pMap['category_id']?.toString() ?? '';
        if (map.containsKey(cId)) {
          map[cId]!['prior_total'] =
              (pMap['total'] as num? ?? 0).toDouble();
        }
      }
    }

    final list = map.values.toList();
    for (final row in list) {
      final t = row['total'] as double;
      final cnt = row['expense_count'] as int;
      row['percentage'] = grandTotal > 0 ? (t / grandTotal) * 100 : 0.0;
      row['average'] = cnt > 0 ? t / cnt : 0.0;
    }

    list.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    return list;
  }

  List<Map<String, dynamic>> buildPaymentBreakdown(
    List<Map<String, dynamic>> expenses,
  ) {
    final Map<String, Map<String, dynamic>> map = {};
    double grandTotal = 0;

    for (final e in expenses) {
      final method = (e['payment_method']?.toString() ?? 'cash').toLowerCase();
      final total = (e['total_amount'] as num? ?? 0).toDouble();
      grandTotal += total;

      if (!map.containsKey(method)) {
        map[method] = {
          'method': method,
          'count': 0,
          'total': 0.0,
        };
      }
      map[method]!['count'] = (map[method]!['count'] as int) + 1;
      map[method]!['total'] = (map[method]!['total'] as double) + total;
    }

    final list = map.values.toList();
    for (final row in list) {
      final t = row['total'] as double;
      row['percentage'] = grandTotal > 0 ? (t / grandTotal) * 100 : 0.0;
    }

    list.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    return list;
  }

  List<Map<String, dynamic>> buildDailyTrends(
    List<Map<String, dynamic>> expenses,
  ) {
    final Map<String, Map<String, dynamic>> map = {};

    for (final e in expenses) {
      final date = e['expense_date']?.toString() ?? '';
      final total = (e['total_amount'] as num? ?? 0).toDouble();
      final tax = (e['tax_amount'] as num? ?? 0).toDouble();

      if (!map.containsKey(date)) {
        map[date] = {
          'date': date,
          'count': 0,
          'total': 0.0,
          'tax': 0.0,
        };
      }
      map[date]!['count'] = (map[date]!['count'] as int) + 1;
      map[date]!['total'] = (map[date]!['total'] as double) + total;
      map[date]!['tax'] = (map[date]!['tax'] as double) + tax;
    }

    final list = map.values.toList();
    list.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return list;
  }

  (String, List<Map<String, dynamic>>) checkReconciliation(
    List<Map<String, dynamic>> expenses,
  ) {
    final exceptions = <Map<String, dynamic>>[];
    for (final e in expenses) {
      final status = e['status']?.toString().toLowerCase() ?? 'posted';
      if (status == 'posted') {
        final journalId = e['journal_id']?.toString();
        final journalStatus = e['journal_status']?.toString();
        final journals = e['journals'] as List?;

        final hasJournal = (journalId != null && journalId.isNotEmpty) ||
            (journals != null && journals.isNotEmpty);

        if (!hasJournal) {
          exceptions.add({
            'expense_number': e['expense_number'],
            'expense_date': e['expense_date'],
            'amount': e['total_amount'],
            'journal_status': 'Missing',
            'note': 'Missing double-entry journal evidence for posted expense',
          });
        } else if (journalStatus != null &&
            journalStatus.isNotEmpty &&
            journalStatus != 'posted') {
          exceptions.add({
            'expense_number': e['expense_number'],
            'expense_date': e['expense_date'],
            'amount': e['total_amount'],
            'journal_status': journalStatus,
            'note': 'Journal status is $journalStatus instead of posted',
          });
        }
      }
    }

    if (exceptions.isEmpty) {
      return ('Passed', exceptions);
    }
    return ('Mismatch', exceptions);
  }

  Future<void> saveExcel({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> categoryAnalysis,
    required List<Map<String, dynamic>> dailyTrends,
    required List<Map<String, dynamic>> paymentBreakdown,
    List<Map<String, dynamic>> yardCosts = const [],
    required String reconciliationStatus,
    List<Map<String, dynamic>> reconciliationExceptions = const [],
  }) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Summary') {
      excel.rename(defaultSheet, 'Summary');
    }

    // 1. Summary Sheet
    final summarySheet = excel['Summary'];
    summarySheet.appendRow([
      TextCellValue('THQ ERP — ADVANCED EXPENSE REPORT'),
    ]);
    summarySheet.appendRow([TextCellValue('Business: $businessName')]);
    summarySheet.appendRow([
      TextCellValue(
        'Period: ${_dateFormat.format(from)} to ${_dateFormat.format(to)}',
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('Store / Location: ${locationLabel ?? 'All Stores'}'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Reconciliation Status: $reconciliationStatus'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Generated At: ${_timeFormat.format(DateTime.now())}'),
    ]);
    summarySheet.appendRow([TextCellValue('')]);

    summarySheet.appendRow([
      TextCellValue('Metric'),
      TextCellValue('Value'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Total Posted Expenses'),
      DoubleCellValue(
        (summary['total'] as num? ?? 0).toDouble(),
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('Total Net (Before Tax)'),
      DoubleCellValue(
        (summary['net_before_tax'] as num? ?? 0).toDouble(),
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('Total Tax (GST)'),
      DoubleCellValue(
        (summary['tax'] as num? ?? 0).toDouble(),
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('Expense Count'),
      IntCellValue((summary['expense_count'] as num? ?? 0).toInt()),
    ]);
    summarySheet.appendRow([
      TextCellValue('Average Expense'),
      DoubleCellValue(
        (summary['average'] as num? ?? 0).toDouble(),
      ),
    ]);
    summarySheet.appendRow([
      TextCellValue('Largest Expense'),
      DoubleCellValue(
        (summary['largest'] as num? ?? 0).toDouble(),
      ),
    ]);

    // 2. Expense Register Sheet
    final regSheet = excel['Expense Register'];
    regSheet.appendRow([
      TextCellValue('Expense Number'),
      TextCellValue('Date'),
      TextCellValue('Category'),
      TextCellValue('Payee'),
      TextCellValue('Description'),
      TextCellValue('Amount (Net)'),
      TextCellValue('Tax'),
      TextCellValue('Round Off'),
      TextCellValue('Total Amount'),
      TextCellValue('Payment Method'),
      TextCellValue('Reference'),
      TextCellValue('Status'),
      TextCellValue('Store'),
      TextCellValue('Journal Reference'),
    ]);

    for (final e in expenses) {
      regSheet.appendRow([
        TextCellValue(e['expense_number']?.toString() ?? ''),
        TextCellValue(e['expense_date']?.toString() ?? ''),
        TextCellValue(e['category_name']?.toString() ?? ''),
        TextCellValue(e['payee']?.toString() ?? ''),
        TextCellValue(e['description']?.toString() ?? ''),
        DoubleCellValue((e['amount'] as num? ?? 0).toDouble()),
        DoubleCellValue((e['tax_amount'] as num? ?? 0).toDouble()),
        DoubleCellValue((e['round_off'] as num? ?? 0).toDouble()),
        DoubleCellValue((e['total_amount'] as num? ?? 0).toDouble()),
        TextCellValue(
          e['payment_method']?.toString().toUpperCase() ?? '',
        ),
        TextCellValue(e['reference_number']?.toString() ?? ''),
        TextCellValue(e['status']?.toString().toUpperCase() ?? ''),
        TextCellValue(e['location_name']?.toString() ?? ''),
        TextCellValue(e['journal_number']?.toString() ?? ''),
      ]);
    }

    // 3. Category Analysis Sheet
    final catSheet = excel['Category Analysis'];
    catSheet.appendRow([
      TextCellValue('Category Name'),
      TextCellValue('Transactions'),
      TextCellValue('Total Spent'),
      TextCellValue('% of Expenses'),
      TextCellValue('Average Expense'),
      TextCellValue('Prior Period Total'),
    ]);

    for (final c in categoryAnalysis) {
      catSheet.appendRow([
        TextCellValue(c['category_name']?.toString() ?? ''),
        IntCellValue((c['expense_count'] as num? ?? 0).toInt()),
        DoubleCellValue((c['total'] as num? ?? 0).toDouble()),
        TextCellValue('${(c['percentage'] as num? ?? 0).toStringAsFixed(1)}%'),
        DoubleCellValue((c['average'] as num? ?? 0).toDouble()),
        DoubleCellValue((c['prior_total'] as num? ?? 0).toDouble()),
      ]);
    }

    // 4. Daily Trends Sheet
    final trendSheet = excel['Daily Trends'];
    trendSheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Transactions'),
      TextCellValue('Total Amount'),
      TextCellValue('Tax Amount'),
    ]);

    for (final d in dailyTrends) {
      trendSheet.appendRow([
        TextCellValue(d['date']?.toString() ?? ''),
        IntCellValue((d['count'] as num? ?? 0).toInt()),
        DoubleCellValue((d['total'] as num? ?? 0).toDouble()),
        DoubleCellValue((d['tax'] as num? ?? 0).toDouble()),
      ]);
    }

    // 5. Payment Breakdown Sheet
    final paySheet = excel['Payment Breakdown'];
    paySheet.appendRow([
      TextCellValue('Payment Method'),
      TextCellValue('Transactions'),
      TextCellValue('Total Amount'),
      TextCellValue('% of Total'),
    ]);

    for (final p in paymentBreakdown) {
      paySheet.appendRow([
        TextCellValue(p['method']?.toString().toUpperCase() ?? ''),
        IntCellValue((p['count'] as num? ?? 0).toInt()),
        DoubleCellValue((p['total'] as num? ?? 0).toDouble()),
        TextCellValue('${(p['percentage'] as num? ?? 0).toStringAsFixed(1)}%'),
      ]);
    }

    // 6. Material Yard Costs (if present)
    if (yardCosts.isNotEmpty) {
      final yardSheet = excel['Material Yard Costs'];
      yardSheet.appendRow([
        TextCellValue('Load Number'),
        TextCellValue('Date'),
        TextCellValue('Truck Number'),
        TextCellValue('Driver'),
        TextCellValue('Cost Kind'),
        TextCellValue('Description'),
        TextCellValue('Payee'),
        TextCellValue('Quantity'),
        TextCellValue('Rate'),
        TextCellValue('Total Amount'),
        TextCellValue('Payment Method'),
        TextCellValue('Status'),
      ]);

      for (final y in yardCosts) {
        yardSheet.appendRow([
          TextCellValue(y['load_number']?.toString() ?? ''),
          TextCellValue(y['load_date']?.toString() ?? ''),
          TextCellValue(y['truck_number']?.toString() ?? ''),
          TextCellValue(y['driver_name']?.toString() ?? ''),
          TextCellValue(
            y['cost_kind']?.toString().replaceAll('_', ' ').toUpperCase() ?? '',
          ),
          TextCellValue(y['description']?.toString() ?? ''),
          TextCellValue(y['payee']?.toString() ?? ''),
          DoubleCellValue((y['quantity'] as num? ?? 0).toDouble()),
          DoubleCellValue((y['rate'] as num? ?? 0).toDouble()),
          DoubleCellValue((y['amount'] as num? ?? 0).toDouble()),
          TextCellValue(
            y['payment_method']?.toString().toUpperCase() ?? '',
          ),
          TextCellValue(y['cost_status']?.toString().toUpperCase() ?? ''),
        ]);
      }
    }

    // 7. Reconciliation Exceptions
    final excSheet = excel['Reconciliation Exceptions'];
    excSheet.appendRow([
      TextCellValue('Expense Number'),
      TextCellValue('Date'),
      TextCellValue('Amount'),
      TextCellValue('Journal Status'),
      TextCellValue('Discrepancy Note'),
    ]);

    if (reconciliationExceptions.isEmpty) {
      excSheet.appendRow([
        TextCellValue('None'),
        TextCellValue('All posted expenses reconcile perfectly with ledger.'),
      ]);
    } else {
      for (final ex in reconciliationExceptions) {
        excSheet.appendRow([
          TextCellValue(ex['expense_number']?.toString() ?? ''),
          TextCellValue(ex['expense_date']?.toString() ?? ''),
          DoubleCellValue((ex['amount'] as num? ?? 0).toDouble()),
          TextCellValue(ex['journal_status']?.toString() ?? 'Missing'),
          TextCellValue(ex['note']?.toString() ?? ''),
        ]);
      }
    }

    final bytes = excel.encode();
    if (bytes != null) {
      final fileName =
          'expense_report_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx';
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  Future<void> savePdf({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> categoryAnalysis,
    required List<Map<String, dynamic>> paymentBreakdown,
    required String reconciliationStatus,
  }) async {
    final pdf = await buildPdfDocument(
      businessName: businessName,
      currencyCode: currencyCode,
      from: from,
      to: to,
      locationLabel: locationLabel,
      summary: summary,
      expenses: expenses,
      categoryAnalysis: categoryAnalysis,
      paymentBreakdown: paymentBreakdown,
      reconciliationStatus: reconciliationStatus,
    );

    final bytes = await pdf.save();
    final fileName =
        'expense_report_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.pdf';
    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> printPdf({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> categoryAnalysis,
    required List<Map<String, dynamic>> paymentBreakdown,
    required String reconciliationStatus,
  }) async {
    final pdf = await buildPdfDocument(
      businessName: businessName,
      currencyCode: currencyCode,
      from: from,
      to: to,
      locationLabel: locationLabel,
      summary: summary,
      expenses: expenses,
      categoryAnalysis: categoryAnalysis,
      paymentBreakdown: paymentBreakdown,
      reconciliationStatus: reconciliationStatus,
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'Expense_Report_${_dateFormat.format(from)}_${_dateFormat.format(to)}',
    );
  }

  Future<pw.Document> buildPdfDocument({
    required String businessName,
    required String currencyCode,
    required DateTime from,
    required DateTime to,
    String? locationLabel,
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> categoryAnalysis,
    required List<Map<String, dynamic>> paymentBreakdown,
    required String reconciliationStatus,
  }) async {
    final pdf = pw.Document();

    final total = (summary['total'] as num? ?? 0).toDouble();
    final net = (summary['net_before_tax'] as num? ?? 0).toDouble();
    final tax = (summary['tax'] as num? ?? 0).toDouble();
    final count = (summary['expense_count'] as num? ?? 0).toInt();
    final avg = (summary['average'] as num? ?? 0).toDouble();
    final largest = (summary['largest'] as num? ?? 0).toDouble();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    businessName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'ADVANCED EXPENSE REPORT',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Period: ${_dateFormat.format(from)} to ${_dateFormat.format(to)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    'Store: ${locationLabel ?? 'All Stores'} • Reconciled: $reconciliationStatus',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: reconciliationStatus == 'Passed'
                          ? PdfColors.green700
                          : PdfColors.red700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 1),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'THQ ERP Authoritative Financial Report • Generated ${_timeFormat.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 8),
          // KPI Summary Box
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _pdfKpi('TOTAL EXPENSES', _formatMoney(total, currencyCode)),
                _pdfKpi('BEFORE TAX', _formatMoney(net, currencyCode)),
                _pdfKpi('TAX (GST)', _formatMoney(tax, currencyCode)),
                _pdfKpi('COUNT', '$count'),
                _pdfKpi('AVERAGE', _formatMoney(avg, currencyCode)),
                _pdfKpi('LARGEST', _formatMoney(largest, currencyCode)),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Category Summary Table
          pw.Text(
            'CATEGORY ANALYSIS',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: [
              'Category',
              'Count',
              'Total Spent',
              '% Share',
              'Average',
            ],
            data: categoryAnalysis
                .map(
                  (c) => [
                    c['category_name']?.toString() ?? '',
                    '${c['expense_count'] ?? 0}',
                    _formatMoney(c['total'] as num? ?? 0, currencyCode),
                    '${(c['percentage'] as num? ?? 0).toStringAsFixed(1)}%',
                    _formatMoney(c['average'] as num? ?? 0, currencyCode),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 14),

          // Payment Methods Table
          pw.Text(
            'PAYMENT METHOD BREAKDOWN',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Payment Method', 'Transactions', 'Total Paid', '% Share'],
            data: paymentBreakdown
                .map(
                  (p) => [
                    p['method']?.toString().toUpperCase() ?? '',
                    '${p['count'] ?? 0}',
                    _formatMoney(p['total'] as num? ?? 0, currencyCode),
                    '${(p['percentage'] as num? ?? 0).toStringAsFixed(1)}%',
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 14),

          // Detailed Expense Register Table
          pw.Text(
            'DETAILED EXPENSE REGISTER',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: [
              'No.',
              'Date',
              'Category',
              'Payee / Description',
              'Method',
              'Net',
              'Tax',
              'Total',
            ],
            data: expenses
                .map(
                  (e) => [
                    e['expense_number']?.toString() ?? '',
                    e['expense_date']?.toString() ?? '',
                    e['category_name']?.toString() ?? '',
                    e['payee']?.toString().isNotEmpty == true
                        ? '${e['payee']} • ${e['description']}'
                        : (e['description']?.toString() ?? ''),
                    e['payment_method']?.toString().toUpperCase() ?? '',
                    _formatMoney(e['amount'] as num? ?? 0, currencyCode),
                    _formatMoney(e['tax_amount'] as num? ?? 0, currencyCode),
                    _formatMoney(e['total_amount'] as num? ?? 0, currencyCode),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
            },
          ),
        ],
      ),
    );

    return pdf;
  }

  pw.Widget _pdfKpi(String label, String value) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }
}
