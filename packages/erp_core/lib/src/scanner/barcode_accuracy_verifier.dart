import '../barcode/barcode_format.dart';
import 'scanner_models.dart';

/// Result of barcode accuracy and check digit verification.
class BarcodeAccuracyResult {
  /// Whether the barcode decoded cleanly and passed symbology check digit validation.
  final bool isValid;

  /// The exact decoded barcode string with strict character and leading zero fidelity.
  final String rawCode;

  /// The validated or inferred barcode format.
  final SmartBarcodeFormat format;

  /// Descriptive reason if the barcode was rejected as a corrupt, truncated, or glitched read.
  final String? rejectionReason;

  /// Sanitized barcode string with leading zeros strictly preserved.
  String get sanitizedCode => rawCode;

  const BarcodeAccuracyResult._({
    required this.isValid,
    required this.rawCode,
    required this.format,
    this.rejectionReason,
  });

  /// Factory for a valid decoded barcode.
  factory BarcodeAccuracyResult.valid({
    required String rawCode,
    required SmartBarcodeFormat format,
  }) {
    return BarcodeAccuracyResult._(
      isValid: true,
      rawCode: rawCode,
      format: format,
    );
  }

  /// Factory for a rejected or corrupted barcode read.
  factory BarcodeAccuracyResult.rejected({
    required String rawCode,
    required SmartBarcodeFormat format,
    required String reason,
  }) {
    return BarcodeAccuracyResult._(
      isValid: false,
      rawCode: rawCode,
      format: format,
      rejectionReason: reason,
    );
  }

  @override
  String toString() => isValid
      ? 'BarcodeAccuracyResult(valid: $rawCode, format: ${format.label})'
      : 'BarcodeAccuracyResult(rejected: $rawCode, format: ${format.label}, reason: $rejectionReason)';
}

/// High-priority camera accuracy verifier.
///
/// Guards against camera decoding artifacts, oblique frame glitches, dropped bits,
/// and truncated partial scans commonly encountered during mobile camera scanning.
///
/// Invariants:
/// 1. Strict leading-zero preservation — strings are never converted to numeric primitives.
/// 2. Symbology checksum enforcement — EAN-13 and UPC-A barcodes MUST pass standard Modulo 10 checks.
/// 3. Character boundary validation — Code 128 barcodes must reside within printable ASCII bounds (32..126).
///    (Note: Mobile camera decoders such as ML Kit strip the mandatory Modulo 103 checksum internally before
///    exposing rawValue; printable ASCII validation ensures data encoding integrity).
/// 4. No silent guessing — if a frame check digit fails, it is rejected immediately with an informative error.
class BarcodeAccuracyVerifier {
  const BarcodeAccuracyVerifier();

  /// Verifies a raw decoded string and format against symbology integrity rules.
  static BarcodeAccuracyResult verify({
    required String rawValue,
    SmartBarcodeFormat format = SmartBarcodeFormat.unknown,
  }) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return BarcodeAccuracyResult.rejected(
        rawCode: rawValue,
        format: format,
        reason: 'Barcode value is empty or contains only whitespace',
      );
    }

    // 1. QR Code / 2D Matrix verification
    if (format == SmartBarcodeFormat.qrCode || format == SmartBarcodeFormat.dataMatrix) {
      return BarcodeAccuracyResult.valid(
        rawCode: trimmed,
        format: format,
      );
    }

    // 2. EAN-13 Symbology Verification (13 numeric digits with Modulo 10 check digit)
    if (format == SmartBarcodeFormat.ean13 || (format == SmartBarcodeFormat.unknown && trimmed.length == 13 && RegExp(r'^\d{13}$').hasMatch(trimmed))) {
      if (trimmed.length != 13 || !RegExp(r'^\d{13}$').hasMatch(trimmed)) {
        return BarcodeAccuracyResult.rejected(
          rawCode: trimmed,
          format: SmartBarcodeFormat.ean13,
          reason: 'EAN-13 requires exactly 13 numeric digits (found ${trimmed.length})',
        );
      }

      final isValidCheck = BarcodeValidator.isValidEan13(trimmed);
      if (!isValidCheck) {
        final expected = BarcodeValidator.calculateEan13CheckDigit(trimmed.substring(0, 12));
        final actual = trimmed[12];
        return BarcodeAccuracyResult.rejected(
          rawCode: trimmed,
          format: SmartBarcodeFormat.ean13,
          reason: 'EAN-13 check digit mismatch (expected $expected, received $actual). Camera frame dropped.',
        );
      }

      return BarcodeAccuracyResult.valid(
        rawCode: trimmed,
        format: SmartBarcodeFormat.ean13,
      );
    }

    // 3. UPC-A Symbology Verification (12 numeric digits with Modulo 10 check digit)
    if (format == SmartBarcodeFormat.upcA || (format == SmartBarcodeFormat.unknown && trimmed.length == 12 && RegExp(r'^\d{12}$').hasMatch(trimmed))) {
      if (trimmed.length != 12 || !RegExp(r'^\d{12}$').hasMatch(trimmed)) {
        return BarcodeAccuracyResult.rejected(
          rawCode: trimmed,
          format: SmartBarcodeFormat.upcA,
          reason: 'UPC-A requires exactly 12 numeric digits (found ${trimmed.length})',
        );
      }

      final isValidCheck = BarcodeValidator.isValidUpcA(trimmed);
      if (!isValidCheck) {
        final expected = BarcodeValidator.calculateUpcACheckDigit(trimmed.substring(0, 11));
        final actual = trimmed[11];
        return BarcodeAccuracyResult.rejected(
          rawCode: trimmed,
          format: SmartBarcodeFormat.upcA,
          reason: 'UPC-A check digit mismatch (expected $expected, received $actual). Camera frame dropped.',
        );
      }

      return BarcodeAccuracyResult.valid(
        rawCode: trimmed,
        format: SmartBarcodeFormat.upcA,
      );
    }

    // 4. Code 128 / Alphanumeric linear format verification
    // NOTE ON CODE 128 CHECK DIGIT:
    // Mobile camera decoding engines (such as Google ML Kit and ZXing) automatically
    // validate and strip the mandatory Modulo 103 check character internally before
    // exposing the decoded `rawValue`. Therefore, verifying that all characters fall within
    // the standard printable ASCII range (32-126) validates data encoding compliance
    // rather than low-level symbology check digit parity.
    if (format == SmartBarcodeFormat.code128) {
      if (!BarcodeValidator.isValidCode128(trimmed)) {
        return BarcodeAccuracyResult.rejected(
          rawCode: trimmed,
          format: SmartBarcodeFormat.code128,
          reason: 'Code 128 data encoding error: contains non-printable characters outside standard printable ASCII range (32-126)',
        );
      }

      return BarcodeAccuracyResult.valid(
        rawCode: trimmed,
        format: SmartBarcodeFormat.code128,
      );
    }

    // 5. General / other recognized formats (Code 39, Code 93, ITF, etc.)
    // Ensure payload does not contain non-printable control characters
    for (var i = 0; i < trimmed.length; i++) {
      final codeUnit = trimmed.codeUnitAt(i);
      if (codeUnit < 32 && codeUnit != 9 && codeUnit != 10 && codeUnit != 13) {
        return BarcodeAccuracyResult.rejected(
          rawCode: trimmed,
          format: format,
          reason: 'Barcode contains non-printable control character at index $i (0x${codeUnit.toRadixString(16)})',
        );
      }
    }

    return BarcodeAccuracyResult.valid(
      rawCode: trimmed,
      format: format == SmartBarcodeFormat.unknown ? SmartBarcodeFormat.code128 : format,
    );
  }
}
