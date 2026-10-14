import 'package:flutter/material.dart';
import 'package:thq_ui/thq_ui.dart';

import '../models/client_session.dart';
import '../models/sale_detail.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_template_service.dart';
import '../services/tenant_settings_service.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final ClientSession session;
  final SaleDetail sale;
  final String paperType;
  final String? documentType;

  const InvoicePreviewScreen({
    super.key,
    required this.session,
    required this.sale,
    required this.paperType,
    this.documentType,
  });

  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  final InvoiceTemplateService _service = InvoiceTemplateService();
  final InvoicePdfService _pdfService = InvoicePdfService();
  final TenantSettingsService _settingsService = TenantSettingsService();
  late Future<Map<String, dynamic>> _future;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final initial = await Future.wait<dynamic>([
      _service.getSaleOrigin(
        tenantId: widget.session.business.id,
        saleId: widget.sale.saleId,
      ),
      _settingsService.getSettings(widget.session.business.id),
    ]);
    final origin = Map<String, dynamic>.from(initial[0] as Map);
    final settings = Map<String, dynamic>.from(initial[1] as Map);
    final template = await _service.getTemplate(
      tenantId: widget.session.business.id,
      paperType: widget.paperType,
      locationId: origin['location_id']?.toString(),
      deviceId:
          origin['device_id']?.toString() ?? widget.session.device?.deviceId,
      documentType: widget.documentType ??
          (widget.sale.status == 'estimate' ||
                  widget.sale.saleNumber.startsWith('EST-')
              ? 'estimate'
              : null),
    );
    final data = <String, dynamic>{
      'template': template,
      'origin': origin,
      'settings': settings,
    };
    if (widget.sale.saleId != 'estimate-draft' &&
        !widget.sale.saleId.startsWith('estimate-')) {
      try {
        await _service.logEvent(
          tenantId: widget.session.business.id,
          saleId: widget.sale.saleId,
          invoiceNumber: _invoiceNumber(origin),
          templateId: template['id']?.toString(),
          action: 'preview',
          deviceId:
              origin['device_id']?.toString() ?? widget.session.device?.deviceId,
        );
      } catch (_) {
        // Preview must not fail merely because print-history logging is unavailable.
      }
    }
    return data;
  }

  String _money(double value) {
    if (widget.session.currencyCode == 'INR') {
      return '₹${value.toStringAsFixed(2)}';
    }
    return '${widget.session.currencyCode} ${value.toStringAsFixed(2)}';
  }

  String _value(Map<String, dynamic> map, String key, String fallback) {
    final value = map[key]?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  bool _flag(Map<String, dynamic> config, String key, bool fallback) =>
      config.containsKey(key) ? config[key] == true : fallback;

  String _cleanInvoiceNumber(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final docMatch = RegExp(
      r'(?:^|[-_])((?:INV|EST|PUR|EXP|BILL|SAL|TAX|RET)[-_]\d+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (docMatch != null) {
      return docMatch.group(1)!.toUpperCase();
    }
    final parts = trimmed.split('-');
    if (parts.length >= 3) {
      final last = parts.last.trim();
      final prev = parts[parts.length - 2].trim();
      if (RegExp(r'^\d+$').hasMatch(last) && RegExp(r'^[A-Za-z]+$').hasMatch(prev)) {
        return '$prev-$last'.toUpperCase();
      }
      if (RegExp(r'^\d+$').hasMatch(last)) {
        return 'INV-$last';
      }
    }
    return trimmed;
  }

  String _invoiceNumber(Map<String, dynamic> origin) {
    final terminalNumber = origin['invoice_number']?.toString().trim() ?? '';
    final localNumber = origin['local_number']?.toString().trim() ?? '';
    final raw = terminalNumber.isNotEmpty
        ? terminalNumber
        : (localNumber.isNotEmpty ? localNumber : widget.sale.saleNumber);
    return _cleanInvoiceNumber(raw);
  }

  Future<void> _runPdfAction(String action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final data = await _future;
      final template = Map<String, dynamic>.from(
        data['template'] as Map? ?? const {},
      );
      final origin = Map<String, dynamic>.from(
        data['origin'] as Map? ?? const {},
      );
      final bytes = await _pdfService.build(
        session: widget.session,
        sale: widget.sale,
        paperType: widget.paperType,
        template: template,
        origin: origin,
        settingsOverride: Map<String, dynamic>.from(
          data['settings'] as Map? ?? const {},
        ),
      );
      final invoice = _invoiceNumber(origin);
      if (action == 'print') {
        await _pdfService.printBytes(bytes, name: invoice);
      } else {
        await _pdfService.shareBytes(
          bytes,
          fileName: '${invoice.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
        );
      }
      if (widget.sale.saleId != 'estimate-draft' &&
          !widget.sale.saleId.startsWith('estimate-')) {
        try {
          await _service.logEvent(
            tenantId: widget.session.business.id,
            saleId: widget.sale.saleId,
            invoiceNumber: invoice,
            templateId: template['id']?.toString(),
            action: action == 'print' ? 'print' : 'pdf',
            deviceId: widget.session.device?.deviceId,
          );
        } catch (_) {}
      }
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(
          content: Text(
            action == 'print' ? 'Print dialog opened.' : 'PDF prepared.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ThqNotify.showSnackBar(
        context,
        SnackBar(content: Text('Invoice output failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
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

  String _amountInWords(double value) {
    final minor = (value.abs() * 100).round();
    final rupees = minor ~/ 100;
    final paise = minor % 100;
    final prefix = value < 0 ? 'Minus ' : '';
    final paiseText = paise == 0 ? '' : ' and ${_integerWords(paise)} Paise';
    return '$prefix${_integerWords(rupees)} Rupees$paiseText Only';
  }

  String _dateLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '${widget.paperType.toUpperCase()} ${(widget.documentType == 'estimate' || widget.sale.status == 'estimate' || widget.sale.saleNumber.startsWith('EST-')) ? 'Estimate' : 'Invoice'}',
        ),
        actions: [
          if (_working)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Print',
              onPressed: () => _runPdfAction('print'),
              icon: const Icon(Icons.print_outlined),
            ),
            IconButton(
              tooltip: 'Save / Share PDF',
              onPressed: () => _runPdfAction('pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Theme(
        data: ThqTheme.light(),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 44),
                      const SizedBox(height: 12),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => setState(() => _future = _load()),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data ?? const <String, dynamic>{};
            final template = Map<String, dynamic>.from(
              data['template'] as Map? ?? const {},
            );
            final origin = Map<String, dynamic>.from(
              data['origin'] as Map? ?? const {},
            );
            final config = Map<String, dynamic>.from(
              template['config'] as Map? ?? const {},
            );
            final settings = Map<String, dynamic>.from(
              data['settings'] as Map? ?? widget.session.settings,
            );
            final narrow = widget.paperType != 'a4';
            final isEstimateDoc = widget.documentType == 'estimate' ||
                config['document_type'] == 'estimate' ||
                template['name']?.toString().toLowerCase().contains('estimate') == true ||
                widget.sale.status == 'estimate' ||
                widget.sale.saleNumber.startsWith('EST-');
            final nonGst = widget.sale.gst?.isNonGst == true;

            final configuredLegalName =
                settings['business.legal_name']?.toString().trim() ?? '';
            final legalName = configuredLegalName.isNotEmpty
                ? configuredLegalName
                : widget.session.business.name;
            final gstin = _value(
              origin,
              'gstin',
              settings['business.gstin']?.toString() ?? '',
            );
            final phone = _value(
              origin,
              'phone',
              settings['business.phone']?.toString() ?? '',
            );
            final email = _value(
              origin,
              'email',
              settings['business.email']?.toString() ?? '',
            );
            final website =
                settings['business.website']?.toString().trim() ?? '';
            final header =
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
                settings['documents.payment_qr_label']
                        ?.toString()
                        .trim()
                        .isNotEmpty ==
                    true
                ? settings['documents.payment_qr_label'].toString().trim()
                : 'Scan to Pay';
            final logoUrl = _value(
              origin,
              'location_logo_url',
              settings['business.logo_url']?.toString() ?? '',
            );
            final businessAddress =
                settings['business.address']?.toString().trim() ?? '';
            final hasDetailedLocationAddress =
                <dynamic>[
                  origin['address_line1'],
                  origin['address_line2'],
                  origin['city'],
                  origin['postal_code'],
                ].any(
                  (value) =>
                      value != null && value.toString().trim().isNotEmpty,
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
                      (value) =>
                          value != null && value.toString().trim().isNotEmpty,
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
            final invoiceNumber = _invoiceNumber(origin);
            final branchName = origin['location_name']?.toString().trim() ?? '';
            final footer =
                config['footer']?.toString().trim().isNotEmpty == true
                ? config['footer'].toString().trim()
                : (configuredFooter.isNotEmpty
                      ? configuredFooter
                      : 'Thank you for your business.');

            final accentColor = _parseAccent(config);
            final headerAlignment =
                config['header_alignment']?.toString() ?? 'center';
            final textAlign = switch (headerAlignment) {
              'left' => TextAlign.left,
              'right' => TextAlign.right,
              _ => TextAlign.center,
            };

            final configuredCompanyName =
                config['company_name']?.toString().trim() ?? '';
            final rawName = configuredCompanyName.isNotEmpty
                ? configuredCompanyName
                : legalName;
            final displayName = _flag(
              config,
              'company_name_uppercase',
              false,
            )
                ? rawName.toUpperCase()
                : rawName;
            final companyColor = _parseColor(
              config['company_name_color'],
              fallback: Colors.black87,
              accent: accentColor,
            );
            final customSize = double.tryParse(
              config['company_name_size']?.toString() ?? '',
            );
            final double nameFontSize = customSize != null
                ? (narrow ? customSize * 0.75 : customSize)
                : (narrow ? 20.0 : 26.0);
            final isBold = _flag(
              config,
              'company_name_bold',
              true,
            );
            final isItalic = _flag(
              config,
              'company_name_italic',
              false,
            );

            return ThqInvoicePaperScope(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Container(
                    width: narrow ? 360 : 860,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.18),
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 18,
                          color: Color(0x18000000),
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top accent line
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(7),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(narrow ? 16 : 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_flag(config, 'show_logo', true) &&
                                  logoUrl.isNotEmpty) ...[
                                Container(
                                  height: narrow ? 48 : 72,
                                  alignment: switch (headerAlignment) {
                                    'left' => Alignment.centerLeft,
                                    'right' => Alignment.centerRight,
                                    _ => Alignment.center,
                                  },
                                  child: Image.network(
                                    logoUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (_flag(config, 'show_header', true)) ...[
                                if (header.isNotEmpty)
                                  Text(
                                    header,
                                    textAlign: textAlign,
                                    style: TextStyle(
                                      fontSize: narrow ? 10 : 12,
                                      color: accentColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                Text(
                                  displayName,
                                  textAlign: textAlign,
                                  style: TextStyle(
                                    fontSize: nameFontSize,
                                    fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                                    fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                                    color: companyColor,
                                  ),
                                ),
                              ],
                              if (_flag(config, 'show_branch_name', false) &&
                                  branchName.isNotEmpty)
                                Text(
                                  branchName,
                                  textAlign: textAlign,
                                  style: TextStyle(
                                    fontSize: narrow ? 11 : 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              if (_flag(config, 'show_gstin', true) &&
                                  gstin.isNotEmpty)
                                Text(
                                  'GSTIN: $gstin',
                                  textAlign: textAlign,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              if (_flag(config, 'show_phone', true) &&
                                  phone.isNotEmpty)
                                Text(
                                  'Phone: $phone',
                                  textAlign: textAlign,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              if (_flag(config, 'show_email', false) &&
                                  email.isNotEmpty)
                                Text(
                                  'Email: $email',
                                  textAlign: textAlign,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              if (_flag(config, 'show_website', false) &&
                                  website.isNotEmpty)
                                Text(
                                  website,
                                  textAlign: textAlign,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              if (_flag(config, 'show_address', true) &&
                                  address.isNotEmpty)
                                Text(
                                  address,
                                  textAlign: textAlign,
                                  style: TextStyle(
                                    fontSize: narrow ? 10.5 : 11.5,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Divider(
                                height: 2,
                                color: accentColor.withValues(alpha: 0.35),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                isEstimateDoc
                                    ? 'ESTIMATE'
                                    : (nonGst
                                        ? 'INVOICE'
                                        : (widget.sale.gst?.invoiceTitle ?? 'TAX INVOICE')),
                                textAlign: textAlign,
                                style: TextStyle(
                                  fontSize: narrow ? 16 : 20,
                                  fontWeight: FontWeight.w900,
                                  color: accentColor,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (narrow) ...[
                                Text(
                                  isEstimateDoc
                                      ? 'Estimate No: $invoiceNumber'
                                      : 'Invoice No: $invoiceNumber',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Date: ${_dateLabel(widget.sale.saleDate)}',
                                ),
                              ] else
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        isEstimateDoc
                                            ? 'Estimate No: $invoiceNumber'
                                            : 'Invoice No: $invoiceNumber',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Date: ${_dateLabel(widget.sale.saleDate)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              if (_flag(config, 'show_erp_ref', false) &&
                                  invoiceNumber != widget.sale.saleNumber)
                                Text(
                                  'ERP Ref: ${widget.sale.saleNumber}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              if (widget.sale.gst?.authoritative == true) ...[
                                if ((widget.sale.gst!.placeOfSupplyCode ?? '')
                                    .isNotEmpty)
                                  Text(
                                    'Place of Supply: ${widget.sale.gst!.placeOfSupplyCode}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                Text(
                                  'Reverse Charge: '
                                  '${(widget.sale.gst!.taxMode ?? '').toLowerCase().contains('reverse') ? 'Yes' : 'No'}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                              if (_flag(config, 'show_customer', true)) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(
                                      alpha: 0.015,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.black.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'BILL TO',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                          color: accentColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        widget.sale.customerName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if ((widget.sale.customerAddress ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Text(
                                          widget.sale.customerAddress!,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      if ((widget.sale.customerTaxNumber ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Text(
                                          'GSTIN: ${widget.sale.customerTaxNumber}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      if ((widget.sale.customerPhone ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Text(
                                          'Phone: ${widget.sale.customerPhone}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      if ((widget.sale.customerEmail ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        Text(
                                          'Email: ${widget.sale.customerEmail}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              _invoiceItems(narrow, config, accentColor),
                              if (widget.sale.gst?.authoritative == true &&
                                  widget.sale.gst!.rateSummaries.isNotEmpty &&
                                  _flag(
                                    config,
                                    'show_tax_breakup',
                                    true,
                                  )) ...[
                                const SizedBox(height: 18),
                                _gstRateSummary(narrow, accentColor),
                              ],
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  width: narrow ? double.infinity : 340,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: accentColor.withValues(alpha: 0.16),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      if (widget.sale.discountTotal > 0)
                                        _row(
                                          'Discount',
                                          _money(widget.sale.discountTotal),
                                        ),
                                      _row(
                                        'Taxable Value',
                                        _money(widget.sale.taxableTotal),
                                      ),
                                      if (widget.sale.gst?.authoritative ==
                                          true) ...[
                                        if (widget.sale.gst!.cgstTotal.abs() >
                                            0.0001)
                                          _row(
                                            'CGST',
                                            _money(widget.sale.gst!.cgstTotal),
                                          ),
                                        if (widget.sale.gst!.sgstTotal.abs() >
                                            0.0001)
                                          _row(
                                            'SGST',
                                            _money(widget.sale.gst!.sgstTotal),
                                          ),
                                        if (widget.sale.gst!.utgstTotal.abs() >
                                            0.0001)
                                          _row(
                                            'UTGST',
                                            _money(widget.sale.gst!.utgstTotal),
                                          ),
                                        if (widget.sale.gst!.igstTotal.abs() >
                                            0.0001)
                                          _row(
                                            'IGST',
                                            _money(widget.sale.gst!.igstTotal),
                                          ),
                                        if (widget.sale.gst!.cessTotal.abs() >
                                            0.0001)
                                          _row(
                                            'Cess',
                                            _money(widget.sale.gst!.cessTotal),
                                          ),
                                        if (!widget.sale.gst!.hasComponentTax &&
                                            widget.sale.taxTotal > 0.0001)
                                          _row(
                                            'GST / Tax',
                                            _money(widget.sale.taxTotal),
                                          ),
                                      ] else
                                        _row(
                                          'Tax',
                                          _money(widget.sale.taxTotal),
                                        ),
                                      Divider(
                                        height: 14,
                                        color: accentColor.withValues(alpha: 0.3),
                                      ),
                                      _row(
                                        isEstimateDoc ? 'ESTIMATED TOTAL' : 'TOTAL',
                                        _money(widget.sale.grandTotal),
                                        bold: true,
                                        color: accentColor,
                                        fontSize: 14,
                                      ),
                                      if (!isEstimateDoc) ...[
                                        _row(
                                          'Paid',
                                          _money(widget.sale.paidAmount),
                                        ),
                                        _row(
                                          'Balance',
                                          _money(widget.sale.balanceDue),
                                          bold: widget.sale.balanceDue > .0001,
                                          color: widget.sale.balanceDue > .0001
                                              ? Colors.red.shade700
                                              : null,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Amount in words:\n${_amountInWords(widget.sale.grandTotal)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                              if ((_flag(config, 'show_bank_details', false) &&
                                      bankDetails.isNotEmpty) ||
                                  (_flag(
                                        config,
                                        'show_payment_details',
                                        true,
                                      ) &&
                                      paymentDetails.isNotEmpty) ||
                                  (_flag(config, 'show_payment_qr', false) &&
                                      paymentQrUrl.isNotEmpty)) ...[
                                const SizedBox(height: 14),
                                if (narrow)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_flag(
                                            config,
                                            'show_bank_details',
                                            false,
                                          ) &&
                                          bankDetails.isNotEmpty)
                                        Text('Bank: $bankDetails'),
                                      if (_flag(
                                            config,
                                            'show_payment_details',
                                            true,
                                          ) &&
                                          paymentDetails.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(paymentDetails),
                                      ],
                                      if (_flag(
                                            config,
                                            'show_payment_qr',
                                            false,
                                          ) &&
                                          paymentQrUrl.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                paymentQrLabel,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              SizedBox(
                                                width: 96,
                                                height: 96,
                                                child: Image.network(
                                                  paymentQrUrl,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (_, _, _) =>
                                                      const Icon(
                                                        Icons.qr_code_2_outlined,
                                                        size: 64,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                                else
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (_flag(
                                                  config,
                                                  'show_bank_details',
                                                  false,
                                                ) &&
                                                bankDetails.isNotEmpty)
                                              Text('Bank: $bankDetails'),
                                            if (_flag(
                                                  config,
                                                  'show_payment_details',
                                                  true,
                                                ) &&
                                                paymentDetails.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(paymentDetails),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (_flag(
                                            config,
                                            'show_payment_qr',
                                            false,
                                          ) &&
                                          paymentQrUrl.isNotEmpty) ...[
                                        const SizedBox(width: 24),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              paymentQrLabel,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            SizedBox(
                                              width: 112,
                                              height: 112,
                                              child: Image.network(
                                                paymentQrUrl,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, _, _) =>
                                                    const Icon(
                                                      Icons.qr_code_2_outlined,
                                                      size: 72,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                              if (_flag(config, 'show_terms', true) &&
                                  terms.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Terms: $terms',
                                  style: const TextStyle(fontSize: 10.5),
                                ),
                              ],
                              if (_flag(config, 'show_footer', true)) ...[
                                const SizedBox(height: 20),
                                Text(
                                  footer,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: narrow ? 10 : 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _parseAccent(Map<String, dynamic> config) {
    final raw = (config['accent'] ?? '#4F46E5').toString().trim().toLowerCase();
    switch (raw) {
      case 'indigo':
        return const Color(0xFF4F46E5);
      case 'teal':
        return const Color(0xFF0D9488);
      case 'emerald':
      case 'green':
        return const Color(0xFF059669);
      case 'navy':
      case 'blue':
        return const Color(0xFF1E40AF);
      case 'slate':
      case 'mono':
      case 'gray':
      case 'grey':
      case 'charcoal':
        return const Color(0xFF334155);
      case 'crimson':
      case 'red':
      case 'rose':
        return const Color(0xFFBE123C);
      case 'amber':
      case 'orange':
        return const Color(0xFFD97706);
      case 'violet':
      case 'purple':
        return const Color(0xFF7C3AED);
      case 'dark':
      case 'black':
        return const Color(0xFF0F172A);
    }
    final hex = raw.replaceAll('#', '');
    if (hex.length == 6) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    } else if (hex.length == 8) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(val);
    }
    return const Color(0xFF4F46E5);
  }

  Color _parseColor(
    dynamic rawValue, {
    required Color fallback,
    required Color accent,
  }) {
    if (rawValue == null) return fallback;
    final raw = rawValue.toString().trim().toLowerCase();
    if (raw.isEmpty) return fallback;
    if (raw == 'accent') return accent;
    switch (raw) {
      case 'indigo':
        return const Color(0xFF4F46E5);
      case 'teal':
        return const Color(0xFF0D9488);
      case 'emerald':
      case 'green':
        return const Color(0xFF059669);
      case 'navy':
      case 'blue':
        return const Color(0xFF1E40AF);
      case 'slate':
      case 'mono':
      case 'gray':
      case 'grey':
      case 'charcoal':
        return const Color(0xFF334155);
      case 'crimson':
      case 'red':
      case 'rose':
        return const Color(0xFFBE123C);
      case 'amber':
      case 'orange':
        return const Color(0xFFD97706);
      case 'violet':
      case 'purple':
        return const Color(0xFF7C3AED);
      case 'dark':
      case 'black':
        return const Color(0xFF0F172A);
    }
    final hex = raw.replaceAll('#', '');
    if (hex.length == 6) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    } else if (hex.length == 8) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null) return Color(val);
    }
    return fallback;
  }

  List<String> _resolveColumns(Map<String, dynamic> config, bool narrow) {
    final raw = config['columns'];
    final defaults = narrow
        ? <String>['item', 'qty', 'rate', 'total']
        : <String>[
            'item',
            'sku',
            'hsn',
            'qty',
            'unit',
            'rate',
            'discount',
            'tax',
            'total',
          ];
    final requested = raw is List
        ? raw
            .map((v) => v.toString().trim().toLowerCase())
            .where((v) => v.isNotEmpty)
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
    final clean = requested.where(allowed.contains).where((c) {
      if (!_flag(config, 'show_hsn', true) && (c == 'hsn' || c == 'hsn_sac')) {
        return false;
      }
      return true;
    }).toList();
    return clean.isEmpty ? defaults : clean;
  }

  String _normalizeColumn(String column) => switch (column.toLowerCase()) {
    'hsn_sac' => 'hsn',
    'quantity' => 'qty',
    'price' => 'rate',
    _ => column.toLowerCase(),
  };

  bool _isNumericColumn(String column) => switch (_normalizeColumn(column)) {
    'item' || 'sku' || 'hsn' => false,
    _ => true,
  };

  String _columnLabel(String column) => switch (_normalizeColumn(column)) {
    'item' => 'Description',
    'sku' => 'SKU',
    'hsn' => 'HSN/SAC',
    'qty' => 'Qty',
    'unit' => 'Unit',
    'rate' => 'Rate',
    'discount' => 'Disc.',
    'tax' => 'Tax %',
    'tax_amount' => 'Tax Amt',
    'taxable' => 'Taxable',
    _ => 'Amount',
  };

  String _itemColumnValue(SaleDetailItem item, String column) =>
      switch (_normalizeColumn(column)) {
        'item' => item.productName,
        'sku' => item.sku.trim().isNotEmpty ? item.sku.trim() : '—',
        'hsn' => item.hsnSac?.trim().isNotEmpty == true
            ? item.hsnSac!.trim()
            : '—',
        'qty' => item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2),
        'unit' => (item.unitCode ?? '').trim().isNotEmpty
            ? item.unitCode!.trim()
            : '—',
        'rate' => _money(item.unitPrice),
        'discount' => _money(item.discountAmount),
        'tax' => '${item.taxRate.toStringAsFixed(1)}%',
        'tax_amount' => _money(item.taxAmount),
        'taxable' => _money(item.taxableAmount),
        _ => _money(item.lineTotal),
      };

  Widget _invoiceItems(
    bool narrow,
    Map<String, dynamic> config,
    Color accentColor,
  ) {
    final columns = _resolveColumns(config, narrow);
    if (narrow) {
      return Column(
        children: [
          for (final item in widget.sale.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${item.productName}\n'
                      '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)} × ${_money(item.unitPrice)}'
                      '${(item.hsnSac ?? '').trim().isEmpty || !_flag(config, 'show_hsn', true) ? '' : '\nHSN: ${item.hsnSac}'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  Text(
                    _money(item.lineTotal),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    Widget cell(
      String value, {
      bool header = false,
      TextAlign align = TextAlign.left,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text(
        value,
        textAlign: align,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: header ? FontWeight.w800 : FontWeight.normal,
          color: header ? accentColor : null,
        ),
      ),
    );

    final widths = <int, TableColumnWidth>{};
    widths[0] = const FlexColumnWidth(0.5); // Row No (#)
    for (var i = 0; i < columns.length; i++) {
      final col = _normalizeColumn(columns[i]);
      widths[i + 1] = switch (col) {
        'item' => const FlexColumnWidth(3.0),
        'sku' => const FlexColumnWidth(1.2),
        'hsn' => const FlexColumnWidth(1.1),
        'qty' => const FlexColumnWidth(0.85),
        'unit' => const FlexColumnWidth(0.8),
        'rate' => const FlexColumnWidth(1.1),
        'discount' => const FlexColumnWidth(1.0),
        'tax' => const FlexColumnWidth(0.9),
        'tax_amount' => const FlexColumnWidth(1.1),
        'taxable' => const FlexColumnWidth(1.2),
        _ => const FlexColumnWidth(1.2),
      };
    }

    return Table(
      border: TableBorder.all(
        color: accentColor.withValues(alpha: 0.22),
        width: 1,
      ),
      columnWidths: widths,
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.08),
          ),
          children: [
            cell('#', header: true, align: TextAlign.center),
            for (final col in columns)
              cell(
                _columnLabel(col),
                header: true,
                align: _isNumericColumn(col) ? TextAlign.right : TextAlign.left,
              ),
          ],
        ),
        for (var i = 0; i < widget.sale.items.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: i.isOdd ? Colors.black.withValues(alpha: 0.015) : null,
            ),
            children: [
              cell('${i + 1}', align: TextAlign.center),
              for (final col in columns)
                cell(
                  _itemColumnValue(widget.sale.items[i], col),
                  align:
                      _isNumericColumn(col) ? TextAlign.right : TextAlign.left,
                ),
            ],
          ),
      ],
    );
  }

  Widget _gstRateSummary(bool narrow, Color accentColor) {
    final rows = widget.sale.gst?.rateSummaries ?? const <SaleGstRateSummary>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'TAX SUMMARY',
            style: TextStyle(fontWeight: FontWeight.w900, color: accentColor),
          ),
          const SizedBox(height: 5),
          for (final row in rows)
            Text(
              '${row.rate.toStringAsFixed(2)}% • Taxable ${_money(row.taxable)} '
              '• Tax ${_money(row.taxTotal)}',
              style: const TextStyle(fontSize: 10),
            ),
        ],
      );
    }

    Widget cell(
      String value, {
      bool header = false,
      TextAlign align = TextAlign.right,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: Text(
        value,
        textAlign: align,
        style: TextStyle(
          fontSize: 10,
          fontWeight: header ? FontWeight.w800 : FontWeight.normal,
          color: header ? accentColor : null,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'TAX SUMMARY',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 11,
            color: accentColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Table(
          border: TableBorder.all(
            color: accentColor.withValues(alpha: 0.22),
            width: 1,
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
              ),
              children: [
                cell('GST %', header: true, align: TextAlign.left),
                cell('Taxable', header: true),
                cell('CGST', header: true),
                cell('SGST/UTGST', header: true),
                cell('IGST', header: true),
                cell('Cess', header: true),
                cell('Total', header: true),
              ],
            ),
            for (final row in rows)
              TableRow(
                children: [
                  cell(
                    '${row.rate.toStringAsFixed(2)}%',
                    align: TextAlign.left,
                  ),
                  cell(_money(row.taxable)),
                  cell(_money(row.cgst)),
                  cell(_money(row.sgst + row.utgst)),
                  cell(_money(row.igst)),
                  cell(_money(row.cess)),
                  cell(_money(row.total)),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color? color,
    double? fontSize,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : null,
                color: color,
                fontSize: fontSize,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
              color: color,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
}

