import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/mobile_session.dart';

class MobileClientService {
  SupabaseClient get _supabase => Supabase.instance.client;
  List<Map<String, dynamic>> _rows(dynamic raw) => (raw as List? ?? const []).whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  Map<String, dynamic> _map(dynamic raw) => raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

  Future<Map<String, dynamic>> dashboard(MobileSession s,{String? locationId}) async => _map(await _supabase.rpc('mobile_client_dashboard_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_day':DateTime.now().toIso8601String().split('T').first,'p_location_id':locationId}));
  Future<List<Map<String, dynamic>>> sales(MobileSession s,{String? locationId}) async => _rows(await _supabase.rpc('mobile_sales_status_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_location_id':locationId,'p_limit':150}));
  Future<List<Map<String, dynamic>>> purchases(MobileSession s,{String? locationId}) async => _rows(await _supabase.rpc('mobile_purchases_status_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_location_id':locationId,'p_limit':150}));
  Future<List<Map<String, dynamic>>> inventory(MobileSession s,{String? locationId,String query=''}) async => _rows(await _supabase.rpc('mobile_inventory_status_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_location_id':locationId,'p_query':query,'p_limit':500}));
  Future<List<Map<String, dynamic>>> customerOutstanding(MobileSession s,{String? locationId,String query=''}) async => _rows(await _supabase.rpc('mobile_customer_outstanding_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_location_id':locationId,'p_query':query,'p_limit':500}));
  Future<List<Map<String, dynamic>>> supplierOutstanding(MobileSession s,{String? locationId,String query=''}) async => _rows(await _supabase.rpc('mobile_supplier_outstanding_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_location_id':locationId,'p_query':query,'p_limit':500}));
  Future<List<Map<String, dynamic>>> storePerformance(MobileSession s) async => _rows(await _supabase.rpc('mobile_store_status_v480',params:{'p_tenant_id':s.tenantId,'p_day':DateTime.now().toIso8601String().split('T').first}));
  Future<Map<String, dynamic>> report(MobileSession s,{required DateTime from,required DateTime to,String? locationId}) async => _map(await _supabase.rpc('reports_get_summary_v4',params:{'p_tenant_id':s.tenantId,'p_from_date':_date(from),'p_to_date':_date(to),'p_location_id':locationId}));
  Future<List<Map<String, dynamic>>> approvals(MobileSession s) async => _rows(await _supabase.rpc('mobile_approvals_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_status':'pending','p_limit':300}));
  Future<void> decide(MobileSession s,{required String type,required String id,required bool approve,String note=''}) async { await _supabase.rpc('mobile_approval_decide_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_approval_type':type,'p_id':id,'p_approve':approve,'p_note':note}); }
  Future<Map<String,dynamic>> receiveCustomerPayment(MobileSession s,{required String customerId,required double amount,required String method,String reference='',String notes=''}) async => _map(await _supabase.rpc('mobile_customer_payment_v487',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_customer_id':customerId,'p_amount':amount,'p_payment_method':method,'p_reference_number':reference,'p_notes':notes,'p_sale_id':null,'p_request_id':const Uuid().v4()}));
  String _date(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}
