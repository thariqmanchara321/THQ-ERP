import 'dart:convert';
import 'dart:typed_data';

import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

class MockCatalogRepository implements ProductIdentificationRepository {
  final Map<String, ProductIdentificationMatch> catalog = {};

  void seedProduct({
    required String productId,
    required String variantId,
    required String productName,
    required String sku,
    String? barcode,
  }) {
    final match = ProductIdentificationMatch(
      productId: productId,
      variantId: variantId,
      productName: productName,
      variantName: 'Default',
      sku: sku,
      barcode: barcode,
      sellingPrice: 100.0,
      costPrice: 80.0,
      stockQuantity: 50.0,
      unitCode: 'PCS',
      matchMethod: MatchMethod.exactSku,
      matchedCode: sku,
    );
    catalog[sku.toLowerCase()] = match;
    if (barcode != null) {
      catalog[barcode.toLowerCase()] = match;
    }
  }

  @override
  Future<List<ProductIdentificationMatch>> lookupIdentifier({
    required String tenantId,
    required String code,
    String? locationId,
    Set<String>? allowedTypes,
  }) async {
    final clean = code.trim().toLowerCase();
    if (catalog.containsKey(clean)) {
      return [catalog[clean]!];
    }
    return const [];
  }

  @override
  Future<ProductIdentificationMatch?> lookupVariant({
    required String tenantId,
    required String variantId,
    String? locationId,
  }) async {
    for (final m in catalog.values) {
      if (m.variantId == variantId) return m;
    }
    return null;
  }
}

