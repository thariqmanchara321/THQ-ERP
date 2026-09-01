import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/client_session.dart';
import 'offline_pos_service.dart';
import 'pos_hardware_service.dart';

class OfflineReceiptService {
  final OfflinePosService _local = OfflinePosService.instance;
  final PosHardwareService _hardware = PosHardwareService();

  Future<String?> printQueuedReceipt({
    required ClientSession session,
    required String localInvoiceNumber,
    required Map<String, dynamic> payload,
  }) async {
    final device = session.device;
    if (device == null) return 'No POS device context is available for printing.';
    final raw = await _local.getMeta('printer:${session.business.id}:${device.deviceId}');
    if (raw is! Map) return 'No cached invoice printer is available. Sync once while online to cache printer settings.';
    final profile = Map<String, dynamic>.from(raw);
    final printerName = profile['printer_name']?.toString().trim() ?? '';
    if (printerName.isEmpty) return 'The cached invoice printer has no printer name.';
    final paper = profile['paper_size']?.toString().toLowerCase() ?? '80mm';
    final bytes = await _build(
      session: session,
      localInvoiceNumber: localInvoiceNumber,
      payload: payload,
      paper: paper,
    );
    final copies = ((profile['copies'] as num?)?.toInt() ?? 1).clamp(1, 10);
    for (var i = 0; i < copies; i++) {
      await _hardware.directPrintPdfBytes(
        printerName: printerName,
        bytes: bytes,
        jobName: 'Offline $localInvoiceNumber',
      );
    }
    if (payload['payment_method']?.toString() == 'cash' && profile['cash_drawer_enabled'] == true) {
      await _hardware.openCashDrawer(
        printerName: printerName,
        command: profile['cash_drawer_command']?.toString() ?? 'standard',
      );
    }
    return null;
  }

  Future<Uint8List> _build({
    required ClientSession session,
    required String localInvoiceNumber,
    required Map<String, dynamic> payload,
    required String paper,
  }) async {
    final narrow = paper != 'a4';
    final page = narrow
        ? PdfPageFormat(80 * PdfPageFormat.mm, 190 * PdfPageFormat.mm, marginAll: 4 * PdfPageFormat.mm)
        : PdfPageFormat.a4;
    final doc = pw.Document();
    final items = (payload['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final total = _number(payload['total']);
    final paid = _number(payload['initial_payment']);
    final outstanding = _number(payload['outstanding']);
    doc.addPage(
      pw.Page(
        pageFormat: page,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(child: pw.Text(session.business.name, style: pw.TextStyle(fontSize: narrow ? 13 : 20, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 4),
            pw.Center(child: pw.Text('OFFLINE SALE RECEIPT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text('PENDING SERVER SYNC', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            pw.Divider(),
            pw.Text('Local No: $localInvoiceNumber'),
            pw.Text('Date: ${payload['sale_time'] ?? payload['sale_date'] ?? ''}'),
            pw.Text('POS: ${session.device?.deviceCode ?? ''} • ${session.device?.locationCode ?? ''}'),
            pw.Text('Customer: ${payload['customer_name'] ?? ''}'),
            pw.Divider(),
            ...items.map((item) {
              final qty = _number(item['quantity']);
              final price = _number(item['unit_price']);
              final discount = _number(item['discount_amount']);
              final tax = _number(item['tax_rate']);
              final taxable = (qty * price - discount).clamp(0, double.infinity).toDouble();
              final line = taxable * (1 + tax / 100);
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(item['product_name']?.toString() ?? item['sku']?.toString() ?? 'Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text('${_q(qty)} ${item['unit_code'] ?? ''} × ${_money(session, price)}'),
                    pw.Text(_money(session, line)),
                  ]),
                  if ((item['serial_numbers'] as List?)?.isNotEmpty == true)
                    pw.Text('Serial: ${(item['serial_numbers'] as List).join(', ')}', style: const pw.TextStyle(fontSize: 8)),
                ]),
              );
            }),
            pw.Divider(),
            _moneyRow(session, 'TOTAL', total, bold: true),
            _moneyRow(session, 'PAID', paid),
            if (outstanding > 0.005) _moneyRow(session, 'ACCOUNT DUE', outstanding),
            pw.SizedBox(height: 8),
            pw.Text(
              'This is a local offline receipt. The final THQ invoice number is assigned only after server synchronization. Keep this receipt until sync is confirmed.',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  pw.Widget _moneyRow(ClientSession session, String label, double value, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
          pw.Text(_money(session, value), style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
        ],
      );

  double _number(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
  String _q(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(3);
  String _money(ClientSession session, double value) => session.currencyCode == 'INR' ? 'INR ${value.toStringAsFixed(2)}' : '${session.currencyCode} ${value.toStringAsFixed(2)}';
}
