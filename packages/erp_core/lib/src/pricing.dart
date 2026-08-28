class PriceResolution {
  final String variantId;
  final String? customerId;
  final String unitId;
  final double quantity;
  final double unitPrice;
  final String source;
  final String? priceListId;
  final String? priceListName;

  const PriceResolution({required this.variantId, required this.customerId, required this.unitId, required this.quantity, required this.unitPrice, required this.source, required this.priceListId, required this.priceListName});

  factory PriceResolution.fromMap(Map<String,dynamic> map) {
    double n(dynamic v)=>v is num?v.toDouble():double.tryParse(v?.toString()??'')??0;
    return PriceResolution(
      variantId: map['variant_id']?.toString()??'', customerId: map['customer_id']?.toString(),
      unitId: map['unit_id']?.toString()??'', quantity:n(map['quantity']), unitPrice:n(map['unit_price']),
      source: map['source']?.toString()??'product_price', priceListId: map['price_list_id']?.toString(), priceListName: map['price_list_name']?.toString());
  }
  String get sourceLabel => switch(source) {
    'customer'=>'Customer Price',
    'price_list'=>priceListName?.isNotEmpty==true?priceListName!:'Price List',
    'unit_price'=>'Unit Price',
    'location_price'=>'Store Price',
    _=>'Retail Price',
  };
}

class ProductIdentifier {
  final String id; final String variantId; final String type; final String code;
  final String? supplierId; final String? supplierName; final String? label;
  final bool isPrimary; final bool generated; final bool active;
  const ProductIdentifier({required this.id,required this.variantId,required this.type,required this.code,required this.supplierId,required this.supplierName,required this.label,required this.isPrimary,required this.generated,required this.active});
  factory ProductIdentifier.fromMap(Map<String,dynamic> map)=>ProductIdentifier(
    id:map['identifier_id']?.toString()??map['id']?.toString()??'',variantId:map['variant_id']?.toString()??'',
    type:map['identifier_type']?.toString()??map['type']?.toString()??'barcode',code:map['code']?.toString()??'',
    supplierId:map['supplier_id']?.toString(),supplierName:map['supplier_name']?.toString(),label:map['label']?.toString(),
    isPrimary:map['is_primary']==true,generated:map['generated']==true,active:map['active']!=false);
}
