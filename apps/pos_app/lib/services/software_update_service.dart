import 'dart:async';
import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_pos_service.dart';

class SoftwareUpdateState {
  final UpdateStatus status;
  final AppReleaseInfo? release;
  final UpdateDownloadProgress? downloadProgress;
  final String? errorMessage;
  final DateTime? lastCheckedAt;
  final DateTime? lastSuccessfulUpdate;
  final File? installerFile;
  final int unsyncedInvoicesCount;

  const SoftwareUpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.downloadProgress,
    this.errorMessage,
    this.lastCheckedAt,
    this.lastSuccessfulUpdate,
    this.installerFile,
    this.unsyncedInvoicesCount = 0,
  });

  SoftwareUpdateState copyWith({
    UpdateStatus? status,
    AppReleaseInfo? release,
    UpdateDownloadProgress? downloadProgress,
    String? errorMessage,
    DateTime? lastCheckedAt,
    DateTime? lastSuccessfulUpdate,
    File? installerFile,
    int? unsyncedInvoicesCount,
    bool clearError = false,
  }) {
    return SoftwareUpdateState(
      status: status ?? this.status,
      release: release ?? this.release,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastSuccessfulUpdate: lastSuccessfulUpdate ?? this.lastSuccessfulUpdate,
      installerFile: installerFile ?? this.installerFile,
      unsyncedInvoicesCount: unsyncedInvoicesCount ?? this.unsyncedInvoicesCount,
    );
  }
}

class SoftwareUpdateService {
  static final SoftwareUpdateService _instance = SoftwareUpdateService._internal();
  factory SoftwareUpdateService() => _instance;
  SoftwareUpdateService._internal();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  final SoftwareUpdateDownloader _downloader = SoftwareUpdateDownloader();
  
  SupabaseClient get _supabase => Supabase.instance.client;

  final ValueNotifier<SoftwareUpdateState> stateNotifier =
      ValueNotifier<SoftwareUpdateState>(const SoftwareUpdateState());

  SoftwareUpdateState get state => stateNotifier.value;

  Timer? _periodicTimer;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    DateTime? lastChecked;
    DateTime? lastSuccess;
    try {
      final checkedStr = await _storage.read(key: 'thq.pos.last_update_check');
      if (checkedStr != null && checkedStr.isNotEmpty) {
        lastChecked = DateTime.tryParse(checkedStr);
      }
      final successStr = await _storage.read(key: 'thq.pos.last_successful_update');
      if (successStr != null && successStr.isNotEmpty) {
        lastSuccess = DateTime.tryParse(successStr);
      }
    } catch (_) {}

    stateNotifier.value = state.copyWith(
      lastCheckedAt: lastChecked,
      lastSuccessfulUpdate: lastSuccess,
    );

    // Warmup background check after 20 seconds, then every 6 hours
    Timer(const Duration(seconds: 20), () {
      checkForUpdate(silent: true);
    });

