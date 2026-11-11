import 'dart:typed_data';

/// The supported file types for Smart Product Import.
enum ImportFileType {
  csv,
  xlsx,
  unknown,
}

/// Destination fields in THQ ERP product catalogue.
enum ProductImportField {
  productName('Product Name', isRequired: true),
  sku('SKU', isRequired: true),
  barcode('Barcode', isRequired: false),
  description('Description', isRequired: false),
  category('Category', isRequired: false),
  brand('Brand', isRequired: false),
  unit('Base Unit', isRequired: false),
  itemType('Item Type', isRequired: false),
  sellingPrice('Selling Price', isRequired: false),
  costPrice('Cost Price', isRequired: false),
  listPrice('List Price (MRP)', isRequired: false),
  taxRate('Tax Rate (%)', isRequired: false),
  reorderLevel('Reorder Level', isRequired: false),
  partNumber('Part Number / OEM', isRequired: false),
  openingStock('Opening Stock', isRequired: false),
  variantName('Variant Name', isRequired: false),
  ignore('Do Not Import', isRequired: false);

  final String label;
  final bool isRequired;

  const ProductImportField(this.label, {required this.isRequired});
}

/// Mapping confidence level calculated by the automatic matching engine.
enum MappingConfidence {
  high,
  medium,
  low,
  unmapped,
}

/// Duplicate handling mode selected by the user.
enum DuplicateHandlingMode {
  skipDuplicates('Skip Duplicates (Recommended)'),
  importNewOnly('Import New Products Only'),
  updateExisting('Update Existing Products');

  final String label;
  const DuplicateHandlingMode(this.label);
}

/// Duplicate status classification for an individual spreadsheet row.
enum RowDuplicateStatus {
  none,
  inSpreadsheet,
  inCatalog,
  conflict,
}

/// Validation status of an individual row.
enum RowValidationStatus {
  pending,
  valid,
  invalid,
}

/// Row-level error descriptor.
class ImportRowError {
  final ProductImportField? field;
  final String columnName;
  final dynamic providedValue;
  final String message;
  final String? suggestion;

  const ImportRowError({
    this.field,
    required this.columnName,
    this.providedValue,
    required this.message,
    this.suggestion,
  });

  @override
  String toString() => '$columnName: $message';
}

/// Row-level warning descriptor.
class ImportRowWarning {
  final ProductImportField? field;
  final String columnName;
  final String message;

  const ImportRowWarning({
    this.field,
    required this.columnName,
    required this.message,
  });

  @override
  String toString() => '$columnName: $message';
}

/// A mapping definition between a source spreadsheet column and a destination product field.
class ColumnMapping {
  final String sourceColumn;
  final int sourceColumnIndex;
  ProductImportField destinationField;
  MappingConfidence confidence;
  bool isManualOverride;
  final List<String> sampleValues;

  ColumnMapping({
    required this.sourceColumn,
    required this.sourceColumnIndex,
    required this.destinationField,
    this.confidence = MappingConfidence.unmapped,
    this.isManualOverride = false,
    List<String>? sampleValues,
  }) : sampleValues = sampleValues ?? <String>[];

  bool get isIgnored => destinationField == ProductImportField.ignore;
  bool get isMapped => destinationField != ProductImportField.ignore;

  ColumnMapping copyWith({
    ProductImportField? destinationField,
    MappingConfidence? confidence,
    bool? isManualOverride,
  }) {
    return ColumnMapping(
      sourceColumn: sourceColumn,
      sourceColumnIndex: sourceColumnIndex,
      destinationField: destinationField ?? this.destinationField,
      confidence: confidence ?? this.confidence,
      isManualOverride: isManualOverride ?? this.isManualOverride,
      sampleValues: sampleValues,
    );
  }
}

/// Represents an individual parsed row from the source spreadsheet.
class ImportRow {
  final int sourceRowNumber;
  final Map<String, dynamic> rawValues;
  final Map<ProductImportField, dynamic> mappedValues;
  RowValidationStatus validationStatus;
  final List<ImportRowError> errors;
  final List<ImportRowWarning> warnings;
  RowDuplicateStatus duplicateStatus;
  String? duplicateReason;
  String? existingVariantId;
  String? existingProductId;
  bool isSelectedForImport;

