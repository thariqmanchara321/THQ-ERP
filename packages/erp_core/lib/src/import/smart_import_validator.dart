import 'smart_import_models.dart';

/// Pre-import validation engine verifying product and variant integrity
/// before any database persistence.
class SmartImportValidator {
  const SmartImportValidator();

  /// Maps and validates a raw spreadsheet row against active column mappings.
  ImportRow validateRow({
    required int sourceRowNumber,
    required List<String> rawRow,
    required List<ColumnMapping> mappings,
    required ImportConfiguration config,
  }) {
    final rawValuesMap = <String, dynamic>{};
    final mappedValues = <ProductImportField, dynamic>{};
    final errors = <ImportRowError>[];
    final warnings = <ImportRowWarning>[];

    // 1. Populate raw map and mapped values from column mapping
    for (final mapping in mappings) {
      final colIdx = mapping.sourceColumnIndex;
      final val = (colIdx < rawRow.length) ? rawRow[colIdx].trim() : '';

      rawValuesMap[mapping.sourceColumn] = val;

      if (mapping.isMapped && val.isNotEmpty) {
        mappedValues[mapping.destinationField] = val;
      }
    }

    // 2. Validate Product Name (Mandatory)
    final name = mappedValues[ProductImportField.productName]?.toString().trim() ?? '';
    if (name.isEmpty) {
      errors.add(
        ImportRowError(
          field: ProductImportField.productName,
          columnName: _findColName(mappings, ProductImportField.productName),
          message: 'Product name is required.',
          suggestion: 'Provide a non-empty name for this item.',
        ),
      );
    } else {
      mappedValues[ProductImportField.productName] = name;
    }

    // 3. Validate SKU (Mandatory)
    final rawSku = mappedValues[ProductImportField.sku]?.toString().trim() ?? '';
    if (rawSku.isEmpty) {
      errors.add(
        ImportRowError(
          field: ProductImportField.sku,
          columnName: _findColName(mappings, ProductImportField.sku),
          message: 'SKU is required.',
          suggestion: 'Provide a unique SKU or part code.',
        ),
      );
    } else {
      // Preserve leading zeros and strip illegal characters
      mappedValues[ProductImportField.sku] = rawSku;
    }

    // 4. Validate Barcode (Optional)
    if (mappedValues.containsKey(ProductImportField.barcode)) {
      final bc = mappedValues[ProductImportField.barcode].toString().trim();
      if (bc.isNotEmpty) {
        mappedValues[ProductImportField.barcode] = bc;
      } else {
        mappedValues.remove(ProductImportField.barcode);
      }
    }

    // 5. Validate Selling Price
    final rawSelling = mappedValues[ProductImportField.sellingPrice]?.toString().trim() ?? '';
    if (rawSelling.isNotEmpty) {
      final price = double.tryParse(rawSelling);
      if (price == null) {
        errors.add(
          ImportRowError(
            field: ProductImportField.sellingPrice,
            columnName: _findColName(mappings, ProductImportField.sellingPrice),
            providedValue: rawSelling,
            message: 'Selling price must be a valid number.',
            suggestion: 'Enter a numeric rate such as 150.00.',
          ),
        );
      } else if (price < 0) {
        errors.add(
          ImportRowError(
            field: ProductImportField.sellingPrice,
            columnName: _findColName(mappings, ProductImportField.sellingPrice),
            providedValue: rawSelling,
            message: 'Selling price cannot be negative.',
          ),
        );
      } else {
        mappedValues[ProductImportField.sellingPrice] = price;
      }
    } else {
      mappedValues[ProductImportField.sellingPrice] = 0.0;
    }

    // 6. Validate Cost Price (Subject to permissions)
    if (config.canManageCostPrice) {
      final rawCost = mappedValues[ProductImportField.costPrice]?.toString().trim() ?? '';
      if (rawCost.isNotEmpty) {
        final cost = double.tryParse(rawCost);
        if (cost == null) {
          errors.add(
            ImportRowError(
              field: ProductImportField.costPrice,
              columnName: _findColName(mappings, ProductImportField.costPrice),
              providedValue: rawCost,
              message: 'Cost price must be a valid number.',
            ),
          );
        } else if (cost < 0) {
          errors.add(
            ImportRowError(
              field: ProductImportField.costPrice,
              columnName: _findColName(mappings, ProductImportField.costPrice),
              providedValue: rawCost,
              message: 'Cost price cannot be negative.',
            ),
          );
        } else {
          mappedValues[ProductImportField.costPrice] = cost;
        }
      } else {
        mappedValues[ProductImportField.costPrice] = 0.0;
      }
    } else {
      // Zero out if user has no financial management permission
      mappedValues[ProductImportField.costPrice] = 0.0;
    }

    // 7. Validate List Price / MRP
    final rawList = mappedValues[ProductImportField.listPrice]?.toString().trim() ?? '';
    if (rawList.isNotEmpty) {
      final listP = double.tryParse(rawList);
      if (listP == null || listP < 0) {
        errors.add(
          ImportRowError(
            field: ProductImportField.listPrice,
            columnName: _findColName(mappings, ProductImportField.listPrice),
            providedValue: rawList,
            message: 'List price (MRP) must be a non-negative number.',
          ),
        );
      } else {
        mappedValues[ProductImportField.listPrice] = listP;
      }
    }

    // 8. Validate Tax Rate (0 to 100)
    final rawTax = mappedValues[ProductImportField.taxRate]?.toString().trim() ?? '';
    if (rawTax.isNotEmpty) {
      // Strip % sign if present
      final cleanTax = rawTax.replaceAll('%', '').trim();
      final tax = double.tryParse(cleanTax);
      if (tax == null) {
        errors.add(
          ImportRowError(
            field: ProductImportField.taxRate,
            columnName: _findColName(mappings, ProductImportField.taxRate),
            providedValue: rawTax,
            message: 'Tax rate must be numeric.',
          ),
        );
      } else if (tax < 0 || tax > 100) {
        errors.add(
          ImportRowError(
            field: ProductImportField.taxRate,
            columnName: _findColName(mappings, ProductImportField.taxRate),
            providedValue: rawTax,
            message: 'Tax rate must be between 0% and 100%.',
          ),
        );
      } else {
        mappedValues[ProductImportField.taxRate] = tax;
      }
    } else {
      mappedValues[ProductImportField.taxRate] = 0.0;
    }

    // 9. Validate Reorder Level
    final rawReorder = mappedValues[ProductImportField.reorderLevel]?.toString().trim() ?? '';
    if (rawReorder.isNotEmpty) {
      final reorder = double.tryParse(rawReorder);
      if (reorder == null || reorder < 0) {
        errors.add(
          ImportRowError(
            field: ProductImportField.reorderLevel,
            columnName: _findColName(mappings, ProductImportField.reorderLevel),
            providedValue: rawReorder,
            message: 'Reorder level must be a non-negative number.',
          ),
        );
      } else {
        mappedValues[ProductImportField.reorderLevel] = reorder;
      }
    } else {
      mappedValues[ProductImportField.reorderLevel] = 0.0;
    }

    // 10. Validate Item Type
    final rawType = mappedValues[ProductImportField.itemType]?.toString().trim().toLowerCase() ?? '';
    if (rawType.isNotEmpty) {
      if (rawType == 'stock' || rawType == 'non_stock' || rawType == 'service') {
        mappedValues[ProductImportField.itemType] = rawType;
      } else {
        warnings.add(
          ImportRowWarning(
            field: ProductImportField.itemType,
            columnName: _findColName(mappings, ProductImportField.itemType),
            message: 'Unknown item type "$rawType". Defaulting to "${config.defaultItemType}".',
          ),
        );
        mappedValues[ProductImportField.itemType] = config.defaultItemType;
      }
    } else {
      mappedValues[ProductImportField.itemType] = config.defaultItemType;
    }

    // 11. Validate Base Unit
    final rawUnit = mappedValues[ProductImportField.unit]?.toString().trim().toUpperCase() ?? '';
    if (rawUnit.isNotEmpty) {
      mappedValues[ProductImportField.unit] = rawUnit;
    } else {
      mappedValues[ProductImportField.unit] = config.defaultUnitCode;
    }

    // 12. Validate Opening Stock (Strict Operational Guard)
    final rawOpening = mappedValues[ProductImportField.openingStock]?.toString().trim() ?? '';
    if (rawOpening.isNotEmpty) {
      final opening = double.tryParse(rawOpening);
      if (opening == null || opening < 0) {
        errors.add(
          ImportRowError(
            field: ProductImportField.openingStock,
            columnName: _findColName(mappings, ProductImportField.openingStock),
            providedValue: rawOpening,
            message: 'Opening stock must be a non-negative number.',
          ),
        );
      } else if (!config.allowOpeningStock && opening > 0) {
        warnings.add(
          ImportRowWarning(
            field: ProductImportField.openingStock,
            columnName: _findColName(mappings, ProductImportField.openingStock),
            message: 'Catalogue import sets product definitions only. Opening stock ($opening) will not adjust live inventory balances.',
          ),
        );
        mappedValues[ProductImportField.openingStock] = 0.0;
      } else {
        mappedValues[ProductImportField.openingStock] = opening;
      }
    } else {
      mappedValues[ProductImportField.openingStock] = 0.0;
    }

    return ImportRow(
      sourceRowNumber: sourceRowNumber,
      rawValues: rawValuesMap,
      mappedValues: mappedValues,
      validationStatus: errors.isEmpty ? RowValidationStatus.valid : RowValidationStatus.invalid,
      errors: errors,
      warnings: warnings,
    );
  }

  static String _findColName(List<ColumnMapping> mappings, ProductImportField field) {
    for (final m in mappings) {
      if (m.destinationField == field) return m.sourceColumn;
    }
    return field.label;
  }
}
