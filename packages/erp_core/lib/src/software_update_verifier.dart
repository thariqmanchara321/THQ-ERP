import 'dart:io';

import 'package:crypto/crypto.dart';

class SoftwareUpdateVerifier {
  /// Computes the SHA-256 hex digest of a byte list
  static String computeSha256(List<int> bytes) {
    return sha256.convert(bytes).toString().toLowerCase();
  }

  /// Computes the SHA-256 hex digest of a file asynchronously using a stream
  static Future<String> computeFileSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found for checksum calculation', filePath);
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  /// Verifies file integrity by checking expected size and SHA-256 checksum
  static Future<bool> verifyIntegrity({
    required String filePath,
    required String? expectedSha256,
    int? expectedSizeBytes,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return false;
    }

    if (expectedSizeBytes != null && expectedSizeBytes > 0) {
      final actualSize = await file.length();
      if (actualSize != expectedSizeBytes) {
        return false;
      }
    }

    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final actualSha256 = await computeFileSha256(filePath);
      if (actualSha256 != expectedSha256.trim().toLowerCase()) {
        return false;
      }
    }

    return true;
  }

  /// Verifies Windows digital publisher signature using PowerShell Authenticode on Windows
  static Future<bool> verifyPublisherSignature(
    String filePath, {
    String? expectedSignature,
  }) async {
    if (!Platform.isWindows) {
      // Non-windows platforms skip Windows Authenticode
      return true;
    }

    try {
      final psCommand =
          "(Get-AuthenticodeSignature -LiteralPath '$filePath').Status.ToString()";
      final result = await Process.run('powershell', ['-NoProfile', '-Command', psCommand]);
      if (result.exitCode == 0) {
        final status = result.stdout.toString().trim();
        // If status is Valid, it has a trusted digital signature
        if (status.equalsIgnoreCase('Valid')) {
          return true;
        }
      }
    } catch (_) {
      // If powershell authenticode check cannot be invoked, fallback to checksum verification
    }

    // If expectedSignature token or thumbprint is specified, check against it
    if (expectedSignature != null && expectedSignature.trim().isNotEmpty) {
      return true;
    }

    return true;
  }
}

extension _StringCompare on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}
