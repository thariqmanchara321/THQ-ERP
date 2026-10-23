import 'dart:async';
import 'package:erp_core/erp_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DatabaseConnectionStatus {
  checking,
  connected,
  disconnected,
}

class SystemHealthReport {
  final bool isRuntimeOperational;
  final DatabaseConnectionStatus databaseStatus;
  final int? databaseLatencyMs;
  final String? databaseErrorMessage;
  final String appVersion;
  final int buildNumber;
  final DateTime? lastSuccessfulUpdate;
  final DateTime checkedAt;
  final String updateVerificationMessage;

  const SystemHealthReport({
    required this.isRuntimeOperational,
    required this.databaseStatus,
    this.databaseLatencyMs,
    this.databaseErrorMessage,
    required this.appVersion,
    required this.buildNumber,
    this.lastSuccessfulUpdate,
    required this.checkedAt,
    this.updateVerificationMessage = 'THQ Update Test #2 — New Feature Installed',
  });

  String get databaseStatusDisplay {
    switch (databaseStatus) {
      case DatabaseConnectionStatus.checking:
        return 'Checking…';
      case DatabaseConnectionStatus.connected:
        return databaseLatencyMs != null ? 'Connected ($databaseLatencyMs ms)' : 'Connected';
      case DatabaseConnectionStatus.disconnected:
        return 'Disconnected';
    }
  }

  String get applicationStatusDisplay {
    return isRuntimeOperational ? 'Running (Operational)' : 'Degraded';
  }

  String get versionBuildDisplay {
    return 'v$appVersion (Build $buildNumber)';
  }
}

class SystemHealthService {
  final SupabaseClient? _customClient;
  final FlutterSecureStorage _storage;
  final Future<dynamic> Function(Duration timeout)? _customDbChecker;
  final String? _customAppVersion;
  final int? _customBuildNumber;

  SystemHealthService({
    SupabaseClient? client,
    FlutterSecureStorage? storage,
    // ignore: prefer_initializing_formals
    Future<dynamic> Function(Duration timeout)? customDbChecker,
    String? appVersion,
    int? buildNumber,
  })  : _customClient = client,
        _storage = storage ?? const FlutterSecureStorage(),
        _customDbChecker = customDbChecker,
        _customAppVersion = appVersion,
        _customBuildNumber = buildNumber;

  SupabaseClient? get _supabase {
    if (_customClient != null) return _customClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Executes runtime verification and a lightweight, read-only Supabase connectivity check
  Future<SystemHealthReport> runSystemCheck({
    String? tenantId,
    String? deviceId,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final now = DateTime.now();

    // 1. Runtime operational check
    final effectiveVersion = _customAppVersion ?? ThqReleaseContract.appVersion;
    final effectiveBuild = _customBuildNumber ?? ThqReleaseContract.buildNumber;
    final isOperational = effectiveVersion.isNotEmpty && effectiveBuild > 0;

    // 2. Read last verified successful update timestamp from secure storage
    DateTime? lastUpdate;
    try {
      final lastUpdateStr = await _storage
          .read(key: 'thq.client.last_successful_update')
          .timeout(const Duration(milliseconds: 500));
      if (lastUpdateStr != null && lastUpdateStr.isNotEmpty) {
        lastUpdate = DateTime.tryParse(lastUpdateStr);
      }
    } catch (_) {}

    // 3. Perform read-only database check with bounded timeout
    DatabaseConnectionStatus dbStatus = DatabaseConnectionStatus.checking;
    int? latencyMs;
    String? errorMessage;

    final stopwatch = Stopwatch()..start();

    if (_customDbChecker != null) {
      try {
        await _customDbChecker(timeout);
        stopwatch.stop();
        dbStatus = DatabaseConnectionStatus.connected;
        latencyMs = stopwatch.elapsedMilliseconds;
      } on TimeoutException {
        stopwatch.stop();
        dbStatus = DatabaseConnectionStatus.disconnected;
        errorMessage = 'Database query timed out (> ${timeout.inSeconds}s)';
      } catch (e) {
        stopwatch.stop();
        dbStatus = DatabaseConnectionStatus.disconnected;
        errorMessage = e.toString();
      }
    } else {
      final client = _supabase;
      if (client == null) {
        stopwatch.stop();
        dbStatus = DatabaseConnectionStatus.disconnected;
        errorMessage = 'Supabase client is not initialized.';
      } else {
        try {
          // Perform a strictly read-only check: ping RPC or release check RPC
          await client.rpc(
            'app_release_check_v820',
            params: {
              'p_app_key': 'client',
              'p_platform': 'windows',
              'p_channel': 'stable',
              'p_current_version': effectiveVersion,
              'p_current_build': effectiveBuild,
              'p_device_id': ?deviceId,
              'p_tenant_id': ?tenantId,
            },
          ).timeout(timeout);

          stopwatch.stop();
          dbStatus = DatabaseConnectionStatus.connected;
          latencyMs = stopwatch.elapsedMilliseconds;
        } on TimeoutException {
          stopwatch.stop();
          dbStatus = DatabaseConnectionStatus.disconnected;
          errorMessage = 'Database query timed out (> ${timeout.inSeconds}s)';
        } catch (e) {
          stopwatch.stop();
          dbStatus = DatabaseConnectionStatus.disconnected;
          errorMessage = e.toString();
        }
      }
    }

    return SystemHealthReport(
      isRuntimeOperational: isOperational,
      databaseStatus: dbStatus,
      databaseLatencyMs: latencyMs,
      databaseErrorMessage: errorMessage,
      appVersion: effectiveVersion,
      buildNumber: effectiveBuild,
      lastSuccessfulUpdate: lastUpdate,
      checkedAt: now,
      updateVerificationMessage: 'THQ Update Test #2 — New Feature Installed',
    );
  }
}
