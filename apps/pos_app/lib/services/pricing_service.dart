import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PricingService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<List<Map<String,dynamic>>> priceLists(String tenantId) async {
    final result=await _supabase.rpc('pricing_lists_v482',params:{'p_tenant_id':tenantId});
    return (result as List? ?? const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<String> savePriceList({required String tenantId,String? priceListId,required String code,required String name,String description='',required bool isDefault,bool active=true}) async {
    final r=await _supabase.rpc('pricing_list_save_v482',params:{'p_tenant_id':tenantId,'p_price_list_id':priceListId,'p_code':code.trim(),'p_name':name.trim(),'p_description':description.trim(),'p_is_default':isDefault,'p_active':active});return r?.toString()??'';
  }
  Future<List<Map<String,dynamic>>> priceRules({required String tenantId,required String priceListId,String? variantId}) async {
    final r=await _supabase.rpc('pricing_rules_v482',params:{'p_tenant_id':tenantId,'p_price_list_id':priceListId,'p_variant_id':variantId});return (r as List? ?? const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<String> savePriceRule({required String tenantId,String? ruleId,required String priceListId,required String variantId,required String unitId,required double minQuantity,required double unitPrice,bool active=true}) async {
    final r=await _supabase.rpc('pricing_rule_save_v482',params:{'p_tenant_id':tenantId,'p_rule_id':ruleId,'p_price_list_id':priceListId,'p_variant_id':variantId,'p_unit_id':unitId,'p_min_quantity':minQuantity,'p_unit_price':unitPrice,'p_active':active});return r?.toString()??'';
  }
  Future<void> setCustomerPriceList({required String tenantId,required String customerId,String? priceListId})=>_supabase.rpc('customer_pricing_profile_set_v482',params:{'p_tenant_id':tenantId,'p_customer_id':customerId,'p_price_list_id':priceListId});
  Future<List<Map<String,dynamic>>> customerPrices({required String tenantId,required String customerId,String? variantId}) async {
    final r=await _supabase.rpc('customer_prices_v482',params:{'p_tenant_id':tenantId,'p_customer_id':customerId,'p_variant_id':variantId});return (r as List? ?? const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  }
  Future<String> saveCustomerPrice({required String tenantId,String? ruleId,required String customerId,required String variantId,required String unitId,required double minQuantity,required double unitPrice,bool active=true}) async {
    final r=await _supabase.rpc('customer_price_save_v482',params:{'p_tenant_id':tenantId,'p_rule_id':ruleId,'p_customer_id':customerId,'p_variant_id':variantId,'p_unit_id':unitId,'p_min_quantity':minQuantity,'p_unit_price':unitPrice,'p_active':active});return r?.toString()??'';
  }
  Future<PriceResolution> resolve({required String tenantId,required String variantId,String? customerId,String? unitId,required double quantity,String? locationId}) async {
    final r=await _supabase.rpc('pricing_resolve_v482',params:{'p_tenant_id':tenantId,'p_variant_id':variantId,'p_customer_id':customerId,'p_unit_id':unitId,'p_quantity':quantity,'p_location_id':locationId});
    return PriceResolution.fromMap(Map<String,dynamic>.from(r as Map));
  }
}
