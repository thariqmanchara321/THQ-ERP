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
    });
  });
}
