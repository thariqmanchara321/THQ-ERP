double numberValue(dynamic value, [double fallback = 0]) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? fallback;

class MobileSaleUnit {
  final String unitId;
  final String code;
  final String name;
  final double conversionToBase;
  final double salePrice;
  final double quantityStep;
  final bool isDefault;

  const MobileSaleUnit({required this.unitId,required this.code,required this.name,required this.conversionToBase,required this.salePrice,required this.quantityStep,required this.isDefault});
  factory MobileSaleUnit.fromMap(Map<String,dynamic> m) => MobileSaleUnit(
    unitId: (m['unit_id'] ?? m['id'])?.toString() ?? '',code: m['code']?.toString() ?? m['unit_code']?.toString() ?? '',
    name: m['name']?.toString() ?? m['unit_name']?.toString() ?? '',conversionToBase: numberValue(m['conversion_to_base'],1),
    salePrice: numberValue(m['sale_price'] ?? m['selling_price']),quantityStep:numberValue(m['quantity_step'],1)>0?numberValue(m['quantity_step'],1):1,isDefault: m['is_default_sale']==true || m['is_default']==true,
  );
}

class MobileProduct {
  final String productId;
  final String variantId;
  final String name;
  final String variantName;
  final String sku;
  final String barcode;
  final String searchCodes;
  final String itemType;
  final String baseUnitCode;
  final double sellingPrice;
  final double taxRate;
  final double stockQuantity;
  final String trackingMode;
  final List<MobileSaleUnit> saleUnits;

  const MobileProduct({required this.productId,required this.variantId,required this.name,required this.variantName,required this.sku,required this.barcode,required this.searchCodes,required this.itemType,required this.baseUnitCode,required this.sellingPrice,required this.taxRate,required this.stockQuantity,required this.trackingMode,required this.saleUnits});
  factory MobileProduct.fromMap(Map<String,dynamic> m) => MobileProduct(
    productId:m['product_id']?.toString()??'',variantId:m['variant_id']?.toString()??'',name:m['product_name']?.toString()??'',variantName:m['variant_name']?.toString()??'',
    sku:m['sku']?.toString()??'',barcode:m['barcode']?.toString()??'',searchCodes:m['search_codes']?.toString()??'',itemType:m['item_type']?.toString()??'stock',
    baseUnitCode:m['base_unit_code']?.toString()??m['unit_code']?.toString()??'PCS',sellingPrice:numberValue(m['selling_price']),taxRate:numberValue(m['tax_rate']),
    stockQuantity:numberValue(m['offline_available_quantity']??m['stock_quantity']),trackingMode:m['tracking_mode']?.toString()??'none',
    saleUnits:(m['sale_units'] as List? ?? const []).whereType<Map>().map((x)=>MobileSaleUnit.fromMap(Map<String,dynamic>.from(x))).toList(),
  );
  MobileSaleUnit get defaultUnit {
    for(final unit in saleUnits){if(unit.isDefault)return unit;}
    if(saleUnits.isNotEmpty)return saleUnits.first;
    return MobileSaleUnit(unitId:'',code:baseUnitCode,name:baseUnitCode,conversionToBase:1,salePrice:sellingPrice,quantityStep:1,isDefault:true);
  }
  bool matchesCode(String raw){
    final q=raw.trim().toLowerCase();
    return q.isNotEmpty && (sku.toLowerCase()==q || barcode.toLowerCase()==q || searchCodes.toLowerCase().split(RegExp(r'[,;|\s]+')).contains(q));
  }
}

class MobileCustomer {
  final String id;
  final String name;
  final String phone;
  final bool isWalkIn;
  const MobileCustomer({required this.id,required this.name,required this.phone,required this.isWalkIn});
  factory MobileCustomer.fromMap(Map<String,dynamic> m)=>MobileCustomer(id:(m['customer_id']??m['id'])?.toString()??'',name:(m['customer_name']??m['name'])?.toString()??'',phone:m['phone']?.toString()??'',isWalkIn:m['is_walk_in']==true);
}

class CartLine {
  final MobileProduct product;
  MobileSaleUnit unit;
  double quantity;
  double? resolvedUnitPrice;
  String pricingSource;
  final List<String> serialNumbers;
  CartLine({required this.product,required this.unit,required this.quantity,this.resolvedUnitPrice,this.pricingSource='cached',List<String>? serialNumbers}):serialNumbers=serialNumbers??<String>[];
  double get unitPrice => resolvedUnitPrice ?? (unit.salePrice > 0 ? unit.salePrice : product.sellingPrice);
  double get taxable => quantity*unitPrice;
  double get tax => taxable*product.taxRate/100;
  double get total => taxable+tax;
  double get baseQuantity => quantity*unit.conversionToBase;
  Map<String,dynamic> toPayload()=>{
    'variant_id':product.variantId,'product_name':product.name,'sku':product.sku,'quantity':quantity,'base_quantity':baseQuantity,
    'conversion_to_base':unit.conversionToBase,'unit_id':unit.unitId.isEmpty?null:unit.unitId,'unit_code':unit.code,'unit_price':unitPrice,
    'tax_rate':product.taxRate,'discount_amount':0,'serial_numbers':serialNumbers,'pricing_source':pricingSource,
  };
}

class LocalInvoice {
  final String requestId,localNumber,status;
  final Map<String,dynamic> payload;
  final Map<String,dynamic>? serverResponse;
  final int attempts;
  final String conflictCode,conflictMessage;
  final DateTime createdAt;
  const LocalInvoice({required this.requestId,required this.localNumber,required this.status,required this.payload,this.serverResponse,required this.attempts,required this.conflictCode,required this.conflictMessage,required this.createdAt});
}
