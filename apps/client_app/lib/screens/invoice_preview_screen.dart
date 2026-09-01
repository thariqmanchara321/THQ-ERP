import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/sale_detail.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_template_service.dart';
import '../services/tenant_settings_service.dart';

class InvoicePreviewScreen extends StatefulWidget {
  final ClientSession session;
  final SaleDetail sale;
  final String paperType;

  const InvoicePreviewScreen({
    super.key,
    required this.session,
    required this.sale,
    required this.paperType,
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
    );
    final data = <String, dynamic>{
      'template': template,
      'origin': origin,
      'settings': settings,
    };
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

  String _invoiceNumber(Map<String, dynamic> origin) {
    final terminalNumber = origin['invoice_number']?.toString().trim() ?? '';
    final localNumber = origin['local_number']?.toString().trim() ?? '';
    if (terminalNumber.isNotEmpty) return terminalNumber;
    if (localNumber.isNotEmpty) return localNumber;
    return widget.sale.saleNumber;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'print' ? 'Print dialog opened.' : 'PDF prepared.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invoice output failed: $error')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        title: Text('${widget.paperType.toUpperCase()} Invoice'),
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
      body: FutureBuilder<Map<String, dynamic>>(
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
          final website = settings['business.website']?.toString().trim() ?? '';
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
          final hasDetailedLocationAddress = <dynamic>[
            origin['address_line1'],
            origin['address_line2'],
            origin['city'],
            origin['postal_code'],
          ].any((value) => value != null && value.toString().trim().isNotEmpty);
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
          final footer = config['footer']?.toString().trim().isNotEmpty == true
              ? config['footer'].toString().trim()
              : (configuredFooter.isNotEmpty
                    ? configuredFooter
                    : 'Thank you for your business.');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Container(
                width: narrow ? 350 : 840,
                padding: EdgeInsets.all(narrow ? 16 : 34),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
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
                    if (_flag(config, 'show_logo', true) && logoUrl.isNotEmpty)
                      SizedBox(
                        height: narrow ? 52 : 82,
                        child: Image.network(
                          logoUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    if (_flag(config, 'show_header', true)) ...[
                      if (header.isNotEmpty)
                        Text(
                          header,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: narrow ? 10 : 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      Text(
                        legalName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: narrow ? 20 : 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    if (branchName.isNotEmpty)
                      Text(branchName, textAlign: TextAlign.center),
                    if (_flag(config, 'show_gstin', true) && gstin.isNotEmpty)
                      Text('GSTIN: $gstin', textAlign: TextAlign.center),
                    if (_flag(config, 'show_phone', true) && phone.isNotEmpty)
                      Text('Phone: $phone', textAlign: TextAlign.center),
                    if (_flag(config, 'show_email', false) && email.isNotEmpty)
                      Text('Email: $email', textAlign: TextAlign.center),
                    if (_flag(config, 'show_website', false) &&
                        website.isNotEmpty)
                      Text(website, textAlign: TextAlign.center),
                    if (_flag(config, 'show_address', true) &&
                        address.isNotEmpty)
                      Text(address, textAlign: TextAlign.center),
                    const Divider(height: 26),
                    Text(
                      'TAX INVOICE • $invoiceNumber',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (invoiceNumber != widget.sale.saleNumber)
                      Text(
                        'ERP Ref: ${widget.sale.saleNumber}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    Text(
                      'Date: ${widget.sale.saleDate.toLocal().toString().split(' ').first}',
                    ),
                    if (_flag(config, 'show_customer', true)) ...[
                      Text('Customer: ${widget.sale.customerName}'),
                      if ((widget.sale.customerTaxNumber ?? '')
                          .trim()
                          .isNotEmpty)
                        Text(
                          'Customer GSTIN: ${widget.sale.customerTaxNumber}',
                        ),
                      if ((widget.sale.customerPhone ?? '').trim().isNotEmpty)
                        Text('Customer Phone: ${widget.sale.customerPhone}'),
                      if ((widget.sale.customerEmail ?? '').trim().isNotEmpty)
                        Text('Customer Email: ${widget.sale.customerEmail}'),
                      if ((widget.sale.customerAddress ?? '').trim().isNotEmpty)
                        Text(
                          'Customer Address: ${widget.sale.customerAddress}',
                        ),
                    ],
                    const Divider(),
                    ...widget.sale.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${item.productName}\n${item.quantity} × ${_money(item.unitPrice)}',
                                style: TextStyle(fontSize: narrow ? 11 : 13),
                              ),
                            ),
                            Text(
                              _money(item.lineTotal),
                              style: TextStyle(
                                fontSize: narrow ? 11 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    if (widget.sale.discountTotal > 0)
                      _row('Discount', _money(widget.sale.discountTotal)),
                    _row('Taxable', _money(widget.sale.taxableTotal)),
                    if (widget.sale.gst?.authoritative == true) ...[
                      if (widget.sale.gst!.cgstTotal.abs() > 0.0001)
                        _row('CGST', _money(widget.sale.gst!.cgstTotal)),
                      if (widget.sale.gst!.sgstTotal.abs() > 0.0001)
                        _row('SGST', _money(widget.sale.gst!.sgstTotal)),
                      if (widget.sale.gst!.utgstTotal.abs() > 0.0001)
                        _row('UTGST', _money(widget.sale.gst!.utgstTotal)),
                      if (widget.sale.gst!.igstTotal.abs() > 0.0001)
                        _row('IGST', _money(widget.sale.gst!.igstTotal)),
                      if (widget.sale.gst!.cessTotal.abs() > 0.0001)
                        _row('Cess', _money(widget.sale.gst!.cessTotal)),
                      if (!widget.sale.gst!.hasComponentTax &&
                          widget.sale.taxTotal > 0.0001)
                        _row('GST / Tax', _money(widget.sale.taxTotal)),
                    ] else
                      _row('Tax', _money(widget.sale.taxTotal)),
                    _row('Total', _money(widget.sale.grandTotal), bold: true),
                    _row('Paid', _money(widget.sale.paidAmount)),
                    _row('Balance', _money(widget.sale.balanceDue), bold: true),
                    if ((_flag(config, 'show_bank_details', false) &&
                            bankDetails.isNotEmpty) ||
                        (_flag(config, 'show_payment_details', true) &&
                            paymentDetails.isNotEmpty) ||
                        (_flag(config, 'show_payment_qr', false) &&
                            paymentQrUrl.isNotEmpty)) ...[
                      const SizedBox(height: 14),
                      if (narrow)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_flag(config, 'show_bank_details', false) &&
                                bankDetails.isNotEmpty)
                              Text('Bank: $bankDetails'),
                            if (_flag(config, 'show_payment_details', true) &&
                                paymentDetails.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(paymentDetails),
                            ],
                            if (_flag(config, 'show_payment_qr', false) &&
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
                                        errorBuilder: (_, _, _) => const Icon(
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                            if (_flag(config, 'show_payment_qr', false) &&
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
                                      errorBuilder: (_, _, _) => const Icon(
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
                      Text('Terms: $terms'),
                    ],
                    if (_flag(config, 'show_footer', true)) ...[
                      const SizedBox(height: 20),
                      Text(
                        footer,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: narrow ? 10 : 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
          ),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
        ),
      ],
    );
  }
}
