import 'package:flutter/material.dart';

import '../models/client_session.dart';
import '../models/sale_detail.dart';
import '../services/invoice_pdf_service.dart';
import '../services/invoice_template_service.dart';

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
  late Future<Map<String, dynamic>> _future;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final origin = await _service.getSaleOrigin(
      tenantId: widget.session.business.id,
      saleId: widget.sale.saleId,
    );
    final template = await _service.getTemplate(
      tenantId: widget.session.business.id,
      paperType: widget.paperType,
      locationId: origin['location_id']?.toString(),
      deviceId:
          origin['device_id']?.toString() ?? widget.session.device?.deviceId,
    );
    final data = <String, dynamic>{'template': template, 'origin': origin};
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
          final settings = widget.session.settings;
          final narrow = widget.paperType != 'a4';

          final legalName =
              settings['business.legal_name']?.toString() ??
              widget.session.business.name;
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
          final branchAddress =
              [
                    origin['address_line1'],
                    origin['address_line2'],
                    origin['city'],
                    origin['state'],
                    origin['postal_code'],
                  ]
                  .where(
                    (value) =>
                        value != null && value.toString().trim().isNotEmpty,
                  )
                  .map((value) => value.toString().trim())
                  .join(', ');
          final address = branchAddress.isNotEmpty
              ? branchAddress
              : settings['business.address']?.toString() ?? '';
          final invoiceNumber = _invoiceNumber(origin);
          final branchName = origin['location_name']?.toString() ?? '';

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
                    Text(
                      legalName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: narrow ? 20 : 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (branchName.isNotEmpty)
                      Text(branchName, textAlign: TextAlign.center),
                    if (gstin.isNotEmpty)
                      Text('GSTIN: $gstin', textAlign: TextAlign.center),
                    if (phone.isNotEmpty)
                      Text('Phone: $phone', textAlign: TextAlign.center),
                    if ((!narrow || config['show_address'] == true) &&
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
                    Text('Customer: ${widget.sale.customerName}'),
                    if ((widget.sale.customerTaxNumber ?? '').trim().isNotEmpty)
                      Text('Customer GSTIN: ${widget.sale.customerTaxNumber}'),
                    Text(
                      'Date: ${widget.sale.saleDate.toLocal().toString().split(' ').first}',
                    ),
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
                    _row('Tax', _money(widget.sale.taxTotal)),
                    _row('Total', _money(widget.sale.grandTotal), bold: true),
                    _row('Paid', _money(widget.sale.paidAmount)),
                    _row('Balance', _money(widget.sale.balanceDue), bold: true),
                    const SizedBox(height: 20),
                    Text(
                      (config['footer'] ?? 'Thank you for your business.')
                          .toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: narrow ? 10 : 12),
                    ),
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
