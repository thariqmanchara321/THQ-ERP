import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class DeviceActivation {
  final String tenantId;
  final String tenantName;
  final String businessCode;
  final String deviceId;
  final String deviceCode;
  final String deviceName;
  final String deviceSecret;
  final String locationId;
  final String locationName;
  final String locationCode;

  const DeviceActivation({required this.tenantId,required this.tenantName,required this.businessCode,required this.deviceId,required this.deviceCode,required this.deviceName,required this.deviceSecret,required this.locationId,required this.locationName,required this.locationCode});
}

class DeviceInstallationService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String> installationId() async {
    var value = await _storage.read(key: 'thq.client_mobile.installation_id');
    if (value == null || value.isEmpty) {
      value = const Uuid().v4();
      await _storage.write(key: 'thq.client_mobile.installation_id', value: value);
    }
    return value;
  }

  Future<DeviceActivation?> readActivation() async {
    final deviceId = await _storage.read(key: 'thq.client_mobile.device_id');
    final deviceSecret = await _storage.read(key: 'thq.client_mobile.device_secret');
    final tenantId = await _storage.read(key: 'thq.client_mobile.tenant_id');
    final locationId = await _storage.read(key: 'thq.client_mobile.location_id');
    if ([deviceId, deviceSecret, tenantId, locationId].any((value) => value == null || value.isEmpty)) return null;
    return DeviceActivation(
      tenantId: tenantId!,tenantName: await _storage.read(key: 'thq.client_mobile.tenant_name') ?? 'Business',businessCode: await _storage.read(key: 'thq.client_mobile.business_code') ?? '',
      deviceId: deviceId!,deviceCode: await _storage.read(key: 'thq.client_mobile.device_code') ?? '',deviceName: await _storage.read(key: 'thq.client_mobile.device_name') ?? 'Client Mobile',deviceSecret: deviceSecret!,
      locationId: locationId!,locationName: await _storage.read(key: 'thq.client_mobile.location_name') ?? 'Main',locationCode: await _storage.read(key: 'thq.client_mobile.location_code') ?? 'MAIN',
    );
  }

  Future<DeviceActivation> activate({required String businessCode, required String activationCode}) async {
    final response = await _supabase.functions.invoke('device-activate', body: {
      'business_code': businessCode.trim().toUpperCase(),'activation_code': activationCode.trim().toUpperCase(),'installation_id': await installationId(),'app_key': 'client','app_version': '5.1.0',
    });
    if (response.data is! Map) throw Exception('Unexpected activation response.');
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw Exception(data['error'].toString());
    final activation = DeviceActivation(
      tenantId: data['tenant_id']?.toString() ?? '',tenantName: data['tenant_name']?.toString() ?? 'Business',businessCode: data['business_code']?.toString() ?? '',
      deviceId: data['device_id']?.toString() ?? '',deviceCode: data['device_code']?.toString() ?? '',deviceName: data['device_name']?.toString() ?? 'Client Mobile',deviceSecret: data['device_secret']?.toString() ?? '',
      locationId: data['location_id']?.toString() ?? '',locationName: data['location_name']?.toString() ?? 'Main',locationCode: data['location_code']?.toString() ?? 'MAIN',
    );
    if (activation.deviceId.isEmpty || activation.deviceSecret.isEmpty || activation.tenantId.isEmpty || activation.locationId.isEmpty) throw Exception('Activation response was incomplete.');
    final values = <String, String>{
      'tenant_id': activation.tenantId,'tenant_name': activation.tenantName,'business_code': activation.businessCode,'device_id': activation.deviceId,'device_code': activation.deviceCode,
      'device_name': activation.deviceName,'device_secret': activation.deviceSecret,'location_id': activation.locationId,'location_name': activation.locationName,'location_code': activation.locationCode,
    };
    for (final entry in values.entries) { await _storage.write(key: 'thq.client_mobile.${entry.key}', value: entry.value); }
    return activation;
  }

  Future<void> clearActivation() async {
    for (final key in ['tenant_id','tenant_name','business_code','device_id','device_code','device_name','device_secret','location_id','location_name','location_code']) {
      await _storage.delete(key: 'thq.client_mobile.$key');
    }
  }
}
