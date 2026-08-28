class InventoryProductDetail {
  final String productId;
  final String variantId;

  final String productName;
  final String? description;
  final String itemType;

  final String? categoryName;
  final String? brandName;

  final String? unitName;
  final String? unitCode;

  final String sku;
  final String? barcode;
  final String? partNumber;

  final double costPrice;
  final double sellingPrice;
  final double? listPrice;

  final double taxRate;
  final double reorderLevel;

  final double stockQuantity;

  final String productStatus;
  final String variantStatus;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const InventoryProductDetail({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.description,
    required this.itemType,
    required this.categoryName,
    required this.brandName,
    required this.unitName,
    required this.unitCode,
    required this.sku,
    required this.barcode,
    required this.partNumber,
    required this.costPrice,
    required this.sellingPrice,
    required this.listPrice,
    required this.taxRate,
    required this.reorderLevel,
    required this.stockQuantity,
    required this.productStatus,
    required this.variantStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventoryProductDetail.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    double? nullableNumber(dynamic value) {
      if (value == null) {
        return null;
      }

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value.toString());
    }

    return InventoryProductDetail(
      productId: map['product_id']?.toString() ?? '',
      variantId: map['variant_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      description: map['description']?.toString(),
      itemType: map['item_type']?.toString() ?? 'stock',
      categoryName: map['category_name']?.toString(),
      brandName: map['brand_name']?.toString(),
      unitName: map['unit_name']?.toString(),
      unitCode: map['unit_code']?.toString(),
      sku: map['sku']?.toString() ?? '',
      barcode: map['barcode']?.toString(),
      partNumber: map['part_number']?.toString(),
      costPrice: number(map['cost_price']),
      sellingPrice: number(map['selling_price']),
      listPrice: nullableNumber(map['list_price']),
      taxRate: number(map['tax_rate']),
      reorderLevel: number(map['reorder_level']),
      stockQuantity: number(map['stock_quantity']),
      productStatus: map['product_status']?.toString() ?? '',
      variantStatus: map['variant_status']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }
}
