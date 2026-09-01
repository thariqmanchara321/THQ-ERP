import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pos_models.dart';
import '../models/pos_session.dart';

class MobileReceiptService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Uint8List> build({
    required PosSession session,
    required String localNumber,
    required Map<String, dynamic> payload,
    required bool synced,
  }) async {
    final doc = pw.Document();
    final items = (payload['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          200 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                session.businessName,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                synced ? 'MOBILE POS RECEIPT' : 'OFFLINE SALE RECEIPT',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (!synced)
              pw.Center(
                child: pw.Text(
                  'PENDING SERVER SYNC',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
              ),
            pw.Divider(),
            pw.Text('Local No: $localNumber'),
            pw.Text(
              'Store: ${session.locationCode} • POS: ${session.deviceCode}',
            ),
            pw.Text('Customer: ${payload['customer_name'] ?? ''}'),
            pw.Text(
              'Date: ${payload['sale_time'] ?? payload['sale_date'] ?? ''}',
            ),
            pw.Divider(),
            ...items.map((item) {
              final quantity = numberValue(item['quantity']);
              final price = numberValue(item['unit_price']);
              final tax = numberValue(item['tax_rate']);
              final line = quantity * price * (1 + tax / 100);
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      item['product_name']?.toString() ??
                          item['sku']?.toString() ??
                          'Item',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '${_q(quantity)} ${item['unit_code'] ?? ''} × '
                          '${_money(session, price)}',
                        ),
                        pw.Text(_money(session, line)),
                      ],
                    ),
                    if ((item['serial_numbers'] as List?)?.isNotEmpty == true)
                      pw.Text(
                        'Serial: ${(item['serial_numbers'] as List).join(', ')}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                  ],
                ),
              );
            }),
            pw.Divider(),
            _row(session, 'TOTAL', numberValue(payload['total']), true),
            _row(
              session,
              'PAID',
              numberValue(payload['initial_payment']),
              false,
            ),
            if (numberValue(payload['outstanding']) > 0.005)
              _row(
                session,
                'DUE',
                numberValue(payload['outstanding']),
                false,
              ),
            pw.SizedBox(height: 8),
            if (!synced)
              pw.Text(
                'Local offline receipt. Final server invoice and authoritative '
                'GST are assigned only after successful synchronization.',
                style: const pw.TextStyle(fontSize: 8),
              ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<void> printReceipt({
    required PosSession session,
    required String localNumber,
    required Map<String, dynamic> payload,
    required bool synced,
    String? requestId,
  }) async {
    final bytes = await build(
      session: session,
      localNumber: localNumber,
      payload: payload,
      synced: synced,
    );
    await Printing.layoutPdf(
      onLayout: (_) => bytes,
      name: 'THQ $localNumber',
    );
    await _recordEvent(
      session: session,
      requestId: requestId,
      eventType: 'print',
      localNumber: localNumber,
    );
  }

  Future<void> shareReceipt({
    required PosSession session,
    required String localNumber,
    required Map<String, dynamic> payload,
    required bool synced,
    String? requestId,
  }) async {
    final bytes = await build(
      session: session,
      localNumber: localNumber,
      payload: payload,
      synced: synced,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: '$localNumber.pdf',
    );
    await _recordEvent(
      session: session,
      requestId: requestId,
      eventType: 'share',
      localNumber: localNumber,
    );
  }

  Future<void> _recordEvent({
    required PosSession session,
    required String? requestId,
    required String eventType,
    required String localNumber,
  }) async {
    final id = requestId?.trim() ?? '';
    if (id.isEmpty) return;
    try {
      await _supabase.rpc(
        'mobile_pos_receipt_event_v520',
        params: {
          'p_tenant_id': session.tenantId,
          'p_device_id': session.deviceId,
          'p_request_id': id,
          'p_event_type': eventType,
          'p_local_invoice_number': localNumber,
        },
      );
    } catch (_) {
      // Receipt output must remain available offline. The sale's immutable
      // request/sync audit remains authoritative even if this optional event
      // cannot be logged while disconnected.
    }
  }

  pw.Widget _row(
    PosSession session,
    String label,
    double value,
    bool bold,
  ) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
          ),
          pw.Text(
            _money(session, value),
            style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
          ),
        ],
      );

  String _q(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3);

  String _money(PosSession session, double value) =>
      '${session.currencyCode} ${value.toStringAsFixed(2)}';
}
