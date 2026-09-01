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

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }

  String _integerWords(int value) {
    if (value == 0) return 'Zero';
    const ones = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];
    const tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];
    String belowHundred(int number) {
      if (number < 20) return ones[number];
      final tail = number % 10;
      return '${tens[number ~/ 10]}${tail == 0 ? '' : ' ${ones[tail]}'}';
    }

    final parts = <String>[];
    var remaining = value;
    void take(int unit, String label) {
      if (remaining < unit) return;
      parts.add('${_integerWords(remaining ~/ unit)} $label');
      remaining %= unit;
    }

    take(10000000, 'Crore');
    take(100000, 'Lakh');
    take(1000, 'Thousand');
    take(100, 'Hundred');
    if (remaining > 0) parts.add(belowHundred(remaining));
    return parts.join(' ');
  }

  String _amountInWords(ClientSession session, double value) {
    final minor = (value.abs() * 100).round();
    final major = minor ~/ 100;
    final remainder = minor % 100;
    final prefix = value < 0 ? 'Minus ' : '';
    if (session.currencyCode != 'INR') {
      return '$prefix${_integerWords(major)} ${session.currencyCode} Only';
    }
    final paise = remainder == 0
        ? ''
        : ' and ${_integerWords(remainder)} Paise';
    return '$prefix${_integerWords(major)} Rupees$paise Only';
  }

  Future<Uint8List> build({
    required ClientSession session,
    required SaleDetail sale,
    required String paperType,
    required Map<String, dynamic> template,
    required Map<String, dynamic> origin,
    Map<String, dynamic>? settingsOverride,
  }) async {
    final doc = pw.Document();
    final narrow = paperType.toLowerCase() != 'a4';
    final config = Map<String, dynamic>.from(
      template['config'] as Map? ?? const {},
    );
    final settings = settingsOverride ?? session.settings;
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
    final email = _text(
      origin,
      'email',
      settings['business.email']?.toString() ?? '',
    );
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
    final paymentQrUrl =
        settings['documents.payment_qr_url']?.toString().trim() ?? '';
    final paymentQrLabel =
        settings['documents.payment_qr_label']?.toString().trim().isNotEmpty ==
            true
        ? settings['documents.payment_qr_label'].toString().trim()
        : 'Scan to Pay';
    final businessAddress =
        settings['business.address']?.toString().trim() ?? '';
    final locationCoreParts = <dynamic>[
      origin['address_line1'],
      origin['address_line2'],
      origin['city'],
      origin['postal_code'],
    ];
    final hasDetailedLocationAddress = locationCoreParts.any(
      (value) => value != null && value.toString().trim().isNotEmpty,
    );
    final locationAddressParts =
        <dynamic>[
              origin['address_line1'],
              origin['address_line2'],
              origin['city'],
              origin['state'],
              origin['postal_code'],
              origin['country'],
            ]
            .where(
              (value) => value != null && value.toString().trim().isNotEmpty,
            )
            .map((value) => value.toString().trim())
            .toList();
    final addressParts = <String>[];
    if (hasDetailedLocationAddress) {
      addressParts.addAll(locationAddressParts);
    } else {
      if (businessAddress.isNotEmpty) addressParts.add(businessAddress);
      for (final key in const ['state', 'country']) {
        final value = origin[key]?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        final duplicate = addressParts.any(
          (part) => part.toLowerCase().contains(value.toLowerCase()),
        );
        if (!duplicate) addressParts.add(value);
      }
    }
    final address = addressParts.join(', ');
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

    pw.ImageProvider? paymentQr;
    if (_flag(config, 'show_payment_qr', false) && paymentQrUrl.isNotEmpty) {
      try {
        paymentQr = await networkImage(paymentQrUrl);
      } catch (_) {
        paymentQr = null;
      }
    }

    pw.Widget header() {
      final children = <pw.Widget>[];
      if (logo != null) {
        children.add(
          pw.Container(
            width: narrow ? 55 : 120,
            height: narrow ? 30 : 52,
            alignment: pw.Alignment.center,
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
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
            'Date: ${_dateLabel(sale.saleDate)}',
            style: pw.TextStyle(fontSize: baseFont - .5),
          ),
          if (sale.gst?.authoritative == true) ...[
            if ((sale.gst!.placeOfSupplyCode ?? '').isNotEmpty)
              pw.Text(
                'Place of Supply: ${sale.gst!.placeOfSupplyCode}',
                style: pw.TextStyle(fontSize: baseFont - .5),
              ),
            pw.Text(
              'Reverse Charge: '
              '${(sale.gst!.taxMode ?? '').toLowerCase().contains('reverse') ? 'Yes' : 'No'}',
              style: pw.TextStyle(fontSize: baseFont - .5),
            ),
          ],
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
            if ((sale.customerPhone ?? '').trim().isNotEmpty)
              pw.Text(
                'Phone: ${sale.customerPhone}',
                style: pw.TextStyle(fontSize: baseFont - .5),
              ),
            if ((sale.customerEmail ?? '').trim().isNotEmpty)
              pw.Text(
                'Email: ${sale.customerEmail}',
                style: pw.TextStyle(fontSize: baseFont - .5),
              ),
            if ((sale.customerAddress ?? '').trim().isNotEmpty)
              pw.Text(
                sale.customerAddress!,
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
        'unit',
        'rate',
        'price',
        'discount',
        'tax',
        'tax_amount',
        'taxable',
        'total',
      };
      final clean = requested.where(allowed.contains).where((column) {
        if (!_flag(config, 'show_hsn', true) &&
            (column == 'hsn' || column == 'hsn_sac')) {
          return false;
        }
        return true;
      }).toList();
      return clean.isEmpty
          ? defaults.where((column) {
              return _flag(config, 'show_hsn', true) || column != 'hsn';
            }).toList()
          : clean;
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
      'unit' => 'Unit',
      'rate' => 'Rate',
      'discount' => 'Discount',
      'tax' => 'Tax %',
      'tax_amount' => 'Tax Amt',
      'taxable' => 'Taxable',
      _ => 'Total',
    };

    int flex(String column) => switch (normalized(column)) {
      'item' => 5,
      'sku' => 2,
      'hsn' => 2,
      'qty' => 1,
      'unit' => 1,
      'rate' => 2,
      'discount' => 2,
      'tax' => 1,
      'tax_amount' => 2,
      'taxable' => 2,
      _ => 2,
    };

    String itemValue(SaleDetailItem item, String column) => switch (normalized(
      column,
    )) {
      'item' => item.productName,
      'sku' => item.sku,
      'hsn' =>
        item.hsnSac?.trim().isNotEmpty == true ? item.hsnSac!.trim() : '-',
      'qty' => item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2),
      'unit' =>
        (item.unitCode ?? '').trim().isEmpty ? '-' : item.unitCode!.trim(),
      'rate' => _money(session, item.unitPrice),
      'discount' => _money(session, item.discountAmount),
      'tax' => '${item.taxRate.toStringAsFixed(2)}%',
      'tax_amount' => _money(session, item.taxAmount),
      'taxable' => _money(session, item.taxableAmount),
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
            color: narrow ? PdfColors.grey200 : accent,
            child: pw.Row(
              children: columns
                  .map(
                    (column) => cell(
                      label(column),
                      flex(column),
                      bold: true,
                      color: narrow ? accent : PdfColors.white,
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

    pw.Widget taxSummary() {
      final gst = sale.gst;
      final rows = gst?.rateSummaries ?? const <SaleGstRateSummary>[];
      if (gst?.authoritative != true || rows.isEmpty) {
        return pw.SizedBox();
      }
      pw.Widget cell(String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: narrow ? baseFont - 1.4 : baseFont - 1,
            fontWeight: bold ? pw.FontWeight.bold : null,
          ),
        ),
      );
      if (narrow) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'TAX SUMMARY',
              style: pw.TextStyle(
                fontSize: baseFont,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            ...rows.map(
              (row) => pw.Text(
                '${row.rate.toStringAsFixed(2)}% | '
                'Taxable ${_money(session, row.taxable)} | '
                'Tax ${_money(session, row.taxTotal)}',
                style: pw.TextStyle(fontSize: baseFont - 1),
              ),
            ),
          ],
        );
      }
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'TAX SUMMARY',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: baseFont,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: .4),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cell('GST %', bold: true),
                  cell('Taxable', bold: true),
                  cell('CGST', bold: true),
                  cell('SGST/UTGST', bold: true),
                  cell('IGST', bold: true),
                  cell('Cess', bold: true),
                  cell('Total', bold: true),
                ],
              ),
              ...rows.map(
                (row) => pw.TableRow(
                  children: [
                    cell('${row.rate.toStringAsFixed(2)}%'),
                    cell(_money(session, row.taxable)),
                    cell(_money(session, row.cgst)),
                    cell(_money(session, row.sgst + row.utgst)),
                    cell(_money(session, row.igst)),
                    cell(_money(session, row.cess)),
                    cell(_money(session, row.total)),
                  ],
                ),
              ),
            ],
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
              if (_flag(config, 'show_tax_breakup', true)) ...[
                if (sale.gst?.authoritative == true) ...[
                  if (sale.gst!.cgstTotal.abs() > 0.0001)
                    row('CGST', sale.gst!.cgstTotal),
                  if (sale.gst!.sgstTotal.abs() > 0.0001)
                    row('SGST', sale.gst!.sgstTotal),
                  if (sale.gst!.utgstTotal.abs() > 0.0001)
                    row('UTGST', sale.gst!.utgstTotal),
                  if (sale.gst!.igstTotal.abs() > 0.0001)
                    row('IGST', sale.gst!.igstTotal),
                  if (sale.gst!.cessTotal.abs() > 0.0001)
                    row('Cess', sale.gst!.cessTotal),
                  if (!sale.gst!.hasComponentTax && sale.taxTotal > 0.0001)
                    row('GST / Tax', sale.taxTotal),
                ] else
                  row('GST / Tax', sale.taxTotal),
              ],
              if (sale.additionalCharges > 0)
                row('Additional Charges', sale.additionalCharges),
              pw.Divider(color: accent),
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
          taxSummary(),
          if (sale.gst?.authoritative == true &&
              sale.gst!.rateSummaries.isNotEmpty)
            pw.SizedBox(height: narrow ? 4 : 10),
          totals(),
          pw.SizedBox(height: narrow ? 4 : 8),
          pw.Text(
            'Amount in words: ${_amountInWords(session, sale.grandTotal)}',
            style: pw.TextStyle(
              fontSize: baseFont - .4,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if ((sale.notes ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: narrow ? 4 : 8),
            pw.Text(
              'Notes: ${sale.notes}',
              style: pw.TextStyle(fontSize: baseFont - .5),
            ),
          ],
          if ((_flag(config, 'show_bank_details', false) &&
                  bankDetails.isNotEmpty) ||
              (_flag(config, 'show_payment_details', true) &&
                  paymentDetails.isNotEmpty) ||
              paymentQr != null) ...[
            pw.SizedBox(height: narrow ? 4 : 9),
            if (narrow)
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (_flag(config, 'show_bank_details', false) &&
                      bankDetails.isNotEmpty)
                    pw.Text(
                      'Bank: $bankDetails',
                      style: pw.TextStyle(fontSize: baseFont - .5),
                    ),
                  if (_flag(config, 'show_payment_details', true) &&
                      paymentDetails.isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      paymentDetails,
                      style: pw.TextStyle(fontSize: baseFont - .5),
                    ),
                  ],
                  if (paymentQr != null) ...[
                    pw.SizedBox(height: 7),
                    pw.Center(
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text(
                            paymentQrLabel,
                            style: pw.TextStyle(
                              fontSize: baseFont - .3,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.SizedBox(
                            width: 72,
                            height: 72,
                            child: pw.Image(paymentQr, fit: pw.BoxFit.contain),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              )
            else
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (_flag(config, 'show_bank_details', false) &&
                            bankDetails.isNotEmpty)
                          pw.Text(
                            'Bank: $bankDetails',
                            style: pw.TextStyle(fontSize: baseFont - .5),
                          ),
                        if (_flag(config, 'show_payment_details', true) &&
                            paymentDetails.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            paymentDetails,
                            style: pw.TextStyle(fontSize: baseFont - .5),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (paymentQr != null) ...[
                    pw.SizedBox(width: 20),
                    pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          paymentQrLabel,
                          style: pw.TextStyle(
                            fontSize: baseFont - .3,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.SizedBox(
                          width: 92,
                          height: 92,
                          child: pw.Image(paymentQr, fit: pw.BoxFit.contain),
                        ),
                      ],
                    ),
                  ],
                ],
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
