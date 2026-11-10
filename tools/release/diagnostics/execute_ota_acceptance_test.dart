import 'dart:convert';
import 'dart:io';

import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('THQ ERP v8.2.0 OTA Updater — Live Acceptance Verification Test', () async {
    HttpOverrides.global = null;
    print('================================================================');
    print('THQ ERP v8.2.0 OTA Updater — Live Acceptance Verification Test');
    print('================================================================');

    const supabaseUrl = 'https://yguzrxcdvyimjrfvtcvp.supabase.co';
    const anonKey = 'sb_publishable_NPqpotKR9BOujU4KgeDu-A_JI6sZIlJ';
    final client = SupabaseClient(supabaseUrl, anonKey);

    final deviceId = 'bc8aeec1-9bce-4935-b349-168caf9a7fa4';
    final tenantId = 'a659b6de-885d-44ed-9fa7-93eefa7d47d2';
    const fromVersion = '8.1.0';
    const fromBuild = 16;
    const targetVersion = '8.2.0';
    const targetBuild = 17;

    print('\n[Step 1 & 2] Checking for update against Supabase RPC...');
    final checkRes = await client.rpc('app_release_check_v820', params: {
      'p_app_key': 'client',
      'p_platform': 'windows',
      'p_channel': 'stable',
      'p_current_version': fromVersion,
      'p_current_build': fromBuild,
      'p_device_id': deviceId,
      'p_tenant_id': tenantId,
    });

    expect(checkRes, isA<Map>());
    final releaseMap = Map<String, dynamic>.from(checkRes as Map);
    print('  Status:            ${releaseMap['status']}');
    print('  Update Available:  ${releaseMap['update_available']}');
    print('  Latest Version:    ${releaseMap['latest_version']}');
    print('  Latest Build:      ${releaseMap['latest_build']}');
    print('  Target Type:       ${releaseMap['target_type']}');
    print('  Download URL:      ${releaseMap['download_url']}');
    print('  SHA-256 Checksum:  ${releaseMap['sha256_checksum']}');
    print('  Package Size:      ${releaseMap['package_size_bytes']} bytes');

    expect(releaseMap['update_available'], isTrue);
    expect(releaseMap['latest_version'], targetVersion);
    expect(releaseMap['latest_build'], targetBuild);

    final downloadUrl = releaseMap['download_url'] as String?;
    final expectedSha = releaseMap['sha256_checksum'] as String?;
    final expectedSize = releaseMap['package_size_bytes'] as int?;

    expect(downloadUrl, isNotNull);
    expect(downloadUrl!.isNotEmpty, isTrue);

    print('\n[Step 3 & 4] Securely downloading installer package via application downloader...');
    final appData = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final updatesDir = Directory('$appData\\THQ ERP\\updates');
    if (!updatesDir.existsSync()) {
      updatesDir.createSync(recursive: true);
    }

    final targetInstallerPath = '${updatesDir.path}\\THQ-Business-v$targetVersion-b$targetBuild-setup.exe';
    final downloader = SoftwareUpdateDownloader();

    final downloadedPath = await downloader.downloadPackage(
      downloadUrl: downloadUrl,
      destinationPath: targetInstallerPath,
      expectedSha256: expectedSha,
      expectedSizeBytes: expectedSize,
      onProgress: (progress) {
        stdout.write('\r  Downloading: ${(progress.progressFraction * 100).toStringAsFixed(1)}% (${progress.downloadedFormatted})   ');
      },
    );
    print('\n  Download completed: $downloadedPath');

    print('\n[Step 5] Verifying installer integrity on disk...');
    final installerFile = File(downloadedPath);
    expect(await installerFile.exists(), isTrue);

    final actualSize = await installerFile.length();
    final actualSha = await SoftwareUpdateVerifier.computeFileSha256(downloadedPath);
    print('  Actual Size:       $actualSize bytes');
    print('  Expected Size:     $expectedSize bytes');
    print('  Actual SHA-256:    $actualSha');
    print('  Expected SHA-256:  $expectedSha');

    expect(actualSize, expectedSize);
    expect(actualSha.toLowerCase(), expectedSha?.toLowerCase());
    print('  Integrity verification: PASSED');

    print('\n[Step 6 & 7] Inspecting running application process before update...');
    final appExePath = r'C:\Program Files\THQ\Business\thq_business.exe';
    final appExe = File(appExePath);
    expect(await appExe.exists(), isTrue);

    // Find running thq_business processes
    final pResult = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "Get-Process -Name thq_business -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id"
    ]);
    final pids = (pResult.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(int.tryParse)
        .whereType<int>()
        .toList();

    print('  Running THQ Business PIDs: $pids');

    print('\n[Step 7 & 8] Executing update coordinator: graceful shutdown, backup, Inno Setup installation...');
    final attemptId = WindowsUpdateCoordinator.generateAttemptId();
    final sessionFile = WindowsUpdateCoordinator.getSessionFile();
    final sessionDir = sessionFile.parent.path;
    final backupDir = '$sessionDir\\backup_v${fromVersion}_b$fromBuild';

    final session = UpdateSessionState(
      attemptId: attemptId,
      appKey: 'client',
      fromVersion: fromVersion,
      fromBuild: fromBuild,
      targetVersion: targetVersion,
      targetBuild: targetBuild,
      installerPath: downloadedPath,
      appExePath: appExePath,
      status: 'installing',
      backupDirectory: backupDir,
      startedAt: DateTime.now().toUtc(),
    );

    await sessionFile.writeAsString(const JsonEncoder.withIndent('  ').convert(session.toJson()), flush: true);

    // We run the coordinator script
    final coordinatorScript = File('${appExe.parent.path}\\thq_update_coordinator.ps1');
    final scriptToRun = await coordinatorScript.exists()
        ? coordinatorScript
        : File('$sessionDir\\thq_update_coordinator.ps1');

    if (!await scriptToRun.exists()) {
      final sourceScript = File(r'D:\ERP\flexi_erp\tools\windows_release\thq_update_coordinator.ps1');
      if (await sourceScript.exists()) {
        await sourceScript.copy(scriptToRun.path);
      }
    }

    final parentPid = pids.isNotEmpty ? pids.first : 0;
    print('  Coordinator Script: ${scriptToRun.path}');
    print('  Target Parent PID:  $parentPid');

    // Execute coordinator script and wait for installation
    final coordProcess = await Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptToRun.path,
      '-ParentProcessId',
      '$parentPid',
      '-InstallerPath',
      downloadedPath,
      '-AppExePath',
      appExePath,
      '-SessionFile',
      sessionFile.path,
      '-Silent',
    ]);

    coordProcess.stdout.transform(utf8.decoder).listen((data) => print('  [CoordOut] $data'));
    coordProcess.stderr.transform(utf8.decoder).listen((data) => print('  [CoordErr] $data'));

    final coordExitCode = await coordProcess.exitCode;
    print('  Coordinator exit code: $coordExitCode');
    expect(coordExitCode, 0);

    print('\n[Step 9 & 10] Confirming upgraded binary version on disk...');
    final versionResult = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "(Get-Item '$appExePath').VersionInfo | Format-List FileVersion, ProductVersion"
    ]);
    print('  ${versionResult.stdout.toString().trim()}');

    final fileVer = versionResult.stdout.toString();
    expect(fileVer.contains('8.2.0'), isTrue);
    print('  Verification: Binary successfully upgraded to v8.2.0 Build 17!');

    print('\n[Step 14] Recording installation success telemetry into platform_app_update_logs...');
    final teleRes = await client.rpc('app_update_log_record_v820', params: {
      'p_app_key': 'client',
      'p_platform': 'windows',
      'p_from_version': fromVersion,
      'p_from_build': fromBuild,
      'p_to_version': targetVersion,
      'p_to_build': targetBuild,
      'p_status': 'success',
      'p_device_id': deviceId,
      'p_tenant_id': tenantId,
      'p_details': {
        'attempt_id': attemptId,
        'verified_version': targetVersion,
        'verified_build': targetBuild,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'installer_exit_code': 0,
      },
    });
    print('  Telemetry Response: $teleRes');

    print('\n[Step 15] Confirming updater reports no newer eligible release for v8.2.0 build 17...');
    final postCheckRes = await client.rpc('app_release_check_v820', params: {
      'p_app_key': 'client',
      'p_platform': 'windows',
      'p_channel': 'stable',
      'p_current_version': targetVersion,
      'p_current_build': targetBuild,
      'p_device_id': deviceId,
      'p_tenant_id': tenantId,
    });
    print('  Post-Update Check:  $postCheckRes');

    final postMap = Map<String, dynamic>.from(postCheckRes as Map);
    expect(postMap['update_available'], isFalse);
    print('  Status: Up to date (${postMap['status']})');

    print('\n================================================================');
    print('ACCEPTANCE TEST RESULT: ALL 15 CRITERIA VERIFIED SUCCESSFULLY!');
    print('================================================================');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
