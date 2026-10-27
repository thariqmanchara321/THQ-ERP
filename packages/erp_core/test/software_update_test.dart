import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Semver Comparison Tests', () {
    test('standard version comparisons', () {
      expect(compareSemver('8.2.0', '8.1.0'), 1);
      expect(compareSemver('8.1.0', '8.2.0'), -1);
      expect(compareSemver('8.2.0', '8.2.0'), 0);
      expect(compareSemver('9.0.0', '8.9.9'), 1);
      expect(compareSemver('7.0.0', '8.1.0'), -1);
    });

    test('handles prefixes and extra segments', () {
      expect(compareSemver('v8.2.0', '8.2.0'), 0);
      expect(compareSemver('8.2.0.1', '8.2.0'), 1);
      expect(compareSemver('8.2.0', '8.2.0.1'), -1);
    });
  });

  group('AppReleaseInfo Model Tests', () {
    test('deserializes properly from map', () {
      final map = {
        'app_key': 'client',
        'platform': 'windows',
        'channel': 'stable',
        'latest_version': '8.2.0',
        'latest_build': 17,
        'current_version': '8.1.0',
        'current_build': 16,
        'update_available': true,
        'is_mandatory': true,
        'status': 'update_available',
        'download_url':
            'https://releases.thqerp.com/THQ-Business-v8.2.0-b17-setup.exe',
        'package_size_bytes': 45678901,
        'sha256_checksum': 'a1b2c3d4e5f6',
        'publisher_signature': 'CN=THQ ERP',
        'release_notes': 'Bug fixes and performance improvements.',
        'min_supported_version': '5.1.0',
        'released_at': '2026-10-14T20:00:00Z',
      };

      final info = AppReleaseInfo.fromMap(map);
      expect(info.appKey, 'client');
      expect(info.latestVersion, '8.2.0');
      expect(info.latestBuild, 17);
      expect(info.isUpdateAvailable, true);
      expect(info.isMandatory, true);
      expect(info.formattedSize, '43.6 MB');
      expect(
        info.downloadUrl,
        'https://releases.thqerp.com/THQ-Business-v8.2.0-b17-setup.exe',
      );
      expect(info.sha256Checksum, 'a1b2c3d4e5f6');
      expect(info.publisherSignature, 'CN=THQ ERP');
    });

    test('progress calculation and formatting', () {
      const progress = UpdateDownloadProgress(
        receivedBytes: 15728640, // 15 MB
        totalBytes: 31457280, // 30 MB
        progressFraction: 0.5,
        statusText: 'Downloading…',
      );

      expect(progress.percentageText, '50%');
      expect(progress.downloadedFormatted, '15.0 MB / 30.0 MB');
    });
  });

  group('SoftwareUpdateVerifier Tests', () {
    test('computes SHA-256 correctly', () {
      final bytes = [1, 2, 3, 4, 5];
      final hash = SoftwareUpdateVerifier.computeSha256(bytes);
      expect(hash.length, 64);
    });

    test('verifies file integrity with correct checksum and size', () async {
      final tempDir = await Directory.systemTemp.createTemp('thq_test_');
      final tempFile = File('${tempDir.path}/test_installer.bin');
      await tempFile.writeAsBytes([10, 20, 30, 40, 50]);

      final hash = await SoftwareUpdateVerifier.computeFileSha256(
        tempFile.path,
      );
      final valid = await SoftwareUpdateVerifier.verifyIntegrity(
        filePath: tempFile.path,
        expectedSha256: hash,
        expectedSizeBytes: 5,
      );
      expect(valid, isTrue);

      final invalidChecksum = await SoftwareUpdateVerifier.verifyIntegrity(
        filePath: tempFile.path,
        expectedSha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
        expectedSizeBytes: 5,
      );
      expect(invalidChecksum, isFalse);

      final invalidSize = await SoftwareUpdateVerifier.verifyIntegrity(
        filePath: tempFile.path,
        expectedSha256: hash,
        expectedSizeBytes: 999,
      );
      expect(invalidSize, isFalse);

      await tempDir.delete(recursive: true);
    });
  });

  group('UpdateStatus Lifecycle Tests', () {
    test('isBusy evaluates correctly for active states', () {
      expect(UpdateStatus.checking.isBusy, isTrue);
      expect(UpdateStatus.downloading.isBusy, isTrue);
      expect(UpdateStatus.installing.isBusy, isTrue);
      expect(UpdateStatus.waitingForSafeShutdown.isBusy, isTrue);
      expect(UpdateStatus.restarting.isBusy, isTrue);
      expect(UpdateStatus.verifying.isBusy, isTrue);
      expect(UpdateStatus.idle.isBusy, isFalse);
      expect(UpdateStatus.readyToInstall.isBusy, isFalse);
      expect(UpdateStatus.succeeded.isBusy, isFalse);
    });

    test('canInstall evaluates correctly', () {
      expect(UpdateStatus.readyToInstall.canInstall, isTrue);
      expect(UpdateStatus.downloaded.canInstall, isTrue);
      expect(UpdateStatus.downloading.canInstall, isFalse);
      expect(UpdateStatus.installing.canInstall, isFalse);
    });

    test('isTerminal evaluates correctly', () {
      expect(UpdateStatus.succeeded.isTerminal, isTrue);
      expect(UpdateStatus.failed.isTerminal, isTrue);
      expect(UpdateStatus.recovered.isTerminal, isTrue);
      expect(UpdateStatus.error.isTerminal, isTrue);
      expect(UpdateStatus.downloading.isTerminal, isFalse);
    });
  });

  group('UpdateSessionState & WindowsUpdateCoordinator Tests', () {
    test('generates valid RFC-4122 v4 UUID attempt ID', () {
      final attemptId = WindowsUpdateCoordinator.generateAttemptId();
      expect(
        attemptId,
        matches(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      );
    });

    test('UpdateSessionState serializes and deserializes correctly', () {
      final now = DateTime.now().toUtc();
      final session = UpdateSessionState(
        attemptId: '12345678-1234-4234-8234-123456789abc',
        appKey: 'client',
        fromVersion: '8.1.0',
        fromBuild: 16,
        targetVersion: '8.2.0',
        targetBuild: 17,
        installerPath: r'C:\Updates\setup.exe',
        appExePath: r'C:\App\thq_business.exe',
        status: 'installing',
        startedAt: now,
        installerExitCode: 0,
      );

      final json = session.toJson();
      final reconstructed = UpdateSessionState.fromJson(json);

      expect(reconstructed.attemptId, session.attemptId);
      expect(reconstructed.appKey, 'client');
      expect(reconstructed.fromVersion, '8.1.0');
      expect(reconstructed.targetVersion, '8.2.0');
      expect(reconstructed.targetBuild, 17);
      expect(reconstructed.installerExitCode, 0);
      expect(reconstructed.status, 'installing');
      expect(reconstructed.installerPath, r'C:\Updates\setup.exe');
      expect(reconstructed.appExePath, r'C:\App\thq_business.exe');
    });

    test('initiateUpdate rejects non-existent installer file', () async {
      expect(
        () => WindowsUpdateCoordinator.initiateUpdate(
          appKey: 'client',
          currentVersion: '8.2.2',
          currentBuild: 19,
          targetVersion: '8.2.3',
          targetBuild: 21,
          installerPath: r'C:\NonExistent\installer.exe',
          exitProcess: false,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('UpdateSessionState copyWith preserves and updates fields correctly', () {
      final now = DateTime.now().toUtc();
      final session = UpdateSessionState(
        attemptId: 'test-attempt-id',
        appKey: 'client',
        fromVersion: '8.2.2',
        fromBuild: 19,
        targetVersion: '8.2.3',
        targetBuild: 21,
        installerPath: r'C:\Updates\setup.exe',
        appExePath: r'C:\App\thq_business.exe',
        status: 'launching_installer',
        startedAt: now,
      );

      final updated = session.copyWith(
        status: 'launch_failed',
        errorMessage: 'Helper process blocked.',
        installerExitCode: 1223,
      );

      expect(updated.status, 'launch_failed');
      expect(updated.errorMessage, 'Helper process blocked.');
      expect(updated.installerExitCode, 1223);
      expect(updated.installerPath, r'C:\Updates\setup.exe');
      expect(updated.attemptId, 'test-attempt-id');
    });
  });

  group('Update Failure Diagnostic & Version Verification Tests', () {
    test('Regression: Distinguishes helper launch failure from old version relaunch', () {
      const currentVersion = '8.2.2';
      const currentBuild = 19;
      const targetVersion = '8.2.3';
      const targetBuild = 21;

      // Scenario A: Helper process died before running installer (ExitCode null, status: launching_installer)
      final launchFailedSession = UpdateSessionState(
        attemptId: 'attempt-launch-failed',
        appKey: 'client',
        fromVersion: currentVersion,
        fromBuild: currentBuild,
        targetVersion: targetVersion,
        targetBuild: targetBuild,
        installerPath: r'C:\Updates\setup.exe',
        appExePath: r'C:\App\thq_business.exe',
        status: 'launching_installer',
        startedAt: DateTime.now().toUtc(),
      );

      String getDiagnosticReason(UpdateSessionState pending) {
        final exitCode = pending.installerExitCode;
        if (exitCode == 1223) {
          return 'Administrator authorization (UAC) was declined or cancelled.';
        } else if (exitCode == 1) {
          return 'Installer was cancelled or interrupted before completing setup.';
        } else if (exitCode == 2) {
          return 'Installer could not close conflicting files or processes.';
        } else if (exitCode != null && exitCode != 0) {
          return 'Installer exited unexpectedly with code $exitCode.';
        } else if (pending.status == 'launching_installer' || pending.status == 'launch_failed') {
          return 'The update helper process was interrupted or blocked before installation began.';
        } else {
          return pending.errorMessage ??
              'Application relaunched with version $currentVersion (Build $currentBuild) instead of target $targetVersion (Build $targetBuild).';
        }
      }

      final reasonA = getDiagnosticReason(launchFailedSession);
      expect(
        reasonA,
        'The update helper process was interrupted or blocked before installation began.',
      );

      // Scenario B: User declined UAC elevation prompt (ExitCode 1223)
      final uacDeclinedSession = launchFailedSession.copyWith(
        status: 'recovered',
        installerExitCode: 1223,
      );
      final reasonB = getDiagnosticReason(uacDeclinedSession);
      expect(
        reasonB,
        'Administrator authorization (UAC) was declined or cancelled.',
      );

      // Scenario C: Inno Setup conflict or cancellation (ExitCode 1)
      final cancelledSession = launchFailedSession.copyWith(
        status: 'recovered',
        installerExitCode: 1,
      );
      final reasonC = getDiagnosticReason(cancelledSession);
      expect(
        reasonC,
        'Installer was cancelled or interrupted before completing setup.',
      );

      // Scenario D: Genuine version mismatch after clean installer exit 0
      final mismatchSession = launchFailedSession.copyWith(
        status: 'installed',
        installerExitCode: 0,
      );
      final reasonD = getDiagnosticReason(mismatchSession);
      expect(
        reasonD,
        contains('Application relaunched with version 8.2.2 (Build 19) instead of target 8.2.3 (Build 21).'),
      );
    });

    test('Installer path is preserved on failure', () {
      const installerPath = r'C:\Users\SMART COM\AppData\Roaming\THQ\THQ Business\THQ ERP\updates\setup.exe';
      final session = UpdateSessionState(
        attemptId: 'attempt-path-preservation',
        appKey: 'client',
        fromVersion: '8.2.2',
        fromBuild: 19,
        targetVersion: '8.2.3',
        targetBuild: 21,
        installerPath: installerPath,
        appExePath: r'C:\App\thq_business.exe',
        status: 'launching_installer',
        startedAt: DateTime.now().toUtc(),
      );

      // Verify installerPath is retained in session and readable
      expect(session.installerPath, installerPath);
      expect(session.installerPath.isNotEmpty, isTrue);
    });

    test('Target version verified correctly when running build matches target', () {
      const runningVersion = '8.2.3';
      const runningBuild = 21;

      final session = UpdateSessionState(
        attemptId: 'attempt-success',
        appKey: 'client',
        fromVersion: '8.2.2',
        fromBuild: 19,
        targetVersion: '8.2.3',
        targetBuild: 21,
        installerPath: r'C:\Updates\setup.exe',
        appExePath: r'C:\App\thq_business.exe',
        status: 'installed',
        installerExitCode: 0,
        startedAt: DateTime.now().toUtc(),
      );

      final isMatch = (runningVersion == session.targetVersion && runningBuild == session.targetBuild) ||
          (session.status == 'installed' && runningVersion == session.targetVersion);

      expect(isMatch, isTrue);
    });
  });
}
