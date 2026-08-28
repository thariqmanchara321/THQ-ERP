import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/client_session.dart';
import '../models/sale_detail.dart';

class InvoicePdfService {
  PdfPageFormat _format(String paperType) {
    if (paperType.toLowerCase() == 'a4') return PdfPageFormat.a4;
    final width = paperType.toLowerCase() == '58mm' ? 58.0 : 80.0;
    return PdfPageFormat(width * PdfPageFormat.mm, 297 * PdfPageFormat.mm);
  }

  String _money(ClientSession session, double value) =>
      '${session.currencyCode} ${value.toStringAsFixed(2)}';

  String _text(Map<String, dynamic> map, String key, [String fallback = '']) {
    final value = map[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  bool _flag(Map<String, dynamic> config, String key, bool fallback) =>
      config.containsKey(key) ? config[key] == true : fallback;

  double _number(Map<String, dynamic> config, String key, double fallback) {
    final raw = config[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  PdfColor _accent(Map<String, dynamic> config) {
    var raw = (config['accent'] ?? '#4F46E5').toString().trim().replaceAll(
      '#',
      '',
    );
    if (raw.length != 6) raw = '4F46E5';
    final value = int.tryParse(raw, radix: 16) ?? 0x4F46E5;
    return PdfColor(
      ((value >> 16) & 0xff) / 255,
      ((value >> 8) & 0xff) / 255,
      (value & 0xff) / 255,
    );
  }

  pw.TextAlign _alignment(Map<String, dynamic> config) =>
      switch (config['header_alignment']?.toString()) {
        'left' => pw.TextAlign.left,
        'right' => pw.TextAlign.right,
        _ => pw.TextAlign.center,
      };

  String _invoiceNumber(SaleDetail sale, Map<String, dynamic> origin) {
    final terminal = _text(origin, 'invoice_number');
    if (terminal.isNotEmpty) return terminal;
    final local = _text(origin, 'local_number');
    return local.isNotEmpty ? local : sale.saleNumber;
  }

  Future<Uint8List> build({
    required ClientSession session,
    required SaleDetail sale,
    required String paperType,
    required Map<String, dynamic> template,
    required Map<String, dynamic> origin,
  }) async {
    final doc = pw.Document();
    final narrow = paperType.toLowerCase() != 'a4';
    final config = Map<String, dynamic>.from(
      template['config'] as Map? ?? const {},
    );
    final settings = session.settings;
    final accent = _accent(config);
    final align = _alignment(config);
    final baseFont = _number(
      config,
      'font_size',
      narrow ? 7.5 : 9.5,
    ).clamp(6.0, 16.0).toDouble();
    final marginMm = _number(
      config,
      'margin_mm',
      narrow ? 4 : 12,
    ).clamp(2.0, narrow ? 10.0 : 30.0).toDouble();

    final legalName =
        settings['business.legal_name']?.toString().trim().isNotEmpty == true
        ? settings['business.legal_name'].toString().trim()
        : session.business.name;
    final gstin = _text(
      origin,
      'gstin',
      settings['business.gstin']?.toString() ?? '',
    );
    final phone = _text(
      origin,
      'phone',
      settings['business.phone']?.toString() ?? '',
    );
    final email = settings['business.email']?.toString().trim() ?? '';
    final website = settings['business.website']?.toString().trim() ?? '';
    final configuredHeader =
        settings['documents.invoice_header']?.toString().trim() ?? '';
    final configuredFooter =
        settings['documents.invoice_footer']?.toString().trim() ?? '';
    final terms = settings['documents.terms']?.toString().trim() ?? '';
    final bankDetails =
        settings['documents.bank_details']?.toString().trim() ?? '';
    final paymentDetails =
        settings['documents.payment_details']?.toString().trim() ?? '';
    final addressParts =
        [
              origin['address_line1'],
              origin['address_line2'],
              origin['city'],
              origin['state'],
              origin['postal_code'],
            ]
            .where(
              (value) => value != null && value.toString().trim().isNotEmpty,
            )
            .map((value) => value.toString().trim())
            .toList();
    final address = addressParts.isNotEmpty
        ? addressParts.join(', ')
        : settings['business.address']?.toString().trim() ?? '';
    final branchName = _text(origin, 'location_name');
    final invoiceNumber = _invoiceNumber(sale, origin);
    final footer = (config['footer']?.toString().trim().isNotEmpty == true)
        ? config['footer'].toString().trim()
        : (configuredFooter.isNotEmpty
              ? configuredFooter
              : 'Thank you for your business.');

    final logoUrl = _text(
      origin,
      'location_logo_url',
      settings['business.logo_url']?.toString() ?? '',
    );
    pw.ImageProvider? logo;
    if (_flag(config, 'show_logo', true) && logoUrl.isNotEmpty) {
      try {
        logo = await networkImage(logoUrl);
      } catch (_) {
        logo = null;
      }
    }

    pw.Widget header() {
      final children = <pw.Widget>[];
      if (logo != null) {
        children.add(
          pw.Image(logo, height: narrow ? 30 : 50, fit: pw.BoxFit.contain),
        );
        children.add(pw.SizedBox(height: narrow ? 2 : 5));
      }
      if (_flag(config, 'show_header', true)) {
        if (configuredHeader.isNotEmpty) {
          children.add(
            pw.Text(
              configuredHeader,
              textAlign: align,
              style: pw.TextStyle(fontSize: baseFont, color: accent),
            ),
          );
        }
        children.add(
          pw.Text(
            legalName,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: narrow ? baseFont + 5 : baseFont + 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
      }
      if (branchName.isNotEmpty) {
        children.add(
          pw.Text(
            branchName,
            textAlign: align,
            style: pw.TextStyle(fontSize: baseFont),
          ),
        );
      }
      if (_flag(config, 'show_gstin', true) && gstin.isNotEmpty) {
        children.add(
          pw.Text(
            'GSTIN: $gstin',
            textAlign: align,
            style: pw.TextStyle(fontSize: baseFont),
          ),
        );
      }
      if (_flag(config, 'show_phone', true) && phone.isNotEmpty) {
        children.add(
          pw.Text(
            'Phone: $phone',
            textAlign: align,
            style: pw.TextStyle(fontSize: baseFont),
          ),
        );
      }
      if (_flag(config, 'show_email', false) && email.isNotEmpty) {
        children.add(
          pw.Text(
            email,
            textAlign: align,
            style: pw.TextStyle(fontSize: baseFont),
          ),
        );
      }
      if (_flag(config, 'show_website', false) && website.isNotEmpty) {
        children.add(
          pw.Text(
            website,
            textAlign: align,
            style: pw.TextStyle(fontSize: baseFont),
          ),
        );
      }
      if (_flag(config, 'show_address', true) && address.isNotEmpty) {
        children.add(
          pw.Text(
            address,
            textAlign: align,
            style: pw.TextStyle(fontSize: baseFont - .5),
          ),
        );
      }
      children.add(pw.SizedBox(height: narrow ? 3 : 7));
      children.add(pw.Container(height: 1.2, color: accent));
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: children,
      );
    }

    pw.Widget summary() => pw.Padding(
      padding: pw.EdgeInsets.only(top: narrow ? 4 : 8, bottom: narrow ? 4 : 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'TAX INVOICE',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: baseFont + 1,
              color: accent,
            ),
          ),
          pw.Text(
            'Invoice: $invoiceNumber',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: baseFont,
            ),
          ),
          if (invoiceNumber != sale.saleNumber)
            pw.Text(
              'THQ Ref: ${sale.saleNumber}',
              style: pw.TextStyle(fontSize: baseFont - .5),
            ),
          pw.Text(
            'Date: ${sale.saleDate.toLocal().toString().split(' ').first}',
            style: pw.TextStyle(fontSize: baseFont - .5),
          ),
          if (_flag(config, 'show_customer', true)) ...[
            pw.Text(
              'Customer: ${sale.customerName}',
              style: pw.TextStyle(fontSize: baseFont - .5),
            ),
            if ((sale.customerTaxNumber ?? '').trim().isNotEmpty)
              pw.Text(
                'Customer GSTIN: ${sale.customerTaxNumber}',
                style: pw.TextStyle(fontSize: baseFont - .5),
              ),
          ],
        ],
      ),
    );

    List<String> selectedColumns() {
      final raw = config['columns'];
      final defaults = narrow
          ? <String>['item', 'qty', 'rate', 'total']
          : <String>[
              'item',
              'sku',
              'hsn',
              'qty',
              'rate',
              'discount',
              'tax',
              'total',
            ];
      final requested = raw is List
          ? raw
                .map((value) => value.toString().trim().toLowerCase())
                .where((value) => value.isNotEmpty)
                .toList()
          : defaults;
      final allowed = <String>{
        'item',
        'sku',
        'hsn',
        'hsn_sac',
        'qty',
        'quantity',
        'rate',
        'price',
        'discount',
        'tax',
        'total',
      };
      final clean = requested.where(allowed.contains).toList();
      return clean.isEmpty ? defaults : clean;
    }

    String normalized(String column) => switch (column) {
      'hsn_sac' => 'hsn',
      'quantity' => 'qty',
      'price' => 'rate',
      _ => column,
    };

    String label(String column) => switch (normalized(column)) {
      'item' => 'Item',
      'sku' => 'SKU',
      'hsn' => 'HSN/SAC',
      'qty' => 'Qty',
      'rate' => 'Rate',
      'discount' => 'Disc.',
      'tax' => 'Tax',
      _ => 'Total',
    };

    int flex(String column) => switch (normalized(column)) {
      'item' => 5,
      'sku' => 2,
      'hsn' => 2,
      'qty' => 1,
      'rate' => 2,
      'discount' => 2,
      'tax' => 1,
      _ => 2,
    };

    String itemValue(SaleDetailItem item, String column) => switch (normalized(
      column,
    )) {
      'item' => item.productName,
      'sku' => item.sku,
      'hsn' =>
        item.hsnSac?.trim().isNotEmpty == true ? item.hsnSac!.trim() : '-',
      'qty' =>
        '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)}${(item.unitCode ?? '').trim().isEmpty ? '' : ' ${item.unitCode}'}',
      'rate' => _money(session, item.unitPrice),
      'discount' => _money(session, item.discountAmount),
      'tax' => '${item.taxRate.toStringAsFixed(2)}%',
      _ => _money(session, item.lineTotal),
    };

    pw.Widget items() {
      final columns = selectedColumns();
      pw.Widget cell(
        String text,
        int cellFlex, {
        bool bold = false,
        PdfColor? color,
      }) => pw.Expanded(
        flex: cellFlex,
        child: pw.Padding(
          padding: pw.EdgeInsets.symmetric(
            horizontal: narrow ? 1 : 2,
            vertical: narrow ? 2.5 : 3.5,
          ),
          child: pw.Text(
            text,
            maxLines: narrow ? 2 : 3,
            style: pw.TextStyle(
              fontSize: narrow ? baseFont - 1 : baseFont - .7,
              fontWeight: bold ? pw.FontWeight.bold : null,
              color: color,
            ),
          ),
        ),
      );

      return pw.Column(
        children: [
          pw.Container(
            color: PdfColors.grey200,
            child: pw.Row(
              children: columns
                  .map(
                    (column) => cell(
                      label(column),
                      flex(column),
                      bold: true,
                      color: accent,
                    ),
                  )
                  .toList(),
            ),
          ),
          ...sale.items.map(
            (item) => pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey300, width: .4),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: columns
                    .map(
                      (column) => cell(
                        itemValue(item, column),
                        flex(column),
                        bold: normalized(column) == 'total',
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      );
    }

    pw.Widget totals() {
      pw.Widget row(String name, double value, {bool bold = false}) =>
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    name,
                    style: pw.TextStyle(
                      fontSize: baseFont,
                      fontWeight: bold ? pw.FontWeight.bold : null,
                    ),
                  ),
                ),
                pw.Text(
                  _money(session, value),
                  style: pw.TextStyle(
                    fontSize: baseFont,
                    fontWeight: bold ? pw.FontWeight.bold : null,
                  ),
                ),
              ],
            ),
          );
      return pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: narrow ? double.infinity : 270,
          child: pw.Column(
            children: [
              if (sale.discountTotal > 0) row('Discount', sale.discountTotal),
              row('Taxable', sale.taxableTotal),
              if (_flag(config, 'show_tax_breakup', true))
                row('GST / Tax', sale.taxTotal),
              if (sale.additionalCharges > 0)
                row('Additional Charges', sale.additionalCharges),
              pw.Divider(),
              row('Grand Total', sale.grandTotal, bold: true),
              row('Paid', sale.paidAmount),
              row('Balance', sale.balanceDue, bold: sale.balanceDue > .005),
            ],
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: _format(paperType),
        margin: pw.EdgeInsets.all(marginMm * PdfPageFormat.mm),
        build: (_) => [
          header(),
          summary(),
          items(),
          pw.SizedBox(height: narrow ? 4 : 10),
          totals(),
          if ((sale.notes ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: narrow ? 4 : 8),
            pw.Text(
              'Notes: ${sale.notes}',
              style: pw.TextStyle(fontSize: baseFont - .5),
            ),
          ],
          if (_flag(config, 'show_bank_details', false) &&
              bankDetails.isNotEmpty) ...[
            pw.SizedBox(height: narrow ? 4 : 8),
            pw.Text(
              'Bank: $bankDetails',
              style: pw.TextStyle(fontSize: baseFont - .5),
            ),
          ],
          if (_flag(config, 'show_payment_details', true) &&
              paymentDetails.isNotEmpty) ...[
            pw.SizedBox(height: narrow ? 3 : 6),
            pw.Text(
              paymentDetails,
              style: pw.TextStyle(fontSize: baseFont - .5),
            ),
          ],
          if (_flag(config, 'show_terms', true) && terms.isNotEmpty) ...[
            pw.SizedBox(height: narrow ? 4 : 8),
            pw.Text(
              'Terms: $terms',
              style: pw.TextStyle(fontSize: baseFont - .8),
            ),
          ],
          if (_flag(config, 'show_footer', true)) ...[
            pw.SizedBox(height: narrow ? 7 : 16),
            pw.Text(
              footer,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: baseFont - .5, color: accent),
            ),
          ],
          if (!narrow && _flag(config, 'show_signatures', true)) ...[
            pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Customer Signature',
                  style: pw.TextStyle(fontSize: baseFont - 1),
                ),
                pw.Text(
                  'Authorized Signature',
                  style: pw.TextStyle(fontSize: baseFont - 1),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  Future<void> printBytes(Uint8List bytes, {required String name}) async {
    await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
  }

  Future<void> shareBytes(Uint8List bytes, {required String fileName}) async {
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }
}
