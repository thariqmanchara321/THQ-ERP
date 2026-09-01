import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class InvoiceTemplateService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String> _uploadInvoiceImage({
    required String tenantId,
    required Uint8List bytes,
    required String extension,
    required String filePrefix,
    required String assetLabel,
  }) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (!const {'png', 'jpg', 'jpeg'}.contains(ext)) {
      throw Exception('$assetLabel must be a PNG or JPEG image.');
    }
    if (bytes.isEmpty || bytes.lengthInBytes > 5 * 1024 * 1024) {
      throw Exception('$assetLabel must be smaller than 5 MB.');
    }
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final path =
        '$tenantId/invoice/${filePrefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _supabase.storage.from('thq-assets').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mime, upsert: true),
    );
    return _supabase.storage.from('thq-assets').getPublicUrl(path);
  }

  Future<String> uploadBusinessLogo({
    required String tenantId,
    required Uint8List bytes,
    required String extension,
  }) => _uploadInvoiceImage(
    tenantId: tenantId,
    bytes: bytes,
    extension: extension,
    filePrefix: 'logo',
    assetLabel: 'Logo',
  );

  Future<String> uploadPaymentQr({
    required String tenantId,
    required Uint8List bytes,
    required String extension,
  }) => _uploadInvoiceImage(
    tenantId: tenantId,
    bytes: bytes,
    extension: extension,
    filePrefix: 'payment_qr',
    assetLabel: 'Payment QR',
  );

  Future<Map<String, dynamic>> getTemplate({
    required String tenantId,
    required String paperType,
    String? locationId,
    String? deviceId,
  }) async {
    final result = await _supabase.rpc(
      'tenant_invoice_template_get_v45',
      params: {
        'p_tenant_id': tenantId,
        'p_paper_type': paperType,
        'p_location_id': locationId,
        'p_device_id': deviceId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getSaleOrigin({
    required String tenantId,
    required String saleId,
  }) async {
    final result = await _supabase.rpc(
      'document_origin_get',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': 'sale',
        'p_entity_id': saleId,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  Future<void> logEvent({
    required String tenantId,
    required String saleId,
    required String invoiceNumber,
    String? templateId,
    required String action,
    String? deviceId,
  }) async {
    await _supabase.rpc(
      'invoice_print_event_v4',
      params: {
        'p_tenant_id': tenantId,
        'p_entity_type': 'sale',
        'p_entity_id': saleId,
        'p_invoice_number': invoiceNumber,
        'p_template_id': templateId,
        'p_printer_profile_id': null,
        'p_action': action,
        'p_device_id': deviceId,
      },
    );
  }
}
