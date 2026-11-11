import 'smart_import_models.dart';

/// Intelligent column recognition and auto-mapping engine for product spreadsheets.
class SmartColumnMapper {
  const SmartColumnMapper();

  static const Map<ProductImportField, List<String>> _synonyms = {
    ProductImportField.productName: [
      'product name',
      'productname',
      'product',
      'item name',
      'itemname',
      'item',
      'name',
      'title',
      'material name',
      'material',
      'goods name',
    ],
    ProductImportField.sku: [
      'sku',
      'item code',
      'itemcode',
      'product code',
      'productcode',
      'code',
      'part code',
      'partcode',
      'material code',
      'article no',
      'article number',
      'item id',
      'product id',
    ],
    ProductImportField.barcode: [
      'barcode',
      'bar code',
      'barcode / ean',
      'barcode/ean',
      'barcode ean',
      'upc',
      'upca',
      'upce',
      'ean',
      'ean13',
      'ean8',
      'gtin',
      'qr',
      'qr code',
      'qrcode',
      'scan code',
    ],
    ProductImportField.description: [
      'description',
      'desc',
      'details',
      'specification',
      'specifications',
      'specs',
      'long description',
      'product details',
      'notes',
      'remarks',
    ],
    ProductImportField.category: [
      'category',
      'category name',
      'cat',
      'group',
      'item group',
      'product group',
      'department',
      'family',
      'classification',
    ],
    ProductImportField.brand: [
      'brand',
      'brand name',
      'make',
      'manufacturer',
      'mfg',
      'company',
      'vendor brand',
    ],
    ProductImportField.unit: [
      'unit',
      'uom',
      'base unit',
      'unit of measure',
      'unit code',
      'measurement',
      'measure',
      'pkg',
    ],
    ProductImportField.itemType: [
      'item type',
      'itemtype',
      'type',
      'product type',
      'goods type',
    ],
    ProductImportField.sellingPrice: [
      'selling price',
      'sellingprice',
      'sale price',
      'saleprice',
      'sales price',
      'price',
      'rate',
      'sale rate',
      'unit price',
      'sp',
      'retail price',
      'customer price',
    ],
    ProductImportField.costPrice: [
      'cost price',
      'costprice',
      'purchase price',
      'purchaseprice',
      'purchase rate',
      'cost',
      'buying price',
      'buy price',
      'buy rate',
      'cp',
      'standard cost',
    ],
    ProductImportField.listPrice: [
      'list price',
      'listprice',
      'mrp',
      'max retail price',
      'maximum retail price',
      'original price',
      'catalog price',
    ],
    ProductImportField.taxRate: [
      'tax rate',
      'taxrate',
      'tax',
      'gst',
      'gst rate',
      'tax %',
      'gst %',
      'tax percentage',
      'vat',
      'vat rate',
      'vat %',
      'hsn tax',
    ],
    ProductImportField.reorderLevel: [
      'reorder level',
      'reorderlevel',
      'reorder point',
      'reorder qty',
      'min stock',
      'minimum stock',
      'min level',
      'safety stock',
    ],
    ProductImportField.partNumber: [
      'part number',
      'partnumber',
      'part no',
      'partno',
      'mpn',
      'oem',
      'oem no',
      'oem number',
      'model no',
      'model number',
    ],
    ProductImportField.openingStock: [
      'opening stock',
      'openingstock',
      'initial stock',
      'opening qty',
      'stock',
      'quantity',
      'qty',
      'available qty',
      'balance',
    ],
    ProductImportField.variantName: [
      'variant',
      'variant name',
      'variantname',
      'size',
      'color',
      'grade',
      'flavor',
    ],
  };

  /// Analyzes source headers and returns auto-assigned mappings with confidence scores.
  List<ColumnMapping> autoMapHeaders(
    List<String> headers, {
    List<List<String>> sampleRows = const [],
  }) {
    final mappings = <ColumnMapping>[];
    final mappedFields = <ProductImportField>{};

    for (var colIdx = 0; colIdx < headers.length; colIdx++) {
      final header = headers[colIdx];
      final samples = <String>[];

      for (final row in sampleRows) {
        if (colIdx < row.length && row[colIdx].isNotEmpty) {
          samples.add(row[colIdx]);
          if (samples.length >= 3) break;
        }
      }

      final normalized = _normalizeHeader(header);
      var matchField = ProductImportField.ignore;
      var confidence = MappingConfidence.unmapped;

      // 1. Exact or High-Confidence Synonym Match
      for (final entry in _synonyms.entries) {
        final field = entry.key;
        final synonyms = entry.value;

        if (mappedFields.contains(field)) continue;

        if (synonyms.contains(normalized)) {
          matchField = field;
          confidence = MappingConfidence.high;
          break;
        }
      }

      // 2. Partial / Substring Match (Medium Confidence)
      if (matchField == ProductImportField.ignore) {
        for (final entry in _synonyms.entries) {
          final field = entry.key;
          final synonyms = entry.value;

          if (mappedFields.contains(field)) continue;

          for (final syn in synonyms) {
            if (normalized.contains(syn) || syn.contains(normalized)) {
              matchField = field;
              confidence = MappingConfidence.medium;
              break;
            }
          }
          if (matchField != ProductImportField.ignore) break;
        }
      }

      if (matchField != ProductImportField.ignore) {
        mappedFields.add(matchField);
      }

      mappings.add(
        ColumnMapping(
          sourceColumn: header,
          sourceColumnIndex: colIdx,
          destinationField: matchField,
          confidence: confidence,
          sampleValues: samples,
        ),
      );
    }

    return mappings;
  }

  /// Verifies that all required fields are assigned in the active mappings.
  List<ProductImportField> findMissingRequiredFields(
    List<ColumnMapping> mappings,
  ) {
    final assigned = mappings.map((m) => m.destinationField).toSet();
    final missing = <ProductImportField>[];

    for (final field in ProductImportField.values) {
      if (field.isRequired && !assigned.contains(field)) {
        missing.add(field);
      }
    }

    return missing;
  }

  /// Normalizes header strings by lowercasing, stripping punctuation and compressing spaces.
  static String _normalizeHeader(String raw) {
    var s = raw.toLowerCase().trim();
    // Replace punctuation with spaces
    s = s.replaceAll(RegExp(r'[\_\-\.\,\/\\]'), ' ');
    // Compress multiple spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }
}
