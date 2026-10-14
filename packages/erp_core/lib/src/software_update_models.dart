/// Software update models and states for THQ ERP applications.
library;

enum UpdateStatus {
  idle,
  checking,
  available,
  downloading,
  verifying,
  readyToInstall,
  installing,
  error,
  upToDate,
}

class AppReleaseInfo {
  final String appKey;
  final String platform;
  final String channel;
  final String latestVersion;
  final int latestBuild;
  final String currentVersion;
  final int currentBuild;
  final bool isUpdateAvailable;
  final bool isMandatory;
  final String status;
  final String? downloadUrl;
  final int packageSizeBytes;
  final String? sha256Checksum;
  final String? publisherSignature;
  final String releaseNotes;
  final String? minSupportedVersion;
  final DateTime? releasedAt;

  const AppReleaseInfo({
    required this.appKey,
    required this.platform,
    required this.channel,
    required this.latestVersion,
    required this.latestBuild,
    required this.currentVersion,
    required this.currentBuild,
    required this.isUpdateAvailable,
    required this.isMandatory,
    required this.status,
    required this.downloadUrl,
    required this.packageSizeBytes,
    required this.sha256Checksum,
    required this.publisherSignature,
    required this.releaseNotes,
    required this.minSupportedVersion,
    required this.releasedAt,
  });

  String get formattedSize {
    if (packageSizeBytes <= 0) return 'Unknown size';
    if (packageSizeBytes < 1024 * 1024) {
      final kb = (packageSizeBytes / 1024).toStringAsFixed(1);
      return '$kb KB';
    }
    final mb = (packageSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    return '$mb MB';
  }

  factory AppReleaseInfo.fromMap(Map<String, dynamic> map) {
    DateTime? relDate;
    if (map['released_at'] != null) {
      relDate = DateTime.tryParse(map['released_at'].toString());
    }

    return AppReleaseInfo(
      appKey: map['app_key']?.toString() ?? 'client',
      platform: map['platform']?.toString() ?? 'windows',
      channel: map['channel']?.toString() ?? 'stable',
      latestVersion: map['latest_version']?.toString() ?? '',
      latestBuild: (map['latest_build'] as num?)?.toInt() ?? 0,
      currentVersion: map['current_version']?.toString() ?? '',
      currentBuild: (map['current_build'] as num?)?.toInt() ?? 0,
      isUpdateAvailable: map['update_available'] == true,
      isMandatory: map['is_mandatory'] == true,
      status: map['status']?.toString() ?? 'latest',
      downloadUrl: map['download_url']?.toString(),
      packageSizeBytes: (map['package_size_bytes'] as num?)?.toInt() ?? 0,
      sha256Checksum: map['sha256_checksum']?.toString(),
      publisherSignature: map['publisher_signature']?.toString(),
      releaseNotes: map['release_notes']?.toString() ?? '',
      minSupportedVersion: map['min_supported_version']?.toString(),
      releasedAt: relDate,
    );
  }
}

class UpdateDownloadProgress {
  final int receivedBytes;
  final int totalBytes;
  final double progressFraction;
  final String statusText;

  const UpdateDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.progressFraction,
    required this.statusText,
  });

  String get percentageText {
    final pct = (progressFraction * 100).clamp(0, 100).toInt();
    return '$pct%';
  }

  String get downloadedFormatted {
    final mbRec = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
    if (totalBytes > 0) {
      final mbTot = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
      return '$mbRec MB / $mbTot MB';
    }
    return '$mbRec MB';
  }
}

/// Robust semantic version comparator
int compareSemver(String v1, String v2) {
  final clean1 = v1.replaceAll(RegExp(r'[^0-9.]'), '');
  final clean2 = v2.replaceAll(RegExp(r'[^0-9.]'), '');
  final p1 = clean1.split('.');
  final p2 = clean2.split('.');
  final len = p1.length > p2.length ? p1.length : p2.length;

  for (var i = 0; i < len; i++) {
    final n1 = i < p1.length ? (int.tryParse(p1[i]) ?? 0) : 0;
    final n2 = i < p2.length ? (int.tryParse(p2[i]) ?? 0) : 0;
    if (n1 > n2) return 1;
    if (n1 < n2) return -1;
  }
  return 0;
}
