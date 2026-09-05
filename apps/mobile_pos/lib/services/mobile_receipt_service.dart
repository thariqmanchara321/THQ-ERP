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
    Map<String, dynamic>? serverResponse,
  }) async {
    final authoritative = synced
        ? await _loadAuthoritativeSale(
            session: session,
            serverResponse: serverResponse,
          )
        : null;

    final sale = _map(authoritative?['sale']);
    final gst = _map(authoritative?['gst']);
    final items = authoritative != null
        ? (authoritative['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : (payload['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

    final total = authoritative != null
        ? numberValue(sale['grand_total'])
        : numberValue(payload['total']);
    final paid = authoritative != null
        ? numberValue(authoritative['paid_amount'])
        : numberValue(payload['initial_payment']);
    final due = authoritative != null
        ? numberValue(authoritative['balance_due'])
        : numberValue(payload['outstanding']);

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          240 * PdfPageFormat.mm,
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
                synced
                    ? _documentTitle(gst['document_class']?.toString())
                    : 'OFFLINE SALE RECEIPT',
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
            if (synced && sale['sale_number'] != null)
              pw.Text('Invoice: ${sale['sale_number']}'),
            pw.Text('Local No: $localNumber'),
            pw.Text(
              'Store: ${session.locationCode} • POS: ${session.deviceCode}',
            ),
            pw.Text(
              'Customer: ${synced ? (sale['customer_name'] ?? '') : (payload['customer_name'] ?? '')}',
            ),
            pw.Text(
              'Date: ${synced ? (sale['sale_date'] ?? sale['created_at'] ?? '') : (payload['sale_time'] ?? payload['sale_date'] ?? '')}',
            ),
            if (synced && gst['supplier_gstin'] != null)
              pw.Text('GSTIN: ${gst['supplier_gstin']}'),
            if (synced && gst['place_of_supply_code'] != null)
              pw.Text('Place of supply: ${gst['place_of_supply_code']}'),
            pw.Divider(),
            ...items.map((item) {
              final quantity = numberValue(item['quantity']);
              final price = numberValue(item['unit_price']);

              // Final/synced invoice: use the persisted server line total.
              // Provisional/offline receipt: local math is allowed only while
              // clearly marked PENDING SERVER SYNC.
              final line = authoritative != null
                  ? numberValue(item['line_total'])
                  : quantity *
                      price *
                      (1 + numberValue(item['tax_rate']) / 100);

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
            if (authoritative != null) ...[
              _row(
                session,
                'TAXABLE',
                numberValue(gst['taxable_total']),
                false,
              ),
              if (numberValue(gst['cgst_total']).abs() > 0.004)
                _row(
                  session,
                  'CGST',
                  numberValue(gst['cgst_total']),
                  false,
                ),
              if (numberValue(gst['sgst_total']).abs() > 0.004)
                _row(
                  session,
                  'SGST',
                  numberValue(gst['sgst_total']),
                  false,
                ),
              if (numberValue(gst['utgst_total']).abs() > 0.004)
                _row(
                  session,
                  'UTGST',
                  numberValue(gst['utgst_total']),
                  false,
                ),
              if (numberValue(gst['igst_total']).abs() > 0.004)
                _row(
                  session,
                  'IGST',
                  numberValue(gst['igst_total']),
                  false,
                ),
              if (numberValue(gst['cess_total']).abs() > 0.004)
                _row(
                  session,
                  'CESS',
                  numberValue(gst['cess_total']),
                  false,
                ),
              _row(
                session,
                'GST TOTAL',
                numberValue(gst['tax_collected_total']),
                false,
              ),
            ],
            _row(session, 'TOTAL', total, true),
            _row(session, 'PAID', paid, false),
            if (due > 0.005) _row(session, 'DUE', due, false),
            pw.SizedBox(height: 8),
            if (!synced)
              pw.Text(
                'Local offline receipt. Final server invoice and authoritative '
                'GST are assigned only after successful synchronization.',
                style: const pw.TextStyle(fontSize: 8),
              ),
            if (synced)
              pw.Text(
                'Authoritative server invoice • GST snapshot verified',
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
    Map<String, dynamic>? serverResponse,
    String? requestId,
  }) async {
    final bytes = await build(
      session: session,
      localNumber: localNumber,
      payload: payload,
      synced: synced,
      serverResponse: serverResponse,
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
    Map<String, dynamic>? serverResponse,
    String? requestId,
  }) async {
    final bytes = await build(
      session: session,
      localNumber: localNumber,
      payload: payload,
      synced: synced,
      serverResponse: serverResponse,
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

  Future<Map<String, dynamic>> _loadAuthoritativeSale({
    required PosSession session,
    required Map<String, dynamic>? serverResponse,
  }) async {
    final response = serverResponse ?? const <String, dynamic>{};
    final saleId = response['sale_id']?.toString().trim() ?? '';
    final expectedSnapshot =
        response['gst_snapshot_id']?.toString().trim() ?? '';

    if (saleId.isEmpty || expectedSnapshot.isEmpty) {
      throw StateError(
        'Synced Mobile POS receipt is missing authoritative sale/GST evidence.',
      );
    }

    final raw = await _supabase.rpc(
      'sales_get_detail_v520',
      params: {
        'p_tenant_id': session.tenantId,
        'p_sale_id': saleId,
      },
    );
    if (raw is! Map) {
      throw StateError('Authoritative sale detail returned an invalid response.');
    }

    final detail = Map<String, dynamic>.from(raw);
    final gst = _map(detail['gst']);
    if (gst['authoritative'] != true) {
      throw StateError(
        'Final Mobile POS receipt is blocked because GST is not authoritative.',
      );
    }

    final actualSnapshot = gst['snapshot_id']?.toString().trim() ?? '';
    if (actualSnapshot.isEmpty || actualSnapshot != expectedSnapshot) {
      throw StateError(
        'Final Mobile POS receipt GST snapshot does not match sync evidence.',
      );
    }

    return detail;
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
      // Receipt output remains available offline. The immutable request/sync
      // record remains authoritative even if this optional event cannot log.
    }
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  String _documentTitle(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'bill_of_supply':
        return 'BILL OF SUPPLY';
      case 'tax_invoice':
        return 'TAX INVOICE';
      default:
        return 'FINAL INVOICE';
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
