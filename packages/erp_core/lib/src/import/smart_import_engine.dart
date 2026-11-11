import 'dart:typed_data';

import 'csv_parser.dart';
import 'smart_column_mapper.dart';
import 'smart_duplicate_detector.dart';
import 'smart_import_models.dart';
import 'smart_import_validator.dart';
import 'xlsx_parser.dart';

/// Orchestrates the entire Smart Excel/CSV Import lifecycle:
/// File Loading -> Sheet Selection -> Column Mapping -> Validation ->
/// Duplicate Detection -> Batch Execution -> Error Reporting.
class SmartImportEngine {
  final SmartCsvParser csvParser;
  final SmartXlsxParser xlsxParser;
  final SmartColumnMapper columnMapper;
  final SmartImportValidator validator;
  final SmartDuplicateDetector duplicateDetector;

  const SmartImportEngine({
    this.csvParser = const SmartCsvParser(),
    this.xlsxParser = const SmartXlsxParser(),
    this.columnMapper = const SmartColumnMapper(),
    this.validator = const SmartImportValidator(),
    this.duplicateDetector = const SmartDuplicateDetector(),
  });

  /// Loads and parses raw file bytes, identifying headers and raw rows.
  ImportFile loadFile({
    required String fileName,
    required Uint8List bytes,
    String? sheetName,
  }) {
    final lowerName = fileName.toLowerCase();
    final isCsv = lowerName.endsWith('.csv') || lowerName.endsWith('.tsv');
    final isXlsx = lowerName.endsWith('.xlsx');

    if (!isCsv && !isXlsx) {
      return ImportFile(
        fileName: fileName,
        fileType: ImportFileType.unknown,
        sizeBytes: bytes.length,
        bytes: bytes,
        parseError: 'Unsupported file format. Please upload a .csv or .xlsx file.',
      );
    }

    try {
      if (isCsv) {
        final parsedTable = csvParser.parseBytes(bytes);
        if (parsedTable.isEmpty) {
          return ImportFile(
            fileName: fileName,
            fileType: ImportFileType.csv,
            sizeBytes: bytes.length,
            bytes: bytes,
            parseError: 'The CSV file is empty.',
          );
        }

        final headers = parsedTable.first;
        final rawRows = parsedTable.skip(1).toList();

        return ImportFile(
          fileName: fileName,
          fileType: ImportFileType.csv,
          sizeBytes: bytes.length,
          bytes: bytes,
          headers: headers,
          rows: _createInitialRows(headers, rawRows),
        );
      } else {
        // XLSX
        final sheets = xlsxParser.getWorksheetNames(bytes);
        if (sheets.isEmpty) {
          return ImportFile(
            fileName: fileName,
            fileType: ImportFileType.xlsx,
            sizeBytes: bytes.length,
            bytes: bytes,
            parseError: 'The Excel workbook contains no valid worksheets.',
          );
        }

        final effectiveSheet = (sheetName != null && sheets.contains(sheetName))
            ? sheetName
            : sheets.first;

        final parsedTable = xlsxParser.parseBytes(bytes, sheetName: effectiveSheet);
        if (parsedTable.isEmpty) {
          return ImportFile(
            fileName: fileName,
            fileType: ImportFileType.xlsx,
            sizeBytes: bytes.length,
            bytes: bytes,
            worksheetNames: sheets,
            selectedWorksheet: effectiveSheet,
            parseError: 'Worksheet "$effectiveSheet" is empty.',
          );
        }

        final headers = parsedTable.first;
        final rawRows = parsedTable.skip(1).toList();

        return ImportFile(
          fileName: fileName,
          fileType: ImportFileType.xlsx,
          sizeBytes: bytes.length,
          bytes: bytes,
          worksheetNames: sheets,
          selectedWorksheet: effectiveSheet,
          headers: headers,
          rows: _createInitialRows(headers, rawRows),
        );
      }
    } catch (e) {
      return ImportFile(
        fileName: fileName,
        fileType: isCsv ? ImportFileType.csv : ImportFileType.xlsx,
        sizeBytes: bytes.length,
        bytes: bytes,
        parseError: 'Failed to read file: $e',
      );
    }
  }

