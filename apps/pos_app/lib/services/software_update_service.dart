import 'dart:async';
import 'dart:convert';
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
  final String? activeAttemptId;
  final String? failedTargetVersion;
  final int? failedTargetBuild;
  final String? lastAttemptReason;
  final String? lastAttemptRawError;
  final DateTime? lastAttemptTimestamp;
  final int? lastAttemptExitCode;
  final String? lastAttemptId;
  final String? lastAttemptStatus;

  const SoftwareUpdateState({
    this.status = UpdateStatus.idle,
    this.release,
    this.downloadProgress,
    this.errorMessage,
    this.lastCheckedAt,
    this.lastSuccessfulUpdate,
    this.installerFile,
    this.unsyncedInvoicesCount = 0,
    this.activeAttemptId,
    this.failedTargetVersion,
    this.failedTargetBuild,
    this.lastAttemptReason,
    this.lastAttemptRawError,
    this.lastAttemptTimestamp,
    this.lastAttemptExitCode,
    this.lastAttemptId,
    this.lastAttemptStatus,
  });

  bool get hasFailedAttempt =>
      failedTargetVersion != null && failedTargetVersion!.isNotEmpty;

  String get installedVersionDisplay =>
      'v${ThqReleaseContract.appVersion} (Build ${ThqReleaseContract.buildNumber})';

  String get latestEligibleVersionDisplay {
    if (release != null && release!.latestVersion.isNotEmpty) {
      return 'v${release!.latestVersion} (Build ${release!.latestBuild})';
    }
    return 'v${ThqReleaseContract.appVersion} (Current)';
  }

  String? get pendingUpdateDisplay {
    if (installerFile != null && release != null) {
      return 'v${release!.latestVersion} (Build ${release!.latestBuild}) ready to install';
    }
    return null;
  }

  SoftwareUpdateState copyWith({
    UpdateStatus? status,
    AppReleaseInfo? release,
    UpdateDownloadProgress? downloadProgress,
    String? errorMessage,
    DateTime? lastCheckedAt,
    DateTime? lastSuccessfulUpdate,
    File? installerFile,
    int? unsyncedInvoicesCount,
    String? activeAttemptId,
    String? failedTargetVersion,
    int? failedTargetBuild,
    String? lastAttemptReason,
    String? lastAttemptRawError,
    DateTime? lastAttemptTimestamp,
    int? lastAttemptExitCode,
    String? lastAttemptId,
    String? lastAttemptStatus,
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
      activeAttemptId: activeAttemptId ?? this.activeAttemptId,
      failedTargetVersion: failedTargetVersion ?? this.failedTargetVersion,
      failedTargetBuild: failedTargetBuild ?? this.failedTargetBuild,
      lastAttemptReason: lastAttemptReason ?? this.lastAttemptReason,
      lastAttemptRawError: lastAttemptRawError ?? this.lastAttemptRawError,
      lastAttemptTimestamp: lastAttemptTimestamp ?? this.lastAttemptTimestamp,
      lastAttemptExitCode: lastAttemptExitCode ?? this.lastAttemptExitCode,
      lastAttemptId: lastAttemptId ?? this.lastAttemptId,
      lastAttemptStatus: lastAttemptStatus ?? this.lastAttemptStatus,
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

  Future<void> initialize({String? tenantId, String? deviceId}) async {
    if (_initialized) return;
    _initialized = true;

    // 1. Load persisted timestamps
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

    // 2. Post-update verification via WindowsUpdateCoordinator
    if (Platform.isWindows) {
      await _verifyPendingUpdateSession(tenantId: tenantId, deviceId: deviceId);
    }

    // 3. Flush any queued offline telemetry logs
    unawaited(_flushOfflineTelemetryQueue());

    // 4. Background check timer: check after 20 seconds, then every 6 hours
    Timer(const Duration(seconds: 20), () {
      checkForUpdate(tenantId: tenantId, deviceId: deviceId, silent: true);
    });

    _periodicTimer = Timer.periodic(const Duration(hours: 6), (_) {
      checkForUpdate(tenantId: tenantId, deviceId: deviceId, silent: true);
    });
  }

  void dispose() {
    _periodicTimer?.cancel();
    _downloader.cancel();
  }

  /// Verifies post-installation restart against the target release.
  /// Success is ONLY recorded when the running executable matches the target version.
  Future<void> _verifyPendingUpdateSession({String? tenantId, String? deviceId}) async {
    try {
      final pending = await WindowsUpdateCoordinator.checkPendingSession();
      if (pending == null) return;

      final currentVersion = ThqReleaseContract.appVersion;
      final currentBuild = ThqReleaseContract.buildNumber;
      final targetVersion = pending.targetVersion;
      final targetBuild = pending.targetBuild;

      final isMatch = (currentVersion == targetVersion && currentBuild == targetBuild) ||
          (pending.status == 'installed' && currentVersion == targetVersion);

      if (isMatch) {
        final now = DateTime.now();
        try {
          await _storage.write(
            key: 'thq.pos.last_successful_update',
            value: now.toIso8601String(),
          );
        } catch (_) {}

        stateNotifier.value = state.copyWith(
          status: UpdateStatus.succeeded,
          lastSuccessfulUpdate: now,
          clearError: true,
          lastAttemptStatus: 'success',
          lastAttemptTimestamp: now,
          lastAttemptId: pending.attemptId,
        );

        // 1. Telemetry: POST_INSTALL_VERIFIED
        await _recordLog(
          releaseId: null,
          status: 'post_install_verified',
          targetVersion: targetVersion,
          targetBuild: targetBuild,
          attemptId: pending.attemptId,
          tenantId: tenantId,
          deviceId: deviceId,
          metadata: {
            'installer_exit_code': pending.installerExitCode,
            'verified_version': currentVersion,
            'verified_build': currentBuild,
          },
        );

        // 2. Telemetry: UPDATE_SUCCESS
        await _recordLog(
          releaseId: null,
          status: 'update_success',
          targetVersion: targetVersion,
          targetBuild: targetBuild,
          attemptId: pending.attemptId,
          tenantId: tenantId,
          deviceId: deviceId,
          metadata: {
            'installer_exit_code': pending.installerExitCode,
            'from_version': pending.fromVersion,
            'from_build': pending.fromBuild,
            'verified_version': currentVersion,
            'verified_build': currentBuild,
            'verified_at': now.toUtc().toIso8601String(),
          },
        );

        await WindowsUpdateCoordinator.clearSession();
      } else {
        final now = DateTime.now();
        final exitCode = pending.installerExitCode;
        
        String diagnosticReason;
        if (exitCode == 1223) {
          diagnosticReason = 'Administrator authorization (UAC) was declined or cancelled.';
        } else if (exitCode == 1) {
          diagnosticReason = 'Installer was cancelled or interrupted before completing setup.';
        } else if (exitCode == 2) {
          diagnosticReason = 'Installer could not close conflicting files or processes.';
        } else if (exitCode != null && exitCode != 0) {
          diagnosticReason = 'Installer exited unexpectedly with code $exitCode.';
        } else {
          diagnosticReason = pending.errorMessage ??
              'Application relaunched with version $currentVersion (Build $currentBuild) instead of target $targetVersion (Build $targetBuild).';
        }

        final rawError = 'Target: v$targetVersion (b$targetBuild), Running: v$currentVersion (b$currentBuild), ExitCode: $exitCode, Status: ${pending.status}, Detail: ${pending.errorMessage ?? 'None'}';

        stateNotifier.value = state.copyWith(
          status: UpdateStatus.failed,
          errorMessage: diagnosticReason,
          failedTargetVersion: targetVersion,
          failedTargetBuild: targetBuild,
          lastAttemptReason: diagnosticReason,
          lastAttemptRawError: rawError,
          lastAttemptTimestamp: now,
          lastAttemptExitCode: exitCode,
          lastAttemptId: pending.attemptId,
          lastAttemptStatus: pending.status == 'recovered' ? 'recovered' : 'failed',
        );

        await _recordLog(
          releaseId: null,
          status: 'install_failed',
          targetVersion: targetVersion,
          targetBuild: targetBuild,
          attemptId: pending.attemptId,
          errorMessage: diagnosticReason,
          tenantId: tenantId,
          deviceId: deviceId,
          metadata: {
            'installer_exit_code': exitCode,
            'session_status': pending.status,
            'reverted_to_version': currentVersion,
            'reverted_to_build': currentBuild,
            'raw_error': rawError,
          },
        );

        await WindowsUpdateCoordinator.clearSession();

        // Re-check for available releases so "Latest Eligible Version" remains known and distinct
        unawaited(checkForUpdate(tenantId: tenantId, deviceId: deviceId, silent: true));
      }
    } catch (e) {
      debugPrint('[SoftwareUpdateService-POS] Error verifying update session: $e');
    }
  }

  /// Checks whether an update is available for this POS installation
  Future<AppReleaseInfo?> checkForUpdate({
    String channel = 'stable',
    String? deviceId,
    String? tenantId,
    String? locationId,
    bool silent = false,
  }) async {
    if (state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.installing ||
        state.status == UpdateStatus.waitingForSafeShutdown) {
      return state.release;
    }

    if (!silent) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.checking,
        clearError: true,
      );
    }

    // Flush any pending telemetry on update checks
    unawaited(_flushOfflineTelemetryQueue());

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

          // Telemetry: UPDATE_AVAILABLE
          await _recordLog(
            releaseId: null,
            status: 'update_available',
            targetVersion: releaseInfo.latestVersion,
            targetBuild: releaseInfo.latestBuild,
            tenantId: tenantId,
            deviceId: deviceId,
            metadata: {
              'channel': channel,
              'mandatory': releaseInfo.isMandatory,
              'package_size_bytes': releaseInfo.packageSizeBytes,
            },
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

    final attemptId = state.activeAttemptId ?? WindowsUpdateCoordinator.generateAttemptId();

    stateNotifier.value = state.copyWith(
      status: UpdateStatus.downloading,
      activeAttemptId: attemptId,
      clearError: true,
      downloadProgress: const UpdateDownloadProgress(
        receivedBytes: 0,
        totalBytes: 0,
        progressFraction: 0,
        statusText: 'Connecting to release server…',
      ),
    );

    // Record telemetry: DOWNLOAD_STARTED
    await _recordLog(
      releaseId: null,
      status: 'download_started',
      targetVersion: rel.latestVersion,
      targetBuild: rel.latestBuild,
      attemptId: attemptId,
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

      stateNotifier.value = state.copyWith(status: UpdateStatus.downloading);

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

      // Record telemetry: DOWNLOAD_COMPLETED & VERIFY_SUCCESS
      await _recordLog(
        releaseId: null,
        status: 'download_completed',
        targetVersion: rel.latestVersion,
        targetBuild: rel.latestBuild,
        attemptId: attemptId,
        tenantId: tenantId,
        deviceId: deviceId,
        metadata: {
          'installer_path': installerFile.path,
          'size_bytes': await installerFile.length(),
        },
      );

      await _recordLog(
        releaseId: null,
        status: 'verify_success',
        targetVersion: rel.latestVersion,
        targetBuild: rel.latestBuild,
        attemptId: attemptId,
        tenantId: tenantId,
        deviceId: deviceId,
        metadata: {
          'sha256': rel.sha256Checksum,
        },
      );

      return installerFile;
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Update download failed: $e',
      );

      await _recordLog(
        releaseId: null,
        status: 'verify_failed',
        targetVersion: rel.latestVersion,
        targetBuild: rel.latestBuild,
        attemptId: attemptId,
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

  /// Coordinates safe installation via detached helper process and restarts.
  /// Protects active operations and offline queues. Never bypasses unsynced transactions.
  /// Success is ONLY marked upon restart and verification.
  Future<bool> installUpdate({
    File? fileToInstall,
    bool silent = false,
    String? deviceId,
    String? tenantId,
  }) async {
    // 1. Mandatory check for unsynced offline transactions
    if (tenantId != null && deviceId != null) {
      final unsynced = await checkUnsyncedInvoices(tenantId: tenantId, deviceId: deviceId);
      ErpUpdateReadinessService().setUnsyncedQueueCount(unsynced);
      if (unsynced > 0) {
        stateNotifier.value = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'There are $unsynced unsynced offline transactions in queue. Please sync them first before updating.',
        );
        return false;
      }
    }

    // 2. Check global ERP operational readiness
    final readiness = ErpUpdateReadinessService();
    if (!readiness.isSafeToUpdate) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'An operation is in progress (${readiness.summaryBlockReason}). The update will be available when your work is safely completed.',
      );
      return false;
    }

    final installer = fileToInstall ?? state.installerFile;
    if (installer == null || !await installer.exists()) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Installer file not found on disk. Please download again.',
      );
      return false;
    }

    final rel = state.release;
    final attemptId = state.activeAttemptId ?? WindowsUpdateCoordinator.generateAttemptId();

    stateNotifier.value = state.copyWith(
      status: UpdateStatus.waitingForSafeShutdown,
    );

    // Record telemetry: INSTALL_STARTED
    await _recordLog(
      releaseId: null,
      status: 'install_started',
      targetVersion: rel?.latestVersion ?? 'unknown',
      targetBuild: rel?.latestBuild ?? 0,
      attemptId: attemptId,
      tenantId: tenantId,
      deviceId: deviceId,
    );

    try {
      if (Platform.isWindows) {
        await WindowsUpdateCoordinator.initiateUpdate(
          appKey: 'pos',
          currentVersion: ThqReleaseContract.appVersion,
          currentBuild: ThqReleaseContract.buildNumber,
          targetVersion: rel?.latestVersion ?? 'unknown',
          targetBuild: rel?.latestBuild ?? 0,
          installerPath: installer.path,
          silent: silent,
          tenantId: tenantId,
          deviceId: deviceId,
        );
        return true;
      } else {
        await SoftwareUpdateDownloader.launchWindowsInstaller(
          installerPath: installer.path,
          silent: silent,
        );
        await Future.delayed(const Duration(milliseconds: 600));
        exit(0);
      }
    } catch (e) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to launch installer: $e. You can run setup manually at: ${installer.path}',
      );

      await _recordLog(
        releaseId: null,
        status: 'install_failed',
        targetVersion: rel?.latestVersion ?? 'unknown',
        targetBuild: rel?.latestBuild ?? 0,
        attemptId: attemptId,
        errorMessage: e.toString(),
        tenantId: tenantId,
        deviceId: deviceId,
      );
      return false;
    }
  }

  /// Safely retries the update by re-validating the release, authorization,
  /// installer integrity, offline queue, and system readiness before launching setup.
  Future<bool> retryUpdate({
    String? tenantId,
    String? deviceId,
    String? locationId,
  }) async {
    // 1. Mandatory check for unsynced offline transactions
    if (tenantId != null && deviceId != null) {
      final unsynced = await checkUnsyncedInvoices(tenantId: tenantId, deviceId: deviceId);
      ErpUpdateReadinessService().setUnsyncedQueueCount(unsynced);
      if (unsynced > 0) {
        stateNotifier.value = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'There are $unsynced unsynced offline transactions in queue. Please sync them first before updating.',
        );
        return false;
      }
    }

    // 2. Check readiness
    final readiness = ErpUpdateReadinessService();
    if (!readiness.isSafeToUpdate) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Cannot retry update now: ${readiness.summaryBlockReason}. Finish active operations first.',
      );
      return false;
    }

    // 3. Revalidate release with server
    final rel = await checkForUpdate(
      tenantId: tenantId,
      deviceId: deviceId,
      locationId: locationId,
    );

    if (rel == null || !rel.isUpdateAvailable) {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.upToDate,
        errorMessage: 'The update is no longer available or was superseded/withdrawn.',
      );
      return false;
    }

    if (rel.status == 'blocked') {
      stateNotifier.value = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'This release has been blocked or recalled by administrators.',
      );
      return false;
    }

    // 4. Verify if local installer already exists and is intact
    final appSupport = await getApplicationSupportDirectory();
    final fileName = 'THQ-POS-v${rel.latestVersion}-b${rel.latestBuild}-setup.exe';
    final candidateFile = File(p.join(appSupport.path, 'THQ ERP', 'updates', fileName));

    File? validInstaller;
    if (await candidateFile.exists()) {
      try {
        final length = await candidateFile.length();
        if (length == rel.packageSizeBytes || rel.packageSizeBytes <= 0) {
          final computedHash = await SoftwareUpdateVerifier.computeFileSha256(candidateFile.path);
          if (rel.sha256Checksum != null &&
              computedHash.toLowerCase() == rel.sha256Checksum!.toLowerCase()) {
            validInstaller = candidateFile;
          }
        }
      } catch (_) {}
    }

    // 5. Download if not valid
    validInstaller ??= await downloadRelease(
      releaseToDownload: rel,
      deviceId: deviceId,
      tenantId: tenantId,
    );

    if (validInstaller == null) {
      return false;
    }

    // 6. Trigger installation
    return installUpdate(
      fileToInstall: validInstaller,
      deviceId: deviceId,
      tenantId: tenantId,
      silent: true,
    );
  }

  /// Generates a structured diagnostic report for operators and support engineers.
  String generateDiagnosticReport({String? tenantId, String? deviceId}) {
    final buffer = StringBuffer();
    buffer.writeln('=== THQ ERP UPDATE DIAGNOSTIC REPORT ===');
    buffer.writeln('Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('Application: THQ POS Client');
    buffer.writeln('Installed Version: v${ThqReleaseContract.appVersion} (Build ${ThqReleaseContract.buildNumber})');
    buffer.writeln('Target Release: ${state.release != null ? "v${state.release!.latestVersion} (Build ${state.release!.latestBuild})" : (state.failedTargetVersion != null ? "v${state.failedTargetVersion} (Build ${state.failedTargetBuild})" : "None")}');
    buffer.writeln('Device ID: ${deviceId ?? "N/A"}');
    buffer.writeln('Tenant ID: ${tenantId ?? "N/A"}');
    buffer.writeln('Update State: ${state.status.name}');
    buffer.writeln('Last Check: ${state.lastCheckedAt?.toIso8601String() ?? "Never"}');
    buffer.writeln('Last Success: ${state.lastSuccessfulUpdate?.toIso8601String() ?? "Never"}');
    buffer.writeln('Active Attempt ID: ${state.activeAttemptId ?? state.lastAttemptId ?? "None"}');
    buffer.writeln('Last Attempt Exit Code: ${state.lastAttemptExitCode ?? "None"}');
    buffer.writeln('Last Attempt Status: ${state.lastAttemptStatus ?? "None"}');
    buffer.writeln('Last Attempt Reason: ${state.lastAttemptReason ?? "None"}');
    buffer.writeln('Raw Error: ${state.lastAttemptRawError ?? state.errorMessage ?? "None"}');
    buffer.writeln('Installer Path: ${state.installerFile?.path ?? "None"}');
    buffer.writeln('Readiness: ${ErpUpdateReadinessService().isSafeToUpdate ? "Ready" : "Blocked (${ErpUpdateReadinessService().summaryBlockReason})"}');
    buffer.writeln('========================================');
    return buffer.toString();
  }

  /// Records update telemetry with proper parameter binding and offline fallback queue
  Future<void> _recordLog({
    required String? releaseId,
    required String status,
    required String targetVersion,
    required int targetBuild,
    String? errorMessage,
    String? tenantId,
    String? deviceId,
    String? attemptId,
    Map<String, dynamic>? metadata,
  }) async {
    final payload = <String, dynamic>{
      'p_app_key': 'pos',
      'p_platform': Platform.operatingSystem,
      'p_device_id': deviceId,
      'p_tenant_id': tenantId,
      'p_from_version': ThqReleaseContract.appVersion,
      'p_from_build': ThqReleaseContract.buildNumber,
      'p_to_version': targetVersion,
      'p_to_build': targetBuild,
      'p_status': status,
      'p_error_message': errorMessage,
      'p_details': () {
        final d = <String, dynamic>{
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        };
        if (attemptId != null) d['attempt_id'] = attemptId;
        if (releaseId != null) d['release_id'] = releaseId;
        if (metadata != null) d.addAll(metadata);
        return d;
      }(),
    };

    try {
      await _supabase.rpc('app_update_log_record_v820', params: payload);
    } catch (e) {
      debugPrint('[SoftwareUpdateService-POS] Telemetry dispatch failed, queueing offline: $e');
      await _queueOfflineLog(payload);
    }
  }

  Future<void> _queueOfflineLog(Map<String, dynamic> payload) async {
    try {
      final existingJson = await _storage.read(key: 'thq.pos.offline_update_logs');
      final list = <Map<String, dynamic>>[];
      if (existingJson != null && existingJson.isNotEmpty) {
        final decoded = jsonDecode(existingJson);
        if (decoded is List) {
          list.addAll(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
        }
      }
      list.add(payload);
      if (list.length > 50) list.removeAt(0); // cap size
      await _storage.write(key: 'thq.pos.offline_update_logs', value: jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _flushOfflineTelemetryQueue() async {
    try {
      final existingJson = await _storage.read(key: 'thq.pos.offline_update_logs');
      if (existingJson == null || existingJson.isEmpty) return;

      final decoded = jsonDecode(existingJson);
      if (decoded is! List || decoded.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      for (final item in decoded) {
        try {
          final payload = Map<String, dynamic>.from(item as Map);
          await _supabase.rpc('app_update_log_record_v820', params: payload);
        } catch (_) {
          remaining.add(Map<String, dynamic>.from(item as Map));
        }
      }

      if (remaining.isEmpty) {
        await _storage.delete(key: 'thq.pos.offline_update_logs');
      } else {
        await _storage.write(key: 'thq.pos.offline_update_logs', value: jsonEncode(remaining));
      }
    } catch (_) {}
  }
}
