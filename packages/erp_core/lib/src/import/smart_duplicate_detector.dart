import '../identification/identification_models.dart';
import '../identification/product_identification_repository.dart';
import 'smart_import_models.dart';

/// Duplicate detection engine for product imports.
///
/// Detects duplicate SKUs and barcodes within the spreadsheet (intra-file)
/// and against the existing live THQ product catalogue.
class SmartDuplicateDetector {
  final ProductIdentificationRepository? catalogRepository;

  const SmartDuplicateDetector({this.catalogRepository});

  /// Evaluates rows for duplicates within the spreadsheet and against the catalog.
  Future<void> detectDuplicates({
    required List<ImportRow> rows,
    required ImportConfiguration config,
  }) async {
    final seenSkus = <String, int>{}; // lowercase SKU -> sourceRowNumber
    final seenBarcodes = <String, int>{}; // lowercase Barcode -> sourceRowNumber

    // 1. Intra-file duplicate detection pass
    for (final row in rows) {
      if (row.hasErrors) continue;

      final sku = row.sku.toLowerCase();
      final barcode = row.barcode?.toLowerCase();

      if (sku.isNotEmpty) {
        if (seenSkus.containsKey(sku)) {
          row.duplicateStatus = RowDuplicateStatus.inSpreadsheet;
          row.duplicateReason =
              'Duplicate SKU "${row.sku}" already appears in file on row ${seenSkus[sku]}.';
          _applyDuplicatePolicy(row, config.duplicateMode);
          continue;
        } else {
          seenSkus[sku] = row.sourceRowNumber;
        }
      }

      if (barcode != null && barcode.isNotEmpty) {
        if (seenBarcodes.containsKey(barcode)) {
          row.duplicateStatus = RowDuplicateStatus.inSpreadsheet;
          row.duplicateReason =
              'Duplicate barcode "${row.barcode}" already appears in file on row ${seenBarcodes[barcode]}.';
          _applyDuplicatePolicy(row, config.duplicateMode);
          continue;
        } else {
          seenBarcodes[barcode] = row.sourceRowNumber;
        }
      }
    }

    // 2. Catalog duplicate detection pass (if catalog repository provided)
    if (catalogRepository != null) {
      for (final row in rows) {
        if (row.hasErrors || row.duplicateStatus != RowDuplicateStatus.none) {
          continue;
        }

        ProductIdentificationMatch? match;

        // Check SKU against catalog
        if (row.sku.isNotEmpty) {
          final skuMatches = await catalogRepository!.lookupIdentifier(
            tenantId: config.tenantId,
            code: row.sku,
            locationId: config.locationId,
          );
          if (skuMatches.isNotEmpty) {
            match = skuMatches.first;
          }
        }

        // Check barcode against catalog if not matched by SKU
        if (match == null && row.barcode != null && row.barcode!.isNotEmpty) {
          final bcMatches = await catalogRepository!.lookupIdentifier(
            tenantId: config.tenantId,
            code: row.barcode!,
            locationId: config.locationId,
          );
          if (bcMatches.isNotEmpty) {
            match = bcMatches.first;
          }
        }

        if (match != null) {
          row.duplicateStatus = RowDuplicateStatus.inCatalog;
          row.existingProductId = match.productId;
          row.existingVariantId = match.variantId;
          row.duplicateReason =
              'Matches existing catalogue product "${match.productName}" (SKU: ${match.sku}).';
          _applyDuplicatePolicy(row, config.duplicateMode);
        }
      }
    }
  }

  void _applyDuplicatePolicy(ImportRow row, DuplicateHandlingMode mode) {
    switch (mode) {
      case DuplicateHandlingMode.skipDuplicates:
      case DuplicateHandlingMode.importNewOnly:
        row.isSelectedForImport = false;
        break;
      case DuplicateHandlingMode.updateExisting:
        // Intra-file duplicates cannot be safely updated because they conflict within the file
        if (row.duplicateStatus == RowDuplicateStatus.inSpreadsheet) {
          row.isSelectedForImport = false;
        } else {
          // Catalog duplicate can be updated if variant ID is known
          row.isSelectedForImport = row.existingVariantId != null;
        }
        break;
    }
  }
}