  ImportRow({
    required this.sourceRowNumber,
    required this.rawValues,
    Map<ProductImportField, dynamic>? mappedValues,
    this.validationStatus = RowValidationStatus.pending,
    List<ImportRowError>? errors,
    List<ImportRowWarning>? warnings,
    this.duplicateStatus = RowDuplicateStatus.none,
    this.duplicateReason,
    this.existingVariantId,
    this.existingProductId,
    this.isSelectedForImport = true,
  })  : mappedValues = mappedValues ?? <ProductImportField, dynamic>{},
        errors = errors ?? <ImportRowError>[],
        warnings = warnings ?? <ImportRowWarning>[];

  bool get isValid => validationStatus == RowValidationStatus.valid;
  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isDuplicate => duplicateStatus != RowDuplicateStatus.none;

  String get productName =>
      mappedValues[ProductImportField.productName]?.toString().trim() ?? '';
  String get sku =>
      mappedValues[ProductImportField.sku]?.toString().trim() ?? '';
  String? get barcode {
    final val = mappedValues[ProductImportField.barcode]?.toString().trim();
    return (val != null && val.isNotEmpty) ? val : null;
  }

  void addError(ImportRowError error) {
    errors.add(error);
    validationStatus = RowValidationStatus.invalid;
  }

  void addWarning(ImportRowWarning warning) {
    warnings.add(warning);
  }
}

/// Metadata and parsed structure of an uploaded spreadsheet file.
class ImportFile {
  final String fileName;
  final ImportFileType fileType;
  final int sizeBytes;
  final Uint8List bytes;
  final List<String> worksheetNames;
  final String? selectedWorksheet;
  final List<String> headers;
  final List<ImportRow> rows;
  final String? parseError;

  const ImportFile({
    required this.fileName,
    required this.fileType,
    required this.sizeBytes,
    required this.bytes,
    this.worksheetNames = const [],
    this.selectedWorksheet,
    this.headers = const [],
    this.rows = const [],
    this.parseError,
  });

  ImportFile copyWith({
    String? selectedWorksheet,
    List<String>? headers,
    List<ImportRow>? rows,
    String? parseError,
  }) {
    return ImportFile(
      fileName: fileName,
      fileType: fileType,
      sizeBytes: sizeBytes,
      bytes: bytes,
      worksheetNames: worksheetNames,
      selectedWorksheet: selectedWorksheet ?? this.selectedWorksheet,
      headers: headers ?? this.headers,
      rows: rows ?? this.rows,
      parseError: parseError ?? this.parseError,
    );
  }

  bool get hasError => parseError != null;
  int get totalRows => rows.length;
}

/// Import run configuration options.
class ImportConfiguration {
  final String tenantId;
  final String? locationId;
  final String? deviceId;
  final DuplicateHandlingMode duplicateMode;
  final int headerRowIndex;
  final int firstDataRowIndex;
  final bool allowOpeningStock;
  final String defaultUnitCode;
  final String defaultItemType;
  final bool canManageCostPrice;

  const ImportConfiguration({
    required this.tenantId,
    this.locationId,
    this.deviceId,
    this.duplicateMode = DuplicateHandlingMode.skipDuplicates,
    this.headerRowIndex = 0,
    this.firstDataRowIndex = 1,
    this.allowOpeningStock = false,
    this.defaultUnitCode = 'PCS',
    this.defaultItemType = 'stock',
    this.canManageCostPrice = true,
  });
}

/// Summary of a failed row during actual backend execution.
class ImportFailureItem {
  final int sourceRowNumber;
  final String productName;
  final String sku;
  final String error;

  const ImportFailureItem({
    required this.sourceRowNumber,
    required this.productName,
    required this.sku,
    required this.error,
  });

  Map<String, dynamic> toMap() => {
        'row': sourceRowNumber,
        'product_name': productName,
        'sku': sku,
        'error': error,
      };
}

/// Complete summary result of an executed import process.
class ImportExecutionSummary {
  final int totalSourceRows;
  final int validRows;
  final int invalidRows;
  final int duplicateRows;
  final int createdCount;
  final int updatedCount;
  final int skippedCount;
  final int failedCount;
  final List<ImportFailureItem> failures;
  final Duration duration;
  final bool isCompleted;

  const ImportExecutionSummary({
    required this.totalSourceRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicateRows,
    required this.createdCount,
    required this.updatedCount,
    required this.skippedCount,
    required this.failedCount,
    this.failures = const [],
    required this.duration,
    required this.isCompleted,
  });

  bool get hasFailures => failedCount > 0;
  bool get isFullSuccess => isCompleted && failedCount == 0 && createdCount > 0;
}
