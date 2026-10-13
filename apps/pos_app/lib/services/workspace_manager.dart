import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/workspace_profile.dart';

/// Manages multiple saved business/store location activations on this POS installation.
///
/// Features:
/// 1. Complete namespace isolation per application (POSIX prefix `thq.pos`).
/// 2. Automatic migration of legacy `flexi.*` activation keys into a workspace profile.
/// 3. Multiple saved workspace profiles with an active profile pointer.
/// 4. Store switching within a profile without losing activation or forcing logout.
class ThqWorkspaceManager {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String appKey = 'pos';

  static final ThqWorkspaceManager _instance = ThqWorkspaceManager._internal();
  factory ThqWorkspaceManager() => _instance;
  ThqWorkspaceManager._internal();

  List<ThqWorkspaceProfile>? _cachedProfiles;
  String? _cachedActiveId;
  String? _cachedInstallationId;

  String _key(String suffix) {
    final env = SupabaseConfig.environment;
    final prefix = env == 'production' ? 'thq.pos' : '$env.thq.pos';
    return '$prefix.$suffix';
  }

  /// Installation ID: stable unique installation identifier stored securely.
  Future<String> getInstallationId() async {
    if (_cachedInstallationId != null && _cachedInstallationId!.isNotEmpty) {
      return _cachedInstallationId!;
    }
    final key = _key('installation_id');
    var val = await _storage
        .read(key: key)
        .timeout(const Duration(seconds: 4), onTimeout: () => null);
    if (val == null || val.isEmpty) {
      final legacyKey = SupabaseConfig.environment == 'production'
          ? 'flexi.installation_id'
          : '${SupabaseConfig.environment}.flexi.installation_id';
      val = await _storage
          .read(key: legacyKey)
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      if (val == null || val.isEmpty) {
        val = const Uuid().v4();
      }
      try {
        await _storage
            .write(key: key, value: val)
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    _cachedInstallationId = val;
    return val;
  }

  /// Returns all saved workspace profiles.
  Future<List<ThqWorkspaceProfile>> getProfiles({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedProfiles != null) {
      return List.unmodifiable(_cachedProfiles!);
    }

    String? raw;
    try {
      raw = await _storage
          .read(key: _key('workspaces'))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      return _cachedProfiles ?? [];
    }

    if (raw == null || raw.isEmpty) {
      final legacy = await _migrateLegacyActivation();
      if (legacy != null) {
        final profileWithTime = legacy.copyWith(lastActiveAt: DateTime.now());
        final migratedList = [profileWithTime];
        _cachedProfiles = migratedList;
        _cachedActiveId = profileWithTime.id;
        await _saveProfilesList(migratedList);
        try {
          await _storage
              .write(key: _key('active_workspace_id'), value: profileWithTime.id)
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
        return migratedList;
      }
      _cachedProfiles = [];
      return [];
    }

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final parsed = list
          .map((item) =>
              ThqWorkspaceProfile.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
      _cachedProfiles = parsed;
      return List.unmodifiable(parsed);
    } catch (_) {
      return [];
    }
  }

  /// Returns the currently active workspace profile, or null if none saved.
  Future<ThqWorkspaceProfile?> getActiveProfile() async {
    final profiles = await getProfiles();
    if (profiles.isEmpty) return null;

    if (_cachedActiveId != null && _cachedActiveId!.isNotEmpty) {
      final match = profiles.where((p) => p.id == _cachedActiveId);
      if (match.isNotEmpty) return match.first;
    }

    String? activeId;
    try {
      activeId = await _storage
          .read(key: _key('active_workspace_id'))
          .timeout(const Duration(seconds: 4));
    } catch (_) {}

    if (activeId != null && activeId.isNotEmpty) {
      _cachedActiveId = activeId;
      final match = profiles.where((p) => p.id == activeId);
      if (match.isNotEmpty) return match.first;
    }

    // Default to the most recently active profile
    final sorted = [...profiles]
      ..sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
    final defaultProfile = sorted.first;
    _cachedActiveId = defaultProfile.id;
    try {
      await _storage
          .write(key: _key('active_workspace_id'), value: defaultProfile.id)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
    return defaultProfile;
  }

  /// Sets the currently active workspace profile by ID.
  Future<void> setActiveProfile(String profileId) async {
    final current = await getProfiles();
    final profiles = [...current];
    final index = profiles.indexWhere((p) => p.id == profileId);
    if (index == -1) return;

    final updated = profiles[index].copyWith(lastActiveAt: DateTime.now());
    profiles[index] = updated;
    _cachedProfiles = profiles;
    _cachedActiveId = profileId;

    await _saveProfilesList(profiles);
    try {
      await _storage
          .write(key: _key('active_workspace_id'), value: profileId)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Saves a new profile or updates an existing one, and makes it active.
  Future<void> saveProfile(ThqWorkspaceProfile profile) async {
    final current = await getProfiles();
    final profiles = [...current];

    final index = profiles.indexWhere(
      (p) =>
          p.id == profile.id ||
          (p.tenantId == profile.tenantId && p.locationId == profile.locationId),
    );

    final updatedProfile = profile.copyWith(lastActiveAt: DateTime.now());
    if (index >= 0) {
      profiles[index] = updatedProfile;
    } else {
      profiles.add(updatedProfile);
    }

    _cachedProfiles = profiles;
    _cachedActiveId = updatedProfile.id;

    await _saveProfilesList(profiles);
    try {
      await _storage
          .write(key: _key('active_workspace_id'), value: updatedProfile.id)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Updates the active store/location of a profile without re-activating.
  Future<void> updateProfileLocation({
    required String profileId,
    required String locationId,
    required String locationName,
    required String locationCode,
  }) async {
    final current = await getProfiles();
    final profiles = [...current];
    final index = profiles.indexWhere((p) => p.id == profileId);
    if (index == -1) return;

    final updated = profiles[index].copyWith(
      locationId: locationId,
      locationName: locationName,
      locationCode: locationCode,
      lastActiveAt: DateTime.now(),
    );
    profiles[index] = updated;
    _cachedProfiles = profiles;

    await _saveProfilesList(profiles);
  }

  /// Removes a single workspace profile.
  Future<void> removeProfile(String profileId) async {
    final current = await getProfiles();
    final profiles = [...current];
    profiles.removeWhere((p) => p.id == profileId);
    _cachedProfiles = profiles;

    await _saveProfilesList(profiles);

    if (_cachedActiveId == profileId) {
      if (profiles.isNotEmpty) {
        _cachedActiveId = profiles.first.id;
        try {
          await _storage
              .write(key: _key('active_workspace_id'), value: profiles.first.id)
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
      } else {
        _cachedActiveId = null;
        try {
          await _storage
              .delete(key: _key('active_workspace_id'))
              .timeout(const Duration(seconds: 4));
        } catch (_) {}
      }
    }
  }

  /// Completely resets all local activations on this POS installation.
  Future<void> clearAllWorkspaces() async {
    _cachedProfiles = [];
    _cachedActiveId = null;
    _cachedInstallationId = null;

    try {
      await _storage
          .delete(key: _key('workspaces'))
          .timeout(const Duration(seconds: 4));
      await _storage
          .delete(key: _key('active_workspace_id'))
          .timeout(const Duration(seconds: 4));

      final env = SupabaseConfig.environment;
      final prefix = env == 'production' ? 'flexi' : '$env.flexi';
      for (final k in [
        'tenant_id',
        'tenant_name',
        'business_code',
        'device_id',
        'device_code',
        'device_name',
        'device_secret',
        'location_id',
        'location_name',
        'location_code',
      ]) {
        await _storage
            .delete(key: '$prefix.$k')
            .timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
  }

  Future<void> _saveProfilesList(List<ThqWorkspaceProfile> profiles) async {
    final raw = jsonEncode(profiles.map((p) => p.toMap()).toList());
    try {
      await _storage
          .write(key: _key('workspaces'), value: raw)
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<ThqWorkspaceProfile?> _migrateLegacyActivation() async {
    final env = SupabaseConfig.environment;
    final prefix = env == 'production' ? 'flexi' : '$env.flexi';

    Future<String?> safeRead(String key) async {
      try {
        return await _storage
            .read(key: key)
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
      } catch (_) {
        return null;
      }
    }

    final deviceId = await safeRead('$prefix.device_id');
    final deviceSecret = await safeRead('$prefix.device_secret');
    final tenantId = await safeRead('$prefix.tenant_id');
    final locationId = await safeRead('$prefix.location_id');

    if ([deviceId, deviceSecret, tenantId, locationId].any((v) => v == null || v.isEmpty)) {
      return null;
    }

    final tenantName = await safeRead('$prefix.tenant_name') ?? 'Business';
    final businessCode = await safeRead('$prefix.business_code') ?? '';
    final deviceCode = await safeRead('$prefix.device_code') ?? '';
    final deviceName = await safeRead('$prefix.device_name') ?? 'System';
    final locationName = await safeRead('$prefix.location_name') ?? 'Main';
    final locationCode = await safeRead('$prefix.location_code') ?? 'MAIN';

    return ThqWorkspaceProfile(
      id: const Uuid().v4(),
      tenantId: tenantId!,
      tenantName: tenantName,
      businessCode: businessCode,
      locationId: locationId!,
      locationName: locationName,
      locationCode: locationCode,
      deviceId: deviceId!,
      deviceCode: deviceCode,
      deviceName: deviceName,
      deviceSecret: deviceSecret!,
      appKey: appKey,
      activatedAt: DateTime.now(),
      lastActiveAt: DateTime.now(),
    );
  }
}