  /// Automatically derives column mappings based on headers and sample rows.
  List<ColumnMapping> autoMapHeaders(ImportFile file) {
    final sampleRows = file.rows
        .take(5)
        .map((r) => file.headers.map((h) => r.rawValues[h]?.toString() ?? '').toList())
        .toList();

    return columnMapper.autoMapHeaders(file.headers, sampleRows: sampleRows);
  }

  /// Validates all rows in the file and checks for duplicates.
  ///
  /// CRITICAL RULE: Zero database writes occur during this phase.
  Future<List<ImportRow>> validateAndDetectDuplicates({
    required ImportFile file,
    required List<ColumnMapping> mappings,
    required ImportConfiguration config,
    void Function(int current, int total)? onProgress,
  }) async {
    final validatedRows = <ImportRow>[];
    final total = file.rows.length;

    for (var i = 0; i < total; i++) {
      final initialRow = file.rows[i];
      final rawList = file.headers
          .map((h) => initialRow.rawValues[h]?.toString() ?? '')
          .toList();

      final validated = validator.validateRow(
        sourceRowNumber: initialRow.sourceRowNumber,
        rawRow: rawList,
        mappings: mappings,
        config: config,
      );
      validatedRows.add(validated);

      if (onProgress != null && (i % 20 == 0 || i == total - 1)) {
        onProgress(i + 1, total);
      }
    }

    // Run duplicate detection pass
    await duplicateDetector.detectDuplicates(
      rows: validatedRows,
      config: config,
    );

    return validatedRows;
  }

  /// Executes the actual import against backend services in controlled batches.
  Future<ImportExecutionSummary> executeImport({
    required List<ImportRow> rows,
    required ImportConfiguration config,
    required Future<Map<String, dynamic>> Function(List<Map<String, dynamic>> batch)
        onBatchCreate,
    Future<void> Function(ImportRow row)? onUpdateProduct,
    void Function(int processed, int total)? onProgress,
    int batchSize = 50,
  }) async {
    final stopwatch = Stopwatch()..start();

    var validCount = 0;
    var invalidCount = 0;
    var duplicateCount = 0;
    var createdCount = 0;
    var updatedCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    final failures = <ImportFailureItem>[];

    final createQueue = <ImportRow>[];
    final updateQueue = <ImportRow>[];

    for (final row in rows) {
      if (row.hasErrors) {
        invalidCount++;
        skippedCount++;
        continue;
      }

      validCount++;

      if (row.isDuplicate) {
        duplicateCount++;
        if (!row.isSelectedForImport) {
          skippedCount++;
          continue;
        }

        if (config.duplicateMode == DuplicateHandlingMode.updateExisting) {
          updateQueue.add(row);
          continue;
        }
      }

      if (row.isSelectedForImport) {
        createQueue.add(row);
      } else {
        skippedCount++;
      }
    }

    final totalToProcess = createQueue.length + updateQueue.length;
    var processedCount = 0;

    // 1. Process batch creates
    for (var i = 0; i < createQueue.length; i += batchSize) {
      final chunk = createQueue.skip(i).take(batchSize).toList();
      final payloadRows = chunk.map(_formatCreatePayload).toList();

      try {
        final result = await onBatchCreate(payloadRows);
        final success = (result['success_count'] as num?)?.toInt() ?? 0;
        final failed = (result['failed_count'] as num?)?.toInt() ?? 0;
        final errors = result['errors'] as List? ?? const [];

        createdCount += success;
        failedCount += failed;

        for (final err in errors) {
          if (err is Map) {
            final rowNum = (err['row'] as num?)?.toInt() ?? 0;
            final sku = err['sku']?.toString() ?? '';
            final msg = err['error']?.toString() ?? 'Batch create failed';
            final matchedRow = chunk.firstWhere(
              (r) => r.sku == sku,
              orElse: () => chunk.first,
            );

            failures.add(
              ImportFailureItem(
                sourceRowNumber: rowNum > 0 ? rowNum : matchedRow.sourceRowNumber,
                productName: matchedRow.productName,
                sku: sku.isNotEmpty ? sku : matchedRow.sku,
                error: msg,
              ),
            );
          } else {
            failures.add(
              ImportFailureItem(
                sourceRowNumber: chunk.first.sourceRowNumber,
                productName: chunk.first.productName,
                sku: chunk.first.sku,
                error: err.toString(),
              ),
            );
          }
        }
      } catch (e) {
        failedCount += chunk.length;
        for (final row in chunk) {
          failures.add(
            ImportFailureItem(
              sourceRowNumber: row.sourceRowNumber,
              productName: row.productName,
              sku: row.sku,
              error: e.toString(),
            ),
          );
        }
      }

      processedCount += chunk.length;
      onProgress?.call(processedCount, totalToProcess);
    }

    // 2. Process updates (if authorized and provided)
    if (onUpdateProduct != null) {
      for (final row in updateQueue) {
        try {
          await onUpdateProduct(row);
          updatedCount++;
        } catch (e) {
          failedCount++;
          failures.add(
            ImportFailureItem(
              sourceRowNumber: row.sourceRowNumber,
              productName: row.productName,
              sku: row.sku,
              error: e.toString(),
            ),
          );
        }
        processedCount++;
        onProgress?.call(processedCount, totalToProcess);
      }
    } else {
      skippedCount += updateQueue.length;
    }

    stopwatch.stop();

    return ImportExecutionSummary(
      totalSourceRows: rows.length,
      validRows: validCount,
      invalidRows: invalidCount,
      duplicateRows: duplicateCount,
      createdCount: createdCount,
      updatedCount: updatedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      failures: failures,
      duration: stopwatch.elapsed,
      isCompleted: true,
    );
  }

