import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'software_update_models.dart';
import 'software_update_verifier.dart';

class SoftwareUpdateDownloader {
  HttpClient? _activeClient;
  bool _isCancelled = false;

  void cancel() {
    _isCancelled = true;
    _activeClient?.close(force: true);
  }

  /// Downloads an update package from [downloadUrl] to [destinationPath] with streaming
  /// SHA-256 calculation and progress reporting.
  Future<String> downloadPackage({
    required String downloadUrl,
    required String destinationPath,
    required String? expectedSha256,
    int? expectedSizeBytes,
    String? expectedPublisherSignature,
    void Function(UpdateDownloadProgress progress)? onProgress,
  }) async {
    _isCancelled = false;
    final destFile = File(destinationPath);
    final tempFile = File('$destinationPath.download');

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.parent.create(recursive: true);

    final client = HttpClient();
    _activeClient = client;

    IOSink? sink;
    try {
      if (!SoftwareUpdateVerifier.validateDownloadUrl(downloadUrl)) {
        throw ArgumentError(
          'Untrusted or invalid download URL scheme/destination: $downloadUrl',
        );
      }

      final uri = Uri.parse(downloadUrl);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'THQ-ERP-Updater/1.0');

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Failed to download update package. HTTP ${response.statusCode}: ${response.reasonPhrase}',
          uri: uri,
        );
      }

      final contentLength = response.contentLength > 0
          ? response.contentLength
          : (expectedSizeBytes ?? -1);

      sink = tempFile.openWrite();
      var receivedBytes = 0;
      final shaAccumulator = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((accumulated) {}),
      );

      final stopwatch = Stopwatch()..start();

      await for (final chunk in response) {
        if (_isCancelled) {
          throw const CancellationException('Download cancelled by user.');
        }

        sink.add(chunk);
        shaAccumulator.add(chunk);
        receivedBytes += chunk.length;

        if (onProgress != null) {
          final fraction = contentLength > 0
              ? (receivedBytes / contentLength).clamp(0.0, 1.0)
              : 0.0;

          final elapsedSec = stopwatch.elapsedMilliseconds / 1000.0;
          final speedBytesPerSec = elapsedSec > 0
              ? (receivedBytes / elapsedSec)
              : 0.0;
          final speedMb = (speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1);

          onProgress(
            UpdateDownloadProgress(
              receivedBytes: receivedBytes,
              totalBytes: contentLength,
              progressFraction: fraction,
              statusText: 'Downloading ($speedMb MB/s)…',
            ),
          );
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (_isCancelled) {
        throw const CancellationException('Download cancelled by user.');
      }

      // 1. Verify size
      final actualSize = await tempFile.length();
      if (expectedSizeBytes != null &&
          expectedSizeBytes > 0 &&
          actualSize != expectedSizeBytes) {
        throw UpdateIntegrityException(
          'Downloaded package size mismatch: expected $expectedSizeBytes bytes, got $actualSize bytes.',
        );
      }

      // 2. Verify SHA-256
      if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
        final actualSha256 = await SoftwareUpdateVerifier.computeFileSha256(
          tempFile.path,
        );
        if (actualSha256.toLowerCase() != expectedSha256.trim().toLowerCase()) {
          throw UpdateIntegrityException(
            'Checksum verification failed. The update package may be corrupted or modified.',
          );
        }
      }

      // 3. Move temp file to final destination
      if (await destFile.exists()) {
        await destFile.delete();
      }
      await tempFile.rename(destinationPath);

      // 4. Verify publisher signature on Windows if configured
      if (Platform.isWindows &&
          expectedPublisherSignature != null &&
          expectedPublisherSignature.trim().isNotEmpty) {
        final authResult =
            await SoftwareUpdateVerifier.verifyPublisherSignature(
              destinationPath,
              expectedSignature: expectedPublisherSignature,
              requireValidSignature: true,
            );
        if (!authResult.isValid) {
          await destFile.delete();
          throw UpdateIntegrityException(
            'Publisher signature verification failed: ${authResult.errorMessage ?? authResult.status}',
          );
        }
      }

      return destinationPath;
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
      _activeClient = null;
    }
  }

  /// Launches the downloaded installer on Windows in a detached process.
  static Future<Process> launchWindowsInstaller({
    required String installerPath,
    bool silent = false,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Installer execution is currently only supported on Windows.',
      );
    }

    final file = File(installerPath);
    if (!await file.exists()) {
      throw FileSystemException(
        'Installer executable does not exist',
        installerPath,
      );
    }

    final args = <String>[];
    if (silent) {
      // Inno Setup flags:
      // /SILENT: Shows progress dialog without wizard pages
      // /SP-: Skips the "Do you wish to continue?" prompt
      // /SUPPRESSMSGBOXES: Suppresses message boxes
      // /CLOSEAPPLICATIONS: Closes running THQ ERP instance safely
      // /RESTARTAPPLICATIONS: Restarts the updated application
      args.addAll([
        '/SILENT',
        '/SP-',
        '/SUPPRESSMSGBOXES',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ]);
    }

    return Process.start(installerPath, args, mode: ProcessStartMode.detached);
  }
}

class UpdateIntegrityException implements Exception {
  final String message;
  const UpdateIntegrityException(this.message);

  @override
  String toString() => message;
}

class CancellationException implements Exception {
  final String message;
  const CancellationException(this.message);

  @override
  String toString() => message;
}
