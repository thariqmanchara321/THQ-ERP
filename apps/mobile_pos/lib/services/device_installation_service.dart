import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class DeviceActivation {
  final String tenantId,tenantName,businessCode,deviceId,deviceCode,deviceName,deviceSecret,locationId,locationName,locationCode;
  const DeviceActivation({required this.tenantId,required this.tenantName,required this.businessCode,required this.deviceId,required this.deviceCode,required this.deviceName,required this.deviceSecret,required this.locationId,required this.locationName,required this.locationCode});
}
class DeviceInstallationService {
  static const _storage=FlutterSecureStorage();
  SupabaseClient get _supabase=>Supabase.instance.client;
  static const _prefix='thq.mobile_pos.';
  Future<String> installationId() async {var v=await _storage.read(key:'${_prefix}installation_id');if(v==null||v.isEmpty){v=const Uuid().v4();await _storage.write(key:'${_prefix}installation_id',value:v);}return v;}
  Future<DeviceActivation?> readActivation() async {
    final d=await _storage.read(key:'${_prefix}device_id'),s=await _storage.read(key:'${_prefix}device_secret'),t=await _storage.read(key:'${_prefix}tenant_id'),l=await _storage.read(key:'${_prefix}location_id');
    if([d,s,t,l].any((v)=>v==null||v.isEmpty))return null;
    return DeviceActivation(tenantId:t!,tenantName:await _storage.read(key:'${_prefix}tenant_name')??'Business',businessCode:await _storage.read(key:'${_prefix}business_code')??'',deviceId:d!,deviceCode:await _storage.read(key:'${_prefix}device_code')??'',deviceName:await _storage.read(key:'${_prefix}device_name')??'Mobile POS',deviceSecret:s!,locationId:l!,locationName:await _storage.read(key:'${_prefix}location_name')??'Main',locationCode:await _storage.read(key:'${_prefix}location_code')??'MAIN');
  }
  Future<DeviceActivation> activate({required String businessCode,required String activationCode}) async {
    final response=await _supabase.functions.invoke('device-activate',body:{'business_code':businessCode.trim().toUpperCase(),'activation_code':activationCode.trim().toUpperCase(),'installation_id':await installationId(),'app_key':'pos','app_version':'5.1.0'});
    if(response.data is! Map)throw Exception('Unexpected activation response.');final data=Map<String,dynamic>.from(response.data as Map);if(data['error']!=null)throw Exception(data['error'].toString());
    final a=DeviceActivation(tenantId:data['tenant_id']?.toString()??'',tenantName:data['tenant_name']?.toString()??'Business',businessCode:data['business_code']?.toString()??'',deviceId:data['device_id']?.toString()??'',deviceCode:data['device_code']?.toString()??'',deviceName:data['device_name']?.toString()??'Mobile POS',deviceSecret:data['device_secret']?.toString()??'',locationId:data['location_id']?.toString()??'',locationName:data['location_name']?.toString()??'Main',locationCode:data['location_code']?.toString()??'MAIN');
    if(a.deviceId.isEmpty||a.deviceSecret.isEmpty||a.tenantId.isEmpty||a.locationId.isEmpty)throw Exception('Activation response was incomplete.');
    final values={'tenant_id':a.tenantId,'tenant_name':a.tenantName,'business_code':a.businessCode,'device_id':a.deviceId,'device_code':a.deviceCode,'device_name':a.deviceName,'device_secret':a.deviceSecret,'location_id':a.locationId,'location_name':a.locationName,'location_code':a.locationCode};
    for(final e in values.entries){await _storage.write(key:'$_prefix${e.key}',value:e.value);}return a;
  }
  Future<void> clearActivation() async {for(final k in ['tenant_id','tenant_name','business_code','device_id','device_code','device_name','device_secret','location_id','location_name','location_code']){await _storage.delete(key:'$_prefix$k');}}
}
