import 'barcode_format.dart';

/// Generator for compliant, conflict-free internal product identifiers and payloads.
///
/// Under GS1 standard allocation:
/// - Prefix '28' is explicitly reserved for restricted circulation / in-store internal use.
///   Generating EAN-13 codes with prefix '28' guarantees zero collision with external manufacturer products.
/// - Prefix '2' is reserved for local UPC-A retail store use.
/// - Prefix 'THQ:PRODUCT:' provides an identifiable namespace for QR codes scanned by mobile and hardware scanners.
class BarcodeGenerator {
  const BarcodeGenerator();

  /// Generates a valid internal 13-digit EAN-13 barcode using GS1 restricted circulation prefix '28'.
  /// Matches Supabase RPC `product_identifier_generate_v482`.
  static String generateInternalEan13(int sequence) {
    if (sequence < 0) throw ArgumentError('Sequence must be non-negative');
    final seqStr = sequence.toString().padLeft(10, '0');
    final seed12 = '28$seqStr';
    final checkDigit = BarcodeValidator.calculateEan13CheckDigit(seed12);
    return '$seed12$checkDigit';
  }

  /// Generates a valid internal 12-digit UPC-A barcode using in-store prefix '2'.
  static String generateInternalUpcA(int sequence) {
    if (sequence < 0) throw ArgumentError('Sequence must be non-negative');
    final seqStr = sequence.toString().padLeft(10, '0');
    final seed11 = '2$seqStr';
    final checkDigit = BarcodeValidator.calculateUpcACheckDigit(seed11);
    return '$seed11$checkDigit';
  }

  /// Generates a compliant Code 128 identifier from an SKU or internal sequence.
  static String generateCode128({required String sku, int? sequence}) {
    final sanitizedSku = sku.trim().replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    if (sanitizedSku.isEmpty) {
      final seqStr = (sequence ?? 1).toString().padLeft(8, '0');
      return 'THQ-$seqStr';
    }
    if (sequence != null) {
      final seqStr = sequence.toString().padLeft(4, '0');
      return '$sanitizedSku-$seqStr';
    }
    return sanitizedSku;
  }

  /// Generates a standard THQ structured QR payload.
  /// Format: `THQ:PRODUCT:<variant_short_id>:<code_or_seq>`
  static String generateThqQrPayload({
    required String variantId,
    required String codeOrSequence,
  }) {
    final cleanId = variantId.replaceAll('-', '').trim();
    final shortId = cleanId.length >= 8 ? cleanId.substring(0, 8) : cleanId;
    final cleanCode = codeOrSequence.trim();
    return 'THQ:PRODUCT:$shortId:$cleanCode';
  }
}

