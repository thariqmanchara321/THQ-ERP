class InventoryUnit {
  final String id;
  final String code;
  final String name;
  final String group;
  final int decimalPlaces;
  final bool allowFractional;
  final bool systemUnit;
  final bool active;

  const InventoryUnit({
    required this.id,
    required this.code,
    required this.name,
    required this.group,
    required this.decimalPlaces,
    required this.allowFractional,
    required this.systemUnit,
    required this.active,
  });

  factory InventoryUnit.fromMap(Map<String, dynamic> map) => InventoryUnit(
        id: map['unit_id']?.toString() ?? map['id']?.toString() ?? '',
        code: map['code']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        group: map['unit_group']?.toString() ?? 'count',
        decimalPlaces: (map['decimal_places'] as num?)?.toInt() ?? 0,
        allowFractional: map['allow_fractional'] == true,
        systemUnit: map['system_unit'] == true,
        active: map['active'] != false,
      );
}

class ProductUnitOption {
  final String unitId;
  final String code;
  final String name;
  final int decimalPlaces;
  final bool allowFractional;
  final bool isBase;
  final bool allowPurchase;
  final bool allowSale;
  final bool isDefaultPurchase;
  final bool isDefaultSale;
  final double conversionToBase;
  final double quantityStep;
  final double? salePrice;
  final double? purchaseCost;
  final bool cuttingAllowed;
  final double cuttingCharge;
  final bool active;

  const ProductUnitOption({
    required this.unitId,
    required this.code,
    required this.name,
    required this.decimalPlaces,
    required this.allowFractional,
    required this.isBase,
    required this.allowPurchase,
    required this.allowSale,
    required this.isDefaultPurchase,
    required this.isDefaultSale,
    required this.conversionToBase,
    required this.quantityStep,
    required this.salePrice,
    required this.purchaseCost,
    required this.cuttingAllowed,
    required this.cuttingCharge,
    required this.active,
  });

  factory ProductUnitOption.fromMap(Map<String, dynamic> map) {
    double number(dynamic value, [double fallback = 0]) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return ProductUnitOption(
      unitId: map['unit_id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? map['code']?.toString() ?? '',
      decimalPlaces: (map['decimal_places'] as num?)?.toInt() ?? 0,
      allowFractional: map['allow_fractional'] == true,
      isBase: map['is_base'] == true,
      allowPurchase: map['allow_purchase'] == true,
      allowSale: map['allow_sale'] != false,
      isDefaultPurchase: map['is_default_purchase'] == true,
      isDefaultSale: map['is_default_sale'] == true,
      conversionToBase: number(map['conversion_to_base'], 1),
      quantityStep: number(map['quantity_step'], 1),
      salePrice: map['sale_price'] == null ? null : number(map['sale_price']),
      purchaseCost: map['purchase_cost'] == null ? null : number(map['purchase_cost']),
      cuttingAllowed: map['cutting_allowed'] == true,
      cuttingCharge: number(map['cutting_charge']),
      active: map['active'] != false,
    );
  }

  double salePriceFor(double basePrice) => salePrice ?? basePrice * conversionToBase;
  double purchaseCostFor(double baseCost) => purchaseCost ?? baseCost * conversionToBase;
  double toBase(double quantity) => quantity * conversionToBase;

  bool acceptsQuantity(double quantity) {
    if (quantity <= 0) return false;
    if (!allowFractional && (quantity - quantity.roundToDouble()).abs() > 0.000001) {
      return false;
    }
    final step = quantityStep > 0 ? quantityStep : 1.0;
    final steps = quantity / step;
    return (steps - steps.roundToDouble()).abs() <= 0.000001;
  }

  String formatQuantity(double value) => value.toStringAsFixed(
        allowFractional ? decimalPlaces.clamp(0, 6).toInt() : 0,
      );
}