    _periodicTimer = Timer.periodic(const Duration(hours: 6), (_) {
      checkForUpdate(silent: true);
    });
  }

  void dispose() {
    _periodicTimer?.cancel();
    _downloader.cancel();
  }

  /// Checks whether an update is available for this POS installation
  Future<AppReleaseInfo?> checkForUpdate({
    String channel = 'stable',
    String? deviceId,
    String? tenantId,
    bool silent = false,
  }) async {
    if (state.status == UpdateStatus.downloading || state.status == UpdateStatus.installing) {
      return state.release;
    }

    if (!silent) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.checking,
        clearError: true,
      );
    }

    try {
      final platform = Platform.operatingSystem;
      final currentVersion = ThqReleaseContract.appVersion;
      final currentBuild = ThqReleaseContract.buildNumber;

      final response = await _supabase.rpc(
        'app_release_check_v820',
        params: {
          'p_app_key': 'pos',
          'p_platform': platform,
          'p_channel': channel,
          'p_current_version': currentVersion,
          'p_current_build': currentBuild,
          'p_device_id': deviceId,
          'p_tenant_id': tenantId,
        },
      );

      final now = DateTime.now();
      try {
        await _storage.write(key: 'thq.pos.last_update_check', value: now.toIso8601String());
      } catch (_) {}

      if (response is Map) {
        final map = Map<String, dynamic>.from(response);
        final releaseInfo = AppReleaseInfo.fromMap(map);

        if (releaseInfo.isUpdateAvailable) {
          stateNotifier.value = state.copyWith(
            status: UpdateStatus.available,
            release: releaseInfo,
            lastCheckedAt: now,
            clearError: true,
          );
          return releaseInfo;
        } else {
          stateNotifier.value = state.copyWith(
            status: UpdateStatus.upToDate,
            release: releaseInfo,
            lastCheckedAt: now,
            clearError: true,
          );
          return null;
        }
      }

      stateNotifier.value = state.copyWith(
        status: UpdateStatus.upToDate,
        lastCheckedAt: now,
      );
      return null;
    } catch (e) {
      if (!silent) {
        stateNotifier.value = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'Unable to check for updates: $e',
        );
      }
      return null;
    }
  }

  /// Downloads the release package with SHA-256 integrity verification
  Future<File?> downloadRelease({
    AppReleaseInfo? releaseToDownload,
    String? deviceId,
    String? tenantId,
  }) async {
    final rel = releaseToDownload ?? state.release;
    if (rel == null || rel.downloadUrl == null || rel.downloadUrl!.isEmpty) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Download URL is missing from release metadata.',
      );
      return null;
    }

    stateNotifier.value = state.copyWith(
      status: UpdateStatus.downloading,
      clearError: true,
      downloadProgress: const UpdateDownloadProgress(
        receivedBytes: 0,
        totalBytes: 0,
        progressFraction: 0,
        statusText: 'Connecting to server…',
      ),
    );

    // Record telemetry: started
    _recordLog(
      releaseId: null,
      status: 'downloading',
      targetVersion: rel.latestVersion,
      targetBuild: rel.latestBuild,
      tenantId: tenantId,
      deviceId: deviceId,
    );

    try {
      final appSupport = await getApplicationSupportDirectory();
      final updatesDir = Directory(p.join(appSupport.path, 'THQ ERP', 'updates'));
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      final fileName = 'THQ-POS-v${rel.latestVersion}-b${rel.latestBuild}-setup.exe';
      final targetPath = p.join(updatesDir.path, fileName);

      final downloadedPath = await _downloader.downloadPackage(
        downloadUrl: rel.downloadUrl!,
        destinationPath: targetPath,
        expectedSha256: rel.sha256Checksum,
        expectedSizeBytes: rel.packageSizeBytes,
        expectedPublisherSignature: rel.publisherSignature,
        onProgress: (progress) {
          stateNotifier.value = state.copyWith(
            downloadProgress: progress,
          );
        },
      );

      final installerFile = File(downloadedPath);
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.readyToInstall,
        installerFile: installerFile,
        clearError: true,
      );

      // Record telemetry: downloaded
      _recordLog(
        releaseId: null,
        status: 'downloaded',
        targetVersion: rel.latestVersion,
        targetBuild: rel.latestBuild,
        tenantId: tenantId,
        deviceId: deviceId,
      );

      return installerFile;
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Update download failed: $e',
      );

      _recordLog(
        releaseId: null,
        status: 'failed',
        targetVersion: rel.latestVersion,
        targetBuild: rel.latestBuild,
        errorMessage: e.toString(),
        tenantId: tenantId,
        deviceId: deviceId,
      );
      return null;
    }
  }

  /// Cancels active download
  void cancelDownload() {
    _downloader.cancel();
    stateNotifier.value = state.copyWith(
      status: UpdateStatus.available,
      downloadProgress: null,
    );
  }

  /// Verifies if there are unsynced transactions in POS offline queue
  Future<int> checkUnsyncedInvoices({required String tenantId, required String deviceId}) async {
    try {
      final summary = await OfflinePosService.instance.summary(
        tenantId: tenantId,
        deviceId: deviceId,
      );
      final count = summary.needsAttention;
      stateNotifier.value = state.copyWith(unsyncedInvoicesCount: count);
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Launches the external installer and closes the current application
  Future<bool> installUpdate({
    File? fileToInstall,
    bool silent = false,
    bool forceEvenIfUnsynced = false,
    String? deviceId,
    String? tenantId,
  }) async {
    // Check unsynced offline invoices
    if (!forceEvenIfUnsynced && tenantId != null && deviceId != null) {
      final unsynced = await checkUnsyncedInvoices(tenantId: tenantId, deviceId: deviceId);
      if (unsynced > 0) {
        stateNotifier.value = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'There are $unsynced unsynced offline transactions in queue. Please sync them first before updating.',
        );
        return false;
      }
    }

    final installer = fileToInstall ?? state.installerFile;
    if (installer == null || !await installer.exists()) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Installer file not found on disk. Please download again.',
      );
      return false;
    }

    stateNotifier.value = state.copyWith(
      status: UpdateStatus.installing,
    );

    final rel = state.release;
    final now = DateTime.now();

    try {
      await _storage.write(
        key: 'thq.pos.last_successful_update',
        value: now.toIso8601String(),
      );
    } catch (_) {}

    // Record telemetry: installing
    await _recordLog(
      releaseId: null,
      status: 'installing',
      targetVersion: rel?.latestVersion ?? 'unknown',
      targetBuild: rel?.latestBuild ?? 0,
      tenantId: tenantId,
      deviceId: deviceId,
    );

    try {
      await SoftwareUpdateDownloader.launchWindowsInstaller(
        installerPath: installer.path,
        silent: silent,
      );

      // Give installer process 600ms to initialize before safely exiting
      await Future.delayed(const Duration(milliseconds: 600));
      exit(0);
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to launch installer: $e. You can run the setup manually at: ${installer.path}',
      );

      await _recordLog(
        releaseId: null,
        status: 'failed',
        targetVersion: rel?.latestVersion ?? 'unknown',
        targetBuild: rel?.latestBuild ?? 0,
        errorMessage: e.toString(),
        tenantId: tenantId,
        deviceId: deviceId,
      );
      return false;
    }
  }

  Future<void> _recordLog({
    required String? releaseId,
    required String status,
    required String targetVersion,
    required int targetBuild,
    String? errorMessage,
    String? tenantId,
    String? deviceId,
  }) async {
    try {
      await _supabase.rpc(
        'app_update_log_record_v820',
        params: {
          'p_release_id': releaseId,
          'p_app_key': 'pos',
          'p_from_version': ThqReleaseContract.appVersion,
          'p_from_build': ThqReleaseContract.buildNumber,
          'p_to_version': targetVersion,
          'p_to_build': targetBuild,
          'p_status': status,
          'p_error_message': errorMessage,
          'p_metadata': {
            'platform': Platform.operatingSystem,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          },
          'p_tenant_id': tenantId,
          'p_device_id': deviceId,
        },
      );
    } catch (_) {
      // Telemetry must never crash the update flow
    }
  }
}
