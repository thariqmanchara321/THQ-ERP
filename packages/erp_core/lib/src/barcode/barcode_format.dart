/// Supported barcode formats for THQ ERP product identification and label printing.
enum LabelBarcodeFormat {
  code128('Code 128', 'High-density alphanumeric format for SKUs and internal codes'),
  ean13('EAN-13', 'Standard 13-digit retail barcode with check digit'),
  upcA('UPC-A', 'Standard 12-digit retail barcode with check digit'),
  qrCode('QR Code', '2D matrix barcode for detailed payloads and URL links');

  final String label;
  final String description;

  const LabelBarcodeFormat(this.label, this.description);

  bool get is2D => this == LabelBarcodeFormat.qrCode;
  bool get isLinear => !is2D;

  static LabelBarcodeFormat fromCode(String code) {
    final lower = code.trim().toLowerCase();
    return switch (lower) {
      'ean13' || 'ean_13' || 'ean-13' => LabelBarcodeFormat.ean13,
      'upca' || 'upc_a' || 'upc-a' || 'upc' => LabelBarcodeFormat.upcA,
      'qr' || 'qrcode' || 'qr_code' || 'qr-code' => LabelBarcodeFormat.qrCode,
      _ => LabelBarcodeFormat.code128,
    };
  }
}

/// Validation, check digit calculations, and payload verification for barcode formats.
class BarcodeValidator {
  const BarcodeValidator();

  /// Calculates the EAN-13 check digit from the first 12 numeric digits.
  /// Formula: Modulo 10 with alternating weights of 1 and 3.
  static int calculateEan13CheckDigit(String data12) {
    if (data12.length != 12 || !RegExp(r'^\d{12}$').hasMatch(data12)) {
      throw ArgumentError('EAN-13 check digit requires exactly 12 numeric digits');
    }

    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.parse(data12[i]);
      sum += (i % 2 == 0) ? digit : (digit * 3);
    }

    return (10 - (sum % 10)) % 10;
  }

  /// Verifies if a string is a complete and valid 13-digit EAN-13 barcode.
  static bool isValidEan13(String code) {
    final trimmed = code.trim();
    if (trimmed.length != 13 || !RegExp(r'^\d{13}$').hasMatch(trimmed)) {
      return false;
    }
    final expectedCheck = calculateEan13CheckDigit(trimmed.substring(0, 12));
    final actualCheck = int.parse(trimmed[12]);
    return expectedCheck == actualCheck;
  }

  /// Calculates the UPC-A check digit from the first 11 numeric digits.
  /// Formula: Modulo 10 with odd positions weighted 3 and even positions weighted 1.
  static int calculateUpcACheckDigit(String data11) {
    if (data11.length != 11 || !RegExp(r'^\d{11}$').hasMatch(data11)) {
      throw ArgumentError('UPC-A check digit requires exactly 11 numeric digits');
    }

    var oddSum = 0;
    var evenSum = 0;
    for (var i = 0; i < 11; i++) {
      final digit = int.parse(data11[i]);
      if (i % 2 == 0) {
        oddSum += digit;
      } else {
        evenSum += digit;
      }
    }

    final total = (oddSum * 3) + evenSum;
    return (10 - (total % 10)) % 10;
  }

  /// Verifies if a string is a complete and valid 12-digit UPC-A barcode.
  static bool isValidUpcA(String code) {
    final trimmed = code.trim();
    if (trimmed.length != 12 || !RegExp(r'^\d{12}$').hasMatch(trimmed)) {
      return false;
    }
    final expectedCheck = calculateUpcACheckDigit(trimmed.substring(0, 11));
    final actualCheck = int.parse(trimmed[11]);
    return expectedCheck == actualCheck;
  }

  /// Verifies if a string is valid for Code 128 (1 to 80 ASCII characters between 32 and 126).
  static bool isValidCode128(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty || trimmed.length > 80) return false;
    for (var i = 0; i < trimmed.length; i++) {
      final unit = trimmed.codeUnitAt(i);
      if (unit < 32 || unit > 126) return false;
    }
    return true;
  }

  /// Verifies if a string is valid for QR code payload (non-empty string up to 2000 chars).
  static bool isValidQrCode(String code) {
    final trimmed = code.trim();
    return trimmed.isNotEmpty && trimmed.length <= 2000;
  }

  /// General format validation dispatcher.
  static bool isValid(LabelBarcodeFormat format, String code) {
    return switch (format) {
      LabelBarcodeFormat.code128 => isValidCode128(code),
      LabelBarcodeFormat.ean13 => isValidEan13(code),
      LabelBarcodeFormat.upcA => isValidUpcA(code),
      LabelBarcodeFormat.qrCode => isValidQrCode(code),
    };
  }

  /// Returns a human-friendly validation error or null if valid.
  static String? getValidationError(LabelBarcodeFormat format, String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return 'Code cannot be empty';

    switch (format) {
      case LabelBarcodeFormat.code128:
        if (trimmed.length > 80) return 'Code 128 exceeds 80 characters maximum';
        for (var i = 0; i < trimmed.length; i++) {
          final unit = trimmed.codeUnitAt(i);
          if (unit < 32 || unit > 126) {
            return 'Code 128 contains invalid character at index $i';
          }
        }
        return null;

      case LabelBarcodeFormat.ean13:
        if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
          return 'EAN-13 must contain digits only';
        }
        if (trimmed.length != 13) {
          return 'EAN-13 must be exactly 13 digits (found ${trimmed.length})';
        }
        final expected = calculateEan13CheckDigit(trimmed.substring(0, 12));
        final actual = int.parse(trimmed[12]);
        if (expected != actual) {
          return 'Invalid EAN-13 check digit: expected $expected, found $actual';
        }
        return null;

      case LabelBarcodeFormat.upcA:
        if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
          return 'UPC-A must contain digits only';
        }
        if (trimmed.length != 12) {
          return 'UPC-A must be exactly 12 digits (found ${trimmed.length})';
        }
        final expected = calculateUpcACheckDigit(trimmed.substring(0, 11));
        final actual = int.parse(trimmed[11]);
        if (expected != actual) {
          return 'Invalid UPC-A check digit: expected $expected, found $actual';
        }
        return null;

      case LabelBarcodeFormat.qrCode:
        if (trimmed.length > 2000) return 'QR Code payload exceeds 2000 characters';
        return null;
    }
  }
}

