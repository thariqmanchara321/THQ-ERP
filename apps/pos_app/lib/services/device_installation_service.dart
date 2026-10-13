import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/workspace_profile.dart';
import 'workspace_manager.dart';

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

  factory DeviceActivation.fromProfile(ThqWorkspaceProfile profile) {
    return DeviceActivation(
      tenantId: profile.tenantId,
      tenantName: profile.tenantName,
      businessCode: profile.businessCode,
      deviceId: profile.deviceId,
      deviceCode: profile.deviceCode,
      deviceName: profile.deviceName,
      deviceSecret: profile.deviceSecret,
      locationId: profile.locationId,
      locationName: profile.locationName,
      locationCode: profile.locationCode,
    );
  }
}

class DeviceInstallationService {
  final ThqWorkspaceManager _workspaceManager = ThqWorkspaceManager();

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<String> installationId() => _workspaceManager.getInstallationId();

  Future<DeviceActivation?> readActivation() async {
    final profile = await _workspaceManager
        .getActiveProfile()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (profile == null) return null;
    return DeviceActivation.fromProfile(profile);
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
        'app_version': ThqReleaseContract.appVersion,
      },
    ).timeout(const Duration(seconds: 15));

    if (response.data is! Map) {
      throw Exception('Unexpected activation response.');
    }

    final data = Map<String, dynamic>.from(response.data as Map);

    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }

    final tenantId = data['tenant_id']?.toString() ?? '';
    final tenantName = data['tenant_name']?.toString() ?? 'Business';
    final bCode = data['business_code']?.toString() ?? businessCode.trim().toUpperCase();
    final deviceId = data['device_id']?.toString() ?? '';
    final deviceCode = data['device_code']?.toString() ?? '';
    final deviceName = data['device_name']?.toString() ?? 'POS Counter';
    final deviceSecret = data['device_secret']?.toString() ?? '';
    final locationId = data['location_id']?.toString() ?? '';
    final locationName = data['location_name']?.toString() ?? 'Main';
    final locationCode = data['location_code']?.toString() ?? 'MAIN';

    if (deviceId.isEmpty || deviceSecret.isEmpty || tenantId.isEmpty || locationId.isEmpty) {
      throw Exception('Activation response was incomplete.');
    }

    final profile = ThqWorkspaceProfile(
      id: const Uuid().v4(),
      tenantId: tenantId,
      tenantName: tenantName,
      businessCode: bCode,
      locationId: locationId,
      locationName: locationName,
      locationCode: locationCode,
      deviceId: deviceId,
      deviceCode: deviceCode,
      deviceName: deviceName,
      deviceSecret: deviceSecret,
      appKey: appKey,
      activatedAt: DateTime.now(),
      lastActiveAt: DateTime.now(),
    );

    await _workspaceManager.saveProfile(profile);
    return DeviceActivation.fromProfile(profile);
  }

  Future<void> updateRuntimeBinding({
    required String deviceCode,
    required String deviceName,
    required String locationId,
    required String locationName,
    required String locationCode,
  }) async {
    final profile = await _workspaceManager.getActiveProfile();
    if (profile == null) return;

    await _workspaceManager.updateProfileLocation(
      profileId: profile.id,
      locationId: locationId.isNotEmpty ? locationId : profile.locationId,
      locationName: locationName.isNotEmpty ? locationName : profile.locationName,
      locationCode: locationCode.isNotEmpty ? locationCode : profile.locationCode,
    );
  }

  Future<DeviceActivation?> readAndVerifyActivation() async {
    final profile = await _workspaceManager
        .getActiveProfile()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (profile == null) return null;

    try {
      final res = await _supabase.rpc(
        'verify_device_binding_v704',
        params: {
          'p_device_id': profile.deviceId,
          'p_tenant_id': profile.tenantId,
        },
      ).timeout(const Duration(seconds: 8));

      if (res is Map) {
        final valid = res['valid'] == true;
        if (!valid) {
          await _workspaceManager.removeProfile(profile.id);
          try {
            await _supabase.auth.signOut();
          } catch (_) {}
          return null;
        }
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('device_revoked') || msg.contains('business_deleted')) {
        await _workspaceManager.removeProfile(profile.id);
        try {
          await _supabase.auth.signOut();
        } catch (_) {}
        return null;
      }
    }

    return DeviceActivation.fromProfile(profile);
  }

  /// Removes the currently active workspace profile only.
  Future<void> clearActivation() async {
    final profile = await _workspaceManager.getActiveProfile();
    if (profile != null) {
      await _workspaceManager.removeProfile(profile.id);
    }
  }

  /// Removes all saved workspace profiles (full reset).
  Future<void> resetAllWorkspaces() async {
    await _workspaceManager.clearAllWorkspaces();
  }
}
