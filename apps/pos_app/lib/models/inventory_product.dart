import 'package:erp_core/erp_core.dart';

class InventoryProduct {
  final String productId;
  final String variantId;
  final String productName;
  final String variantName;
  final String itemType;
  final String? categoryName;
  final String? brandName;
  final String? unitName;
  final String? unitCode;
  final String baseUnitCode;
  final String baseUnitName;
  final bool allowFractional;
  final double quantityStep;
  final List<ProductUnitOption> saleUnits;
  final List<ProductUnitOption> purchaseUnits;
  final String sku;
  final String? barcode;
  final String? partNumber;
  final List<ProductIdentifier> identifiers;
  final String searchCodes;
  final double costPrice;
  final double sellingPrice;
  final double? listPrice;
  final double taxRate;
  final double reorderLevel;
  final double stockQuantity;
  final String trackingMode;
  final double? trackedStockQuantity;
  final String productStatus;
  final String variantStatus;
  final DateTime? updatedAt;

  const InventoryProduct({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.itemType,
    required this.categoryName,
    required this.brandName,
    required this.unitName,
    required this.unitCode,
    required this.baseUnitCode,
    required this.baseUnitName,
    required this.allowFractional,
    required this.quantityStep,
    required this.saleUnits,
    required this.purchaseUnits,
    required this.sku,
    required this.barcode,
    required this.partNumber,
    required this.identifiers,
    required this.searchCodes,
    required this.costPrice,
    required this.sellingPrice,
    required this.listPrice,
    required this.taxRate,
    required this.reorderLevel,
    required this.stockQuantity,
    required this.trackingMode,
    required this.trackedStockQuantity,
    required this.productStatus,
    required this.variantStatus,
    required this.updatedAt,
  });

  ProductUnitOption? get defaultSaleUnit {
    for (final unit in saleUnits) {
      if (unit.isDefaultSale) return unit;
    }
    return saleUnits.isEmpty ? null : saleUnits.first;
  }

  ProductUnitOption? get defaultPurchaseUnit {
    for (final unit in purchaseUnits) {
      if (unit.isDefaultPurchase) return unit;
    }
    return purchaseUnits.isEmpty ? null : purchaseUnits.first;
  }

  factory InventoryProduct.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    double? nullableNumber(dynamic value) {
      if (value == null) return null;

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value.toString());
    }

    final saleUnits = (map['sale_units'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ProductUnitOption.fromMap(Map<String, dynamic>.from(row)))
        .toList();
    final purchaseUnits = (map['purchase_units'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ProductUnitOption.fromMap(Map<String, dynamic>.from(row)))
        .toList();
    final base = map['base_unit'] is Map
        ? Map<String, dynamic>.from(map['base_unit'] as Map)
        : <String, dynamic>{};
    final identifiers = (map['identifiers'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => ProductIdentifier.fromMap(Map<String, dynamic>.from(row)))
        .toList();

    return InventoryProduct(
      productId: map['product_id']?.toString() ?? '',
      variantId: map['variant_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      variantName: map['variant_name']?.toString() ?? '',
      itemType: map['item_type']?.toString() ?? 'stock',
      categoryName: map['category_name']?.toString(),
      brandName: map['brand_name']?.toString(),
      unitName: map['unit_name']?.toString(),
      unitCode: map['unit_code']?.toString(),
      baseUnitCode: map['base_unit_code']?.toString() ?? base['code']?.toString() ?? map['unit_code']?.toString() ?? 'PCS',
      baseUnitName: base['name']?.toString() ?? map['unit_name']?.toString() ?? map['unit_code']?.toString() ?? 'Piece',
      allowFractional: base['allow_fractional'] == true,
      quantityStep: number(base['quantity_step']) > 0 ? number(base['quantity_step']) : 1,
      saleUnits: saleUnits,
      purchaseUnits: purchaseUnits,
      sku: map['sku']?.toString() ?? '',
      barcode: map['barcode']?.toString(),
      partNumber: map['part_number']?.toString(),
      identifiers: identifiers,
      searchCodes: map['search_codes']?.toString() ?? '',
      costPrice: number(map['cost_price']),
      sellingPrice: number(map['selling_price']),
      listPrice: nullableNumber(map['list_price']),
      taxRate: number(map['tax_rate']),
      reorderLevel: number(map['reorder_level']),
      stockQuantity: number(map['stock_quantity']),
      trackingMode: map['tracking_mode']?.toString() ?? 'none',
      trackedStockQuantity: map['tracked_stock_quantity'] == null ? null : number(map['tracked_stock_quantity']),
      productStatus: map['product_status']?.toString() ?? '',
      variantStatus: map['variant_status']?.toString() ?? '',
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }
}
