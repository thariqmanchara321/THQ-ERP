import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReturnReceiptRow {
  final String name;
  final String reference;
  final double quantity;
  final double rate;
  final double taxRate;
  final double total;

  const ReturnReceiptRow({
    required this.name,
    required this.reference,
    required this.quantity,
    required this.rate,
    required this.taxRate,
    required this.total,
  });
}

class ReturnReceiptService {
  String _money(String currencyCode, double value) =>
      '$currencyCode ${value.toStringAsFixed(2)}';

  Future<Uint8List> build({
    required String businessName,
    required String currencyCode,
    required String returnType,
    required String returnNumber,
    required String originalNumber,
    required String partyName,
    required String reason,
    required List<ReturnReceiptRow> rows,
    required double grandTotal,
    String? storeName,
    String? terminalName,
    String? userName,
  }) async {
    final doc = pw.Document();
    const format = PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm);
    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
        build: (_) => [
          pw.Text(
            businessName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            returnType == 'sale' ? 'SALES RETURN' : 'PURCHASE RETURN',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Divider(),
          pw.Text(
            'Return: $returnNumber',
            style: const pw.TextStyle(fontSize: 7.5),
          ),
          pw.Text(
            'Original: $originalNumber',
            style: const pw.TextStyle(fontSize: 7.5),
          ),
          pw.Text(
            '${returnType == 'sale' ? 'Customer' : 'Supplier'}: $partyName',
            style: const pw.TextStyle(fontSize: 7.5),
          ),
          if ((storeName ?? '').trim().isNotEmpty)
            pw.Text(
              'Store: $storeName',
              style: const pw.TextStyle(fontSize: 7),
            ),
          if ((terminalName ?? '').trim().isNotEmpty)
            pw.Text(
              'Terminal: $terminalName',
              style: const pw.TextStyle(fontSize: 7),
            ),
          if ((userName ?? '').trim().isNotEmpty)
            pw.Text('User: $userName', style: const pw.TextStyle(fontSize: 7)),
          pw.Text(
            'Date: ${DateTime.now().toLocal().toString().substring(0, 16)}',
            style: const pw.TextStyle(fontSize: 7),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Qty', 'Rate', 'Tax', 'Total'],
            data: rows
                .map(
                  (row) => [
                    row.reference.trim().isEmpty
                        ? row.name
                        : '${row.name}\n${row.reference}',
                    row.quantity.toStringAsFixed(row.quantity % 1 == 0 ? 0 : 2),
                    _money(currencyCode, row.rate),
                    '${row.taxRate.toStringAsFixed(2)}%',
                    _money(currencyCode, row.total),
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(
              fontSize: 6.5,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 6),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 1.5,
              vertical: 2.5,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'RETURN TOTAL',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                _money(currencyCode, grandTotal),
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          if (reason.trim().isNotEmpty) ...[
            pw.SizedBox(height: 5),
            pw.Text(
              'Reason: ${reason.trim()}',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
          pw.Divider(),
          pw.Text(
            'THQ • Audited return linked to original transaction',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> printReceipt({
    required String businessName,
    required String currencyCode,
    required String returnType,
    required String returnNumber,
    required String originalNumber,
    required String partyName,
    required String reason,
    required List<ReturnReceiptRow> rows,
    required double grandTotal,
    String? storeName,
    String? terminalName,
    String? userName,
  }) async {
    final bytes = await build(
      businessName: businessName,
      currencyCode: currencyCode,
      returnType: returnType,
      returnNumber: returnNumber,
      originalNumber: originalNumber,
      partyName: partyName,
      reason: reason,
      rows: rows,
      grandTotal: grandTotal,
      storeName: storeName,
      terminalName: terminalName,
      userName: userName,
    );
    await Printing.layoutPdf(
      name: '${returnNumber}_return.pdf',
      onLayout: (_) async => bytes,
    );
  }
}
