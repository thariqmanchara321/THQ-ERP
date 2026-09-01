import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pos/models/pos_models.dart';
void main(){test('mobile product default unit falls back to base',(){final p=MobileProduct.fromMap({'product_id':'p','variant_id':'v','product_name':'Tea','sku':'T1','base_unit_code':'PCS','selling_price':10});expect(p.defaultUnit.code,'PCS');expect(p.defaultUnit.salePrice,10);});}