void main() {
  group('SmartCsvParser Tests', () {
    const parser = SmartCsvParser();

    test('Parses standard comma-separated values', () {
      const csv = 'Name,SKU,Price\nCement,SKU-01,350\nSand,SKU-02,25';
      final result = parser.parseString(csv);

      expect(result.length, 3);
      expect(result[0], ['Name', 'SKU', 'Price']);
      expect(result[1], ['Cement', 'SKU-01', '350']);
      expect(result[2], ['Sand', 'SKU-02', '25']);
    });

    test('Handles quoted fields with commas and escaped double quotes', () {
      const csv =
          'Product,Description,Price\n"Cement, Portland","High-strength ""Grade 53"" bag",380';
      final result = parser.parseString(csv);

      expect(result.length, 2);
      expect(result[1][0], 'Cement, Portland');
      expect(result[1][1], 'High-strength "Grade 53" bag');
      expect(result[1][2], '380');
    });

    test('Preserves multiline cells within quotes', () {
      const csv = 'Name,Details\nItemA,"Line 1\nLine 2\nLine 3"';
      final result = parser.parseString(csv);

      expect(result.length, 2);
      expect(result[1][0], 'ItemA');
      expect(result[1][1], 'Line 1\nLine 2\nLine 3');
    });

    test('Preserves leading zeros in codes and barcodes as strings', () {
      const csv = 'SKU,Barcode\n001245,0089012345678';
      final result = parser.parseString(csv);

      expect(result.length, 2);
      expect(result[1][0], '001245');
      expect(result[1][1], '0089012345678');
    });

    test('Strips UTF-8 BOM byte marker seamlessly', () {
      final bomBytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF, // BOM
        ...utf8.encode('Name,SKU\nHelmet,SAFE-01'),
      ]);

      final result = parser.parseBytes(bomBytes);
      expect(result.length, 2);
      expect(result[0][0], 'Name');
      expect(result[1][0], 'Helmet');
    });

    test('Auto-detects semicolon delimiters', () {
      const csv = 'Name;SKU;Price\nAggregate;AGG-20;32.50';
      final result = parser.parseString(csv);

      expect(result.length, 2);
      expect(result[0], ['Name', 'SKU', 'Price']);
      expect(result[1], ['Aggregate', 'AGG-20', '32.50']);
    });
  });

  group('SmartXlsxParser Tests', () {
    const xlsxParser = SmartXlsxParser();
    const templateGen = SampleTemplateGenerator();

    test('Parses generated XLSX template and lists sheets', () {
      final bytes = templateGen.generateXlsxBytes();
      final sheets = xlsxParser.getWorksheetNames(bytes);

      expect(sheets.isNotEmpty, isTrue);
      final rows = xlsxParser.parseBytes(bytes, sheetName: sheets.first);

      expect(rows.length, 5); // 1 header + 4 sample rows
      expect(rows[0][0], 'Product Name');
      expect(rows[0][1], 'SKU');
      expect(rows[0][2], 'Barcode');
      expect(rows[1][0], 'UltraTech Cement 50kg');
      expect(rows[1][1], 'SKU-CEM-50');
      expect(rows[1][2], '8901030382910');
    });
  });

  group('SmartColumnMapper Tests', () {
    const mapper = SmartColumnMapper();

    test('Auto-maps common supplier headings with high confidence', () {
      final headers = [
        'Item Name',
        'Item Code',
        'Barcode / EAN',
        'Sales Rate',
        'Purchase Price',
        'Item Group',
        'Vendor Brand',
      ];

      final mappings = mapper.autoMapHeaders(headers);

      expect(mappings[0].destinationField, ProductImportField.productName);
      expect(mappings[0].confidence, MappingConfidence.high);

      expect(mappings[1].destinationField, ProductImportField.sku);
      expect(mappings[1].confidence, MappingConfidence.high);

      expect(mappings[2].destinationField, ProductImportField.barcode);
      expect(mappings[2].confidence, MappingConfidence.high);

      expect(mappings[3].destinationField, ProductImportField.sellingPrice);
      expect(mappings[4].destinationField, ProductImportField.costPrice);
      expect(mappings[5].destinationField, ProductImportField.category);
      expect(mappings[6].destinationField, ProductImportField.brand);
    });

    test('Identifies missing required fields', () {
      final headers = ['Description', 'Price', 'Barcode'];
      final mappings = mapper.autoMapHeaders(headers);

      final missing = mapper.findMissingRequiredFields(mappings);
      expect(missing.contains(ProductImportField.productName), isTrue);
      expect(missing.contains(ProductImportField.sku), isTrue);
    });
  });

  group('SmartImportValidator Tests', () {
    const validator = SmartImportValidator();
    final config = const ImportConfiguration(
      tenantId: 'tenant-test',
      allowOpeningStock: false,
      canManageCostPrice: true,
    );

    final mappings = [
      ColumnMapping(
        sourceColumn: 'Product Name',
        sourceColumnIndex: 0,
        destinationField: ProductImportField.productName,
      ),
      ColumnMapping(
        sourceColumn: 'SKU',
        sourceColumnIndex: 1,
        destinationField: ProductImportField.sku,
      ),
      ColumnMapping(
        sourceColumn: 'Selling Price',
        sourceColumnIndex: 2,
        destinationField: ProductImportField.sellingPrice,
      ),
      ColumnMapping(
        sourceColumn: 'Cost Price',
        sourceColumnIndex: 3,
        destinationField: ProductImportField.costPrice,
      ),
      ColumnMapping(
        sourceColumn: 'Tax Rate',
        sourceColumnIndex: 4,
        destinationField: ProductImportField.taxRate,
      ),
      ColumnMapping(
        sourceColumn: 'Opening Stock',
        sourceColumnIndex: 5,
        destinationField: ProductImportField.openingStock,
      ),
    ];

    test('Validates complete correct row', () {
      final raw = ['Steel Rebar 12mm', 'SKU-ST-12', '750.00', '620.00', '18', '0'];
      final row = validator.validateRow(
        sourceRowNumber: 2,
        rawRow: raw,
        mappings: mappings,
        config: config,
      );

      expect(row.isValid, isTrue);
      expect(row.errors.isEmpty, isTrue);
      expect(row.productName, 'Steel Rebar 12mm');
      expect(row.sku, 'SKU-ST-12');
      expect(row.mappedValues[ProductImportField.sellingPrice], 750.00);
      expect(row.mappedValues[ProductImportField.costPrice], 620.00);
      expect(row.mappedValues[ProductImportField.taxRate], 18.0);
    });

    test('Rejects row with missing product name and negative price', () {
      final raw = ['', 'SKU-FAIL', '-10.00', '50.00', '18', '0'];
      final row = validator.validateRow(
        sourceRowNumber: 3,
        rawRow: raw,
        mappings: mappings,
        config: config,
      );

      expect(row.isValid, isFalse);
      expect(row.hasErrors, isTrue);
      expect(row.errors.any((e) => e.field == ProductImportField.productName), isTrue);
      expect(row.errors.any((e) => e.field == ProductImportField.sellingPrice), isTrue);
    });

    test('Opening stock triggers non-mutating warning when disallowed', () {
      final raw = ['M-Sand', 'SKU-MS-01', '30.00', '22.00', '5', '500'];
      final row = validator.validateRow(
        sourceRowNumber: 4,
        rawRow: raw,
        mappings: mappings,
        config: config,
      );

      expect(row.isValid, isTrue);
      expect(row.hasWarnings, isTrue);
      expect(row.warnings.first.message, contains('will not adjust live inventory balances'));
      expect(row.mappedValues[ProductImportField.openingStock], 0.0);
    });

    test('Cost price is suppressed when user lacks financial permission', () {
      final nonManagerConfig = const ImportConfiguration(
        tenantId: 'tenant-test',
        canManageCostPrice: false,
      );

      final raw = ['Gravel 40mm', 'SKU-GR-40', '40.00', '35.00', '5', '0'];
      final row = validator.validateRow(
        sourceRowNumber: 5,
        rawRow: raw,
        mappings: mappings,
        config: nonManagerConfig,
      );

      expect(row.isValid, isTrue);
      expect(row.mappedValues[ProductImportField.costPrice], 0.0);
    });
  });

  group('SmartDuplicateDetector Tests', () {
    late MockCatalogRepository mockRepo;
    late SmartDuplicateDetector detector;
    final config = const ImportConfiguration(tenantId: 'tenant-test');

    setUp(() {
      mockRepo = MockCatalogRepository();
      mockRepo.seedProduct(
        productId: 'prod-01',
        variantId: 'var-01',
        productName: 'UltraTech Cement 50kg',
        sku: 'SKU-CEM-50',
        barcode: '8901030382910',
      );
      detector = SmartDuplicateDetector(catalogRepository: mockRepo);
    });

    test('Detects intra-file duplicate SKUs and flags subsequent row', () async {
      final rows = [
        ImportRow(
          sourceRowNumber: 2,
          rawValues: {},
          mappedValues: {
            ProductImportField.productName: 'Cement Bag A',
            ProductImportField.sku: 'SKU-DUP-01',
          },
          validationStatus: RowValidationStatus.valid,
        ),
        ImportRow(
          sourceRowNumber: 3,
          rawValues: {},
          mappedValues: {
            ProductImportField.productName: 'Cement Bag B',
            ProductImportField.sku: 'SKU-DUP-01',
          },
          validationStatus: RowValidationStatus.valid,
        ),
      ];

      await detector.detectDuplicates(rows: rows, config: config);

      expect(rows[0].duplicateStatus, RowDuplicateStatus.none);
      expect(rows[1].duplicateStatus, RowDuplicateStatus.inSpreadsheet);
      expect(rows[1].isSelectedForImport, isFalse);
      expect(rows[1].duplicateReason, contains('row 2'));
    });

    test('Detects catalog duplicate SKU against live catalog', () async {
      final rows = [
        ImportRow(
          sourceRowNumber: 2,
          rawValues: {},
          mappedValues: {
            ProductImportField.productName: 'UltraTech Cement',
            ProductImportField.sku: 'SKU-CEM-50',
          },
          validationStatus: RowValidationStatus.valid,
        ),
      ];

      await detector.detectDuplicates(rows: rows, config: config);

      expect(rows[0].duplicateStatus, RowDuplicateStatus.inCatalog);
      expect(rows[0].existingProductId, 'prod-01');
      expect(rows[0].existingVariantId, 'var-01');
      expect(rows[0].isSelectedForImport, isFalse); // Skipped under default mode
    });
  });

  group('SmartImportEngine Lifecycle & Batch Tests', () {
    test('End-to-end import run parses, validates, batches, and produces report', () async {
      final engine = SmartImportEngine();
      final templateGen = SampleTemplateGenerator();
      final csvString = templateGen.generateCsv();
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      // 1. Load File
      final importFile = engine.loadFile(fileName: 'products.csv', bytes: bytes);
      expect(importFile.hasError, isFalse);
      expect(importFile.totalRows, 4);

      // 2. Auto-map headers
      final mappings = engine.autoMapHeaders(importFile);
      expect(mappings.any((m) => m.destinationField == ProductImportField.productName), isTrue);
      expect(mappings.any((m) => m.destinationField == ProductImportField.sku), isTrue);

      // 3. Validate
      final config = const ImportConfiguration(tenantId: 'tenant-01');
      final validatedRows = await engine.validateAndDetectDuplicates(
        file: importFile,
        mappings: mappings,
        config: config,
      );
      expect(validatedRows.every((r) => r.isValid), isTrue);

      // 4. Execute Import in batches
      final summary = await engine.executeImport(
        rows: validatedRows,
        config: config,
        onBatchCreate: (batch) async {
          expect(batch.length, 4);
          expect(batch.first['name'], 'UltraTech Cement 50kg');
          expect(batch.first['sku'], 'SKU-CEM-50');
          return {
            'success_count': 4,
            'failed_count': 0,
            'errors': [],
          };
        },
      );

      expect(summary.isFullSuccess, isTrue);
      expect(summary.createdCount, 4);
      expect(summary.failedCount, 0);
      expect(summary.totalSourceRows, 4);

      // 5. Generate error report (empty when no errors)
      final errorCsv = engine.generateErrorReport(summary);
      expect(errorCsv, contains('Row Number,Product Name,SKU,Error Reason'));
    });
  });
}
