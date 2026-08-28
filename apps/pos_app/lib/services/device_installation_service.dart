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

  const DeviceActivation({
    required this.tenantId,
    required this.tenantName,
    required this.businessCode,
    required this.deviceId,
    required this.deviceCode,
    required this.deviceName,
    required this.deviceSecret,
    required this.locationId,
    required this.locationName,
    required this.locationCode,
  });
}

class DeviceInstallationService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String> installationId() async {
    var value = await _storage.read(key: 'flexi.installation_id');
    if (value == null || value.isEmpty) {
      value = const Uuid().v4();
      await _storage.write(key: 'flexi.installation_id', value: value);
    }
    return value;
  }

  Future<DeviceActivation?> readActivation() async {
    final deviceId = await _storage.read(key: 'flexi.device_id');
    final deviceSecret = await _storage.read(key: 'flexi.device_secret');
    final tenantId = await _storage.read(key: 'flexi.tenant_id');
    final locationId = await _storage.read(key: 'flexi.location_id');
    if ([
      deviceId,
      deviceSecret,
      tenantId,
      locationId,
    ].any((value) => value == null || value.isEmpty)) {
      return null;
    }
    return DeviceActivation(
      tenantId: tenantId!,
      tenantName: await _storage.read(key: 'flexi.tenant_name') ?? 'Business',
      businessCode: await _storage.read(key: 'flexi.business_code') ?? '',
      deviceId: deviceId!,
      deviceCode: await _storage.read(key: 'flexi.device_code') ?? '',
      deviceName: await _storage.read(key: 'flexi.device_name') ?? 'System',
      deviceSecret: deviceSecret!,
      locationId: locationId!,
      locationName: await _storage.read(key: 'flexi.location_name') ?? 'Main',
      locationCode: await _storage.read(key: 'flexi.location_code') ?? 'MAIN',
    );
  }

  Future<DeviceActivation> activate({
    required String businessCode,
    required String activationCode,
    required String appKey,
  }) async {
    final response = await _supabase.functions.invoke(
      'device-activate',
      body: {
        'business_code': businessCode.trim().toUpperCase(),
        'activation_code': activationCode.trim().toUpperCase(),
        'installation_id': await installationId(),
        'app_key': appKey,
        'app_version': '4.8.2',
      },
    );
    if (response.data is! Map) {
      throw Exception('Unexpected activation response.');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    final activation = DeviceActivation(
      tenantId: data['tenant_id']?.toString() ?? '',
      tenantName: data['tenant_name']?.toString() ?? 'Business',
      businessCode: data['business_code']?.toString() ?? '',
      deviceId: data['device_id']?.toString() ?? '',
      deviceCode: data['device_code']?.toString() ?? '',
      deviceName: data['device_name']?.toString() ?? 'System',
      deviceSecret: data['device_secret']?.toString() ?? '',
      locationId: data['location_id']?.toString() ?? '',
      locationName: data['location_name']?.toString() ?? 'Main',
      locationCode: data['location_code']?.toString() ?? 'MAIN',
    );
    if (activation.deviceId.isEmpty ||
        activation.deviceSecret.isEmpty ||
        activation.tenantId.isEmpty ||
        activation.locationId.isEmpty) {
      throw Exception('Activation response was incomplete.');
    }
    await _storage.write(key: 'flexi.tenant_id', value: activation.tenantId);
    await _storage.write(
      key: 'flexi.tenant_name',
      value: activation.tenantName,
    );
    await _storage.write(
      key: 'flexi.business_code',
      value: activation.businessCode,
    );
    await _storage.write(key: 'flexi.device_id', value: activation.deviceId);
    await _storage.write(
      key: 'flexi.device_code',
      value: activation.deviceCode,
    );
    await _storage.write(
      key: 'flexi.device_name',
      value: activation.deviceName,
    );
    await _storage.write(
      key: 'flexi.device_secret',
      value: activation.deviceSecret,
    );
    await _storage.write(
      key: 'flexi.location_id',
      value: activation.locationId,
    );
    await _storage.write(
      key: 'flexi.location_name',
      value: activation.locationName,
    );
    await _storage.write(
      key: 'flexi.location_code',
      value: activation.locationCode,
    );
    return activation;
  }

  /// Refresh mutable logical-system metadata without changing the installation secret.
  /// This lets Admin/Client store assignment, system name/code and location changes
  /// become effective after the app-level Refresh action instead of requiring reactivation.
  Future<void> updateRuntimeBinding({
    required String deviceCode,
    required String deviceName,
    required String locationId,
    required String locationName,
    required String locationCode,
  }) async {
    if (deviceCode.isNotEmpty) {
      await _storage.write(key: 'flexi.device_code', value: deviceCode);
    }
    if (deviceName.isNotEmpty) {
      await _storage.write(key: 'flexi.device_name', value: deviceName);
    }
    if (locationId.isNotEmpty) {
      await _storage.write(key: 'flexi.location_id', value: locationId);
      await _storage.write(key: 'flexi.location_name', value: locationName);
      await _storage.write(key: 'flexi.location_code', value: locationCode);
    }
  }

  Future<void> clearActivation() async {
    for (final key in <String>[
      'flexi.tenant_id',
      'flexi.tenant_name',
      'flexi.business_code',
      'flexi.device_id',
      'flexi.device_code',
      'flexi.device_name',
      'flexi.device_secret',
      'flexi.location_id',
      'flexi.location_name',
      'flexi.location_code',
    ]) {
      await _storage.delete(key: key);
    }
  }
}