  /// Exports an error CSV string for download when import encounters failures.
  String generateErrorReport(ImportExecutionSummary summary) {
    final buffer = StringBuffer();
    buffer.writeln('Row Number,Product Name,SKU,Error Reason');
    for (final failure in summary.failures) {
      final name = _quote(failure.productName);
      final sku = _quote(failure.sku);
      final err = _quote(failure.error);
      buffer.writeln('${failure.sourceRowNumber},$name,$sku,$err');
    }
    return buffer.toString();
  }

  Map<String, dynamic> _formatCreatePayload(ImportRow row) {
    final mv = row.mappedValues;
    return {
      'name': row.productName,
      'sku': row.sku,
      'barcode': row.barcode ?? '',
      'description': mv[ProductImportField.description]?.toString() ?? '',
      'category': mv[ProductImportField.category]?.toString() ?? '',
      'brand': mv[ProductImportField.brand]?.toString() ?? '',
      'unit': mv[ProductImportField.unit]?.toString() ?? 'PCS',
      'item_type': mv[ProductImportField.itemType]?.toString() ?? 'stock',
      'selling_price': mv[ProductImportField.sellingPrice] ?? 0.0,
      'cost_price': mv[ProductImportField.costPrice] ?? 0.0,
      'list_price': mv[ProductImportField.listPrice],
      'tax_rate': mv[ProductImportField.taxRate] ?? 0.0,
      'reorder_level': mv[ProductImportField.reorderLevel] ?? 0.0,
      'part_number': mv[ProductImportField.partNumber]?.toString() ?? '',
      'opening_stock': mv[ProductImportField.openingStock] ?? 0.0,
    };
  }

  List<ImportRow> _createInitialRows(
      List<String> headers, List<List<String>> rawTable) {
    final rows = <ImportRow>[];
    for (var i = 0; i < rawTable.length; i++) {
      final rawList = rawTable[i];
      final rawMap = <String, dynamic>{};
      for (var col = 0; col < headers.length; col++) {
        final val = col < rawList.length ? rawList[col] : '';
        rawMap[headers[col]] = val;
      }
      rows.add(
        ImportRow(
          sourceRowNumber: i + 2, // 1-based, considering row 1 is header
          rawValues: rawMap,
        ),
      );
    }
    return rows;
  }

  static String _quote(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
