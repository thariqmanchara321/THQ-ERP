import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BarcodeValidator EAN-13 Tests', () {
    test('calculateEan13CheckDigit computes correct check digits for known codes', () {
      // Stabilo Boss EAN-13: 4006381333931
      expect(BarcodeValidator.calculateEan13CheckDigit('400638133393'), 1);

      // In-store sequence 1: 280000000001
      // Sum: 2*1 + 8*3 + 0 + 0 + 0 + 0 + 0 + 0 + 0 + 0 + 0*1 + 1*3 = 2 + 24 + 3 = 29
      // (10 - (29 % 10)) % 10 = 1
      expect(BarcodeValidator.calculateEan13CheckDigit('280000000001'), 1);

      // Standard retail test barcode
      expect(BarcodeValidator.calculateEan13CheckDigit('735005385001'), 9);
    });

    test('isValidEan13 validates full 13-digit codes accurately', () {
      expect(BarcodeValidator.isValidEan13('4006381333931'), isTrue);
      expect(BarcodeValidator.isValidEan13('2800000000011'), isTrue);
      expect(BarcodeValidator.isValidEan13('7350053850019'), isTrue);

      // Preserves leading zeros
      const leadingZeroCode = '0012345678905';
      final expectedCheck = BarcodeValidator.calculateEan13CheckDigit('001234567890');
      expect(expectedCheck, 5);
      expect(BarcodeValidator.isValidEan13(leadingZeroCode), isTrue);
    });

    test('isValidEan13 rejects invalid lengths, wrong check digits, and non-numeric chars', () {
      // Wrong check digit (1 expected, got 2)
      expect(BarcodeValidator.isValidEan13('4006381333932'), isFalse);
      // Too short
      expect(BarcodeValidator.isValidEan13('40063813339'), isFalse);
      // Too long
      expect(BarcodeValidator.isValidEan13('40063813339310'), isFalse);
      // Non-numeric
      expect(BarcodeValidator.isValidEan13('400638133393A'), isFalse);
    });

    test('getValidationError returns descriptive message for EAN-13', () {
      expect(BarcodeValidator.getValidationError(LabelBarcodeFormat.ean13, '4006381333931'), isNull);
      expect(BarcodeValidator.getValidationError(LabelBarcodeFormat.ean13, '123'), contains('exactly 13 digits'));
      expect(BarcodeValidator.getValidationError(LabelBarcodeFormat.ean13, '4006381333932'), contains('Invalid EAN-13 check digit'));
      expect(BarcodeValidator.getValidationError(LabelBarcodeFormat.ean13, 'ABC1234567890'), contains('digits only'));
    });
  });

  group('BarcodeValidator UPC-A Tests', () {
    test('calculateUpcACheckDigit computes correct check digits for known codes', () {
      // Known UPC-A: 036000291452
      expect(BarcodeValidator.calculateUpcACheckDigit('03600029145'), 2);

      // In-store sequence: 20000000001 -> (2+0+0+0+0+1)*3 + 0 = 9 -> check digit 1
      expect(BarcodeValidator.calculateUpcACheckDigit('20000000001'), 1);
    });

    test('isValidUpcA validates full 12-digit codes and rejects corruptions', () {
      expect(BarcodeValidator.isValidUpcA('036000291452'), isTrue);
      expect(BarcodeValidator.isValidUpcA('200000000011'), isTrue);

      // Wrong check digit
      expect(BarcodeValidator.isValidUpcA('036000291459'), isFalse);
      // Wrong length
      expect(BarcodeValidator.isValidUpcA('03600029145'), isFalse);
      // Non-numeric
      expect(BarcodeValidator.isValidUpcA('03600029145A'), isFalse);
    });
  });

  group('BarcodeValidator Code 128 & QR Code Tests', () {
    test('isValidCode128 accepts valid ASCII and rejects non-ASCII / oversized', () {
      expect(BarcodeValidator.isValidCode128('SKU-CEM-PPC-50'), isTrue);
      expect(BarcodeValidator.isValidCode128('ITEM 1234/ABC'), isTrue);
      expect(BarcodeValidator.isValidCode128(''), isFalse);
      expect(BarcodeValidator.isValidCode128('A' * 81), isFalse);
      // Unicode emoji
      expect(BarcodeValidator.isValidCode128('SKU-📦-50'), isFalse);
    });

    test('isValidQrCode validates payloads', () {
      expect(BarcodeValidator.isValidQrCode('THQ:PRODUCT:a1b2c3d4:SKU-100'), isTrue);
      expect(BarcodeValidator.isValidQrCode('https://erp.thq.com/p/12345'), isTrue);
      expect(BarcodeValidator.isValidQrCode(''), isFalse);
    });
  });

  group('BarcodeGenerator Tests', () {
    test('generateInternalEan13 generates valid 13-digit code with prefix 28 and verified check digit', () {
      final code1 = BarcodeGenerator.generateInternalEan13(1);
      expect(code1.length, 13);
      expect(code1.startsWith('280000000001'), isTrue);
      expect(BarcodeValidator.isValidEan13(code1), isTrue);

      final code999 = BarcodeGenerator.generateInternalEan13(999);
      expect(code999.length, 13);
      expect(code999.startsWith('280000000999'), isTrue);
      expect(BarcodeValidator.isValidEan13(code999), isTrue);
    });

    test('generateInternalUpcA generates valid 12-digit code with prefix 2', () {
      final code = BarcodeGenerator.generateInternalUpcA(5);
      expect(code.length, 12);
      expect(code.startsWith('20000000005'), isTrue);
      expect(BarcodeValidator.isValidUpcA(code), isTrue);
    });

    test('generateCode128 formats sanitized alphanumeric codes', () {
      expect(BarcodeGenerator.generateCode128(sku: 'SKU-STEEL-12'), 'SKU-STEEL-12');
      expect(BarcodeGenerator.generateCode128(sku: 'SKU-STEEL', sequence: 2), 'SKU-STEEL-0002');
      expect(BarcodeGenerator.generateCode128(sku: '', sequence: 7), 'THQ-00000007');
    });

    test('generateThqQrPayload creates structured namespaced payloads', () {
      final payload = BarcodeGenerator.generateThqQrPayload(
        variantId: 'e2b5c879-1111-2222-3333-444455556666',
        codeOrSequence: 'SKU-CEMENT-50',
      );
      expect(payload, 'THQ:PRODUCT:e2b5c879:SKU-CEMENT-50');
      expect(BarcodeValidator.isValidQrCode(payload), isTrue);
    });
  });

  group('LabelTemplate & Presets Tests', () {
    test('standardPresets includes both thermal and A4 options', () {
      final presets = LabelTemplate.standardPresets;
      expect(presets.length, 6);
      expect(presets.any((t) => t.paperMode == PaperMode.thermal), isTrue);
      expect(presets.any((t) => t.paperMode == PaperMode.a4), isTrue);
    });

    test('LabelTemplate serializes and deserializes consistently', () {
      const template = LabelTemplate(
        code: 'TEST_CUSTOM',
        name: 'Test Custom Template',
        paperMode: PaperMode.a4,
        widthMm: 70.0,
        heightMm: 37.0,
        columns: 3,
        rows: 8,
        showBusiness: true,
        showProduct: true,
        showPrice: true,
        showSku: true,
        showCodeText: true,
        showBrand: true,
        barcodeFormat: LabelBarcodeFormat.ean13,
      );

      final map = template.toMap();
      final restored = LabelTemplate.fromMap(map);

      expect(restored.code, 'TEST_CUSTOM');
      expect(restored.name, 'Test Custom Template');
      expect(restored.paperMode, PaperMode.a4);
      expect(restored.widthMm, 70.0);
      expect(restored.heightMm, 37.0);
      expect(restored.columns, 3);
      expect(restored.rows, 8);
      expect(restored.barcodeFormat, LabelBarcodeFormat.ean13);
      expect(restored.showBrand, isTrue);
    });

    test('LabelPrintItem calculates formatted price with INR currency default', () {
      const item = LabelPrintItem(
        productId: 'p-1',
        variantId: 'v-1',
        productName: 'Cement Bag',
        sku: 'SKU-CEM',
        code: '2800000000011',
        sellingPrice: 380.0,
        copies: 5,
      );

      expect(item.priceText, 'Rs. 380.00');
      expect(item.copies, 5);

      final itemUsd = item.copyWith(currencyCode: 'USD');
      expect(itemUsd.priceText, 'USD 380.00');
    });
  });
}
