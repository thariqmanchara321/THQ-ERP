import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pos_session.dart';
import 'mobile_pos_local_store.dart';

class MobileSyncResult {final int attempted,synced,conflicts,pending;const MobileSyncResult(this.attempted,this.synced,this.conflicts,this.pending);}
class MobilePosSyncService {
  final _local=MobilePosLocalStore.instance;SupabaseClient get _supabase=>Supabase.instance.client;
  Future<void> refreshCatalogue(PosSession s) async {
    final pr=await _supabase.rpc('pos_offline_product_cache_v486',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId});
    final cr=await _supabase.rpc('pos_offline_customer_cache_v486',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId});
    final mr=await _supabase.rpc('mobile_pos_cache_manifest_v488',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId});
    final serials=<Map<String,dynamic>>[];var after='';for(var page=0;page<100;page++){final raw=await _supabase.rpc('pos_offline_available_serials_v486',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_after':after,'p_limit':1000});final rows=(raw as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();serials.addAll(rows);if(rows.length<1000)break;after=rows.last['serial_number']?.toString()??'';if(after.isEmpty)break;}
    await _local.replaceCatalogue(tenantId:s.tenantId,locationId:s.locationId,products:(pr as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList(),customers:(cr as List? ?? const []).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList(),serials:serials,manifest:mr is Map?Map<String,dynamic>.from(mr):<String,dynamic>{});
  }
  Future<MobileSyncResult> sync(PosSession s,{bool includeConflicts=false,String? only}) async {
    final statuses=<String>{'pending','error'};if(includeConflicts)statuses.add('conflict');var rows=await _local.queue(s.tenantId,s.deviceId,statuses:statuses);if(only!=null)rows=rows.where((x)=>x.requestId==only).toList();var synced=0,conflicts=0,pending=0;
    for(final row in rows.reversed){if(row.status=='conflict')await _local.retry(row.requestId);await _local.markSyncing(row.requestId);try{final raw=await _supabase.rpc('mobile_pos_sale_sync_v488',params:{'p_tenant_id':s.tenantId,'p_device_id':s.deviceId,'p_request_id':row.requestId,'p_payload':row.payload});final m=raw is Map?Map<String,dynamic>.from(raw):<String,dynamic>{};if(m['ok']==false||m['status']=='conflict'){await _local.markConflict(row.requestId,m['code']?.toString()??'SERVER_VALIDATION',m['message']?.toString()??'Server rejected invoice.');conflicts++;}else{await _local.markSynced(row.requestId,m);synced++;}}catch(e){await _local.markPending(row.requestId,e.toString());pending++;break;}}
    if(synced>0){try{await refreshCatalogue(s);}catch(_){}}
    return MobileSyncResult(rows.length,synced,conflicts,pending);
  }
}
