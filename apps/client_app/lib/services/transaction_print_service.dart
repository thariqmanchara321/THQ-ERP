import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/client_session.dart';
import '../models/purchase_detail.dart';
import '../models/sale_detail.dart';
import 'invoice_pdf_service.dart';
import 'invoice_template_service.dart';
import 'tenant_settings_service.dart';

/// Output only. This service never creates, retries or changes a transaction.
class TransactionPrintService {
  final InvoiceTemplateService _invoiceTemplates = InvoiceTemplateService();
  final InvoicePdfService _invoicePdf = InvoicePdfService();
  final TenantSettingsService _settings = TenantSettingsService();

  Future<void> printSale({
    required ClientSession session,
    required SaleDetail sale,
    String paperType = 'a4',
  }) async {
    final initial = await Future.wait<dynamic>([
      _invoiceTemplates.getSaleOrigin(
        tenantId: session.business.id,
        saleId: sale.saleId,
      ),
      _settings.getSettings(session.business.id),
    ]);

    final origin = Map<String, dynamic>.from(initial[0] as Map);
    final settings = Map<String, dynamic>.from(initial[1] as Map);
    final template = await _invoiceTemplates.getTemplate(
      tenantId: session.business.id,
      paperType: paperType,
      locationId: origin['location_id']?.toString(),
      deviceId: origin['device_id']?.toString() ?? session.device?.deviceId,
    );

    final bytes = await _invoicePdf.build(
      session: session,
      sale: sale,
      paperType: paperType,
      template: template,
      origin: origin,
      settingsOverride: settings,
    );

    final invoiceNumber =
        origin['invoice_number']?.toString().trim().isNotEmpty == true
        ? origin['invoice_number'].toString().trim()
        : origin['local_number']?.toString().trim().isNotEmpty == true
        ? origin['local_number'].toString().trim()
        : sale.saleNumber;

    await _invoicePdf.printBytes(bytes, name: invoiceNumber);

    try {
      await _invoiceTemplates.logEvent(
        tenantId: session.business.id,
        saleId: sale.saleId,
        invoiceNumber: invoiceNumber,
        templateId: template['id']?.toString(),
        action: 'print',
        deviceId: origin['device_id']?.toString() ?? session.device?.deviceId,
      );
    } catch (_) {
      // A print-history logging failure must never affect the confirmed sale.
    }
  }

  Future<void> printPurchase({
    required ClientSession session,
    required PurchaseDetail purchase,
  }) async {
    final bytes = await _buildPurchase(session: session, purchase: purchase);
    await Printing.layoutPdf(
      name: purchase.purchaseNumber,
      onLayout: (_) async => bytes,
    );
  }

  Future<Uint8List> _buildPurchase({
    required ClientSession session,
    required PurchaseDetail purchase,
  }) async {
    final doc = pw.Document();
    String money(double value) =>
        '${session.currencyCode} ${value.toStringAsFixed(2)}';
    String date(DateTime value) =>
        '${value.day.toString().padLeft(2, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-${value.year}';

    pw.Widget cell(String text, {bool bold = false, pw.TextAlign? align}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(
            session.business.name,
            style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'PURCHASE CONFIRMATION',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Purchase: ${purchase.purchaseNumber}'),
                    pw.Text('Date: ${date(purchase.purchaseDate)}'),
                    if ((purchase.supplierInvoiceNumber ?? '').trim().isNotEmpty)
                      pw.Text(
                        'Supplier invoice: ${purchase.supplierInvoiceNumber}',
                      ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Supplier: ${purchase.supplierName}',
                      textAlign: pw.TextAlign.right,
                    ),
                    if ((purchase.supplierTaxNumber ?? '').trim().isNotEmpty)
                      pw.Text(
                        'GSTIN: ${purchase.supplierTaxNumber}',
                        textAlign: pw.TextAlign.right,
                      ),
                    pw.Text(
                      'Status: ${purchase.status}',
                      textAlign: pw.TextAlign.right,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3.2),
              1: pw.FlexColumnWidth(1.2),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.2),
              4: pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cell('Item', bold: true),
                  cell('Qty', bold: true, align: pw.TextAlign.right),
                  cell('Unit Cost', bold: true, align: pw.TextAlign.right),
                  cell('Tax', bold: true, align: pw.TextAlign.right),
                  cell('Total', bold: true, align: pw.TextAlign.right),
                ],
              ),
              ...purchase.items.map(
                (item) => pw.TableRow(
                  children: [
                    cell(
                      '${item.productName}\n${item.sku}'
                      '${(item.partNumber ?? '').trim().isEmpty ? '' : ' • ${item.partNumber}'}',
                    ),
                    cell(
                      '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 3)} ${item.unitCode ?? ''}',
                      align: pw.TextAlign.right,
                    ),
                    cell(money(item.unitCost), align: pw.TextAlign.right),
                    cell(
                      '${item.taxRate.toStringAsFixed(2)}%\n${money(item.taxAmount)}',
                      align: pw.TextAlign.right,
                    ),
                    cell(money(item.lineTotal), align: pw.TextAlign.right),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 245,
              child: pw.Column(
                children: [
                  _totalRow('Subtotal', money(purchase.subtotal)),
                  if (purchase.discountTotal.abs() > .0001)
                    _totalRow('Discount', '- ${money(purchase.discountTotal)}'),
                  _totalRow('Tax', money(purchase.taxTotal)),
                  if (purchase.additionalCharges.abs() > .0001)
                    _totalRow(
                      'Additional charges',
                      money(purchase.additionalCharges),
                    ),
                  pw.Divider(),
                  _totalRow(
                    'Grand total',
                    money(purchase.grandTotal),
                    bold: true,
                  ),
                  _totalRow('Paid', money(purchase.paidAmount)),
                  _totalRow(
                    'Balance due',
                    money(purchase.balanceDue),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
          if ((purchase.notes ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'Notes: ${purchase.notes}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            'Confirmed in THQ ERP. This output is generated after the purchase '
            'transaction has been successfully posted.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(value, style: style),
        ],
      ),
    );
  }
}
