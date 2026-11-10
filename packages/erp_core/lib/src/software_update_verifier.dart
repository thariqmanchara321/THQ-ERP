import 'dart:convert';
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
      throw FileSystemException(
        'File not found for checksum calculation',
        filePath,
      );
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  /// Validates that a download URL uses trusted HTTPS and safe target format
  static bool validateDownloadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    // Allow https, or http only for localhost/127.0.0.1 in local tests
    final isSecure =
        uri.scheme == 'https' ||
        (uri.scheme == 'http' &&
            (uri.host == 'localhost' || uri.host == '127.0.0.1'));
    if (!isSecure) return false;

    // Ensure path ends with executable or package extension
    final path = uri.path.toLowerCase();
    if (Platform.isWindows &&
        !path.endsWith('.exe') &&
        !path.endsWith('.zip')) {
      return false;
    }

    return true;
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
  /// Returns a record with validity and details.
  static Future<AuthenticodeResult> verifyPublisherSignature(
    String filePath, {
    String? expectedSignature,
    bool requireValidSignature = false,
  }) async {
    if (!Platform.isWindows) {
      return const AuthenticodeResult(
        isValid: true,
        status: 'NonWindowsPlatform',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return const AuthenticodeResult(isValid: false, status: 'FileNotFound');
    }

    try {
      // Escape single quotes for PowerShell
      final escaped = filePath.replaceAll("'", "''");
      final psScript =
          r'''
$sig = Get-AuthenticodeSignature -LiteralPath 'PATH_PLACEHOLDER'
[PSCustomObject]@{
    Status = $sig.Status.ToString()
    StatusMessage = $sig.StatusMessage
    Thumbprint = $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { '' })
    Subject = $(if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '' })
} | ConvertTo-Json -Compress
'''
              .replaceAll('PATH_PLACEHOLDER', escaped);

      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        psScript,
      ]);

      if (result.exitCode == 0) {
        final out = result.stdout.toString().trim();
        if (out.isNotEmpty && out.startsWith('{')) {
          final data = jsonDecode(out) as Map<String, dynamic>;
          final status = data['Status']?.toString() ?? 'Unknown';
          final thumbprint = data['Thumbprint']?.toString() ?? '';
          final subject = data['Subject']?.toString() ?? '';

          final isValid = status.equalsIgnoreCase('Valid');

          if (!isValid && requireValidSignature) {
            return AuthenticodeResult(
              isValid: false,
              status: status,
              thumbprint: thumbprint,
              subject: subject,
              errorMessage: 'Authenticode status is $status (expected Valid)',
            );
          }

          // If expected signature/thumbprint or subject is specified, verify match
          if (expectedSignature != null &&
              expectedSignature.trim().isNotEmpty) {
            final expected = expectedSignature.trim().toLowerCase();
            final matchesThumbprint = thumbprint.toLowerCase() == expected;
            final matchesSubject = subject.toLowerCase().contains(expected);

            if (!matchesThumbprint && !matchesSubject) {
              return AuthenticodeResult(
                isValid: false,
                status: status,
                thumbprint: thumbprint,
                subject: subject,
                errorMessage:
                    'Signer certificate ($subject, thumbprint: $thumbprint) does not match expected ($expectedSignature)',
              );
            }
          }

          return AuthenticodeResult(
            isValid: isValid,
            status: status,
            thumbprint: thumbprint,
            subject: subject,
          );
        }
      }
    } catch (e) {
      return AuthenticodeResult(
        isValid: false,
        status: 'CheckError',
        errorMessage: e.toString(),
      );
    }

    if (requireValidSignature) {
      return const AuthenticodeResult(
        isValid: false,
        status: 'UnsignedOrVerificationFailed',
      );
    }

    return const AuthenticodeResult(isValid: true, status: 'UnsignedAllowed');
  }
}

class AuthenticodeResult {
  final bool isValid;
  final String status;
  final String? thumbprint;
  final String? subject;
  final String? errorMessage;

  const AuthenticodeResult({
    required this.isValid,
    required this.status,
    this.thumbprint,
    this.subject,
    this.errorMessage,
  });

  @override
  String toString() =>
      'AuthenticodeResult(isValid: $isValid, status: $status, subject: $subject, thumbprint: $thumbprint)';
}

extension _StringCompare on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}
