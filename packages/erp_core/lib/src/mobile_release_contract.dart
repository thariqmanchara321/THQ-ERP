/// Mobile-only release contract for THQ Client Mobile and THQ Mobile POS.
///
/// This deliberately does not change [ThqReleaseContract], which remains the
/// shared desktop/backend release contract. Mobile releases can therefore move
/// independently without making Client/POS desktop builds report the wrong
/// version.
abstract final class ThqMobileReleaseContract {
  static const String appVersion = '6.2.0';
  static const int buildNumber = 5;
  static const String releaseName = 'Mobile Experience Foundation';
  static const String platform = 'android';

  static const String versionLabel = 'v$appVersion • Build $buildNumber';
}

class ThqMobileReleaseStatus {
  final String status;
  final String latestVersion;
  final bool mandatory;
  final String releaseNotes;
  final String? downloadUrl;
  final Map<String, dynamic> backend;

  const ThqMobileReleaseStatus({
    required this.status,
    required this.latestVersion,
    required this.mandatory,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.backend,
  });

  const ThqMobileReleaseStatus.unknown()
      : status = 'unknown',
        latestVersion = '',
        mandatory = false,
        releaseNotes = '',
        downloadUrl = null,
        backend = const <String, dynamic>{};

  factory ThqMobileReleaseStatus.fromMap(Map<String, dynamic> map) {
    final backendRaw = map['backend'];
    return ThqMobileReleaseStatus(
      status: map['status']?.toString().trim().toLowerCase() ?? 'unknown',
      latestVersion: map['latest_version']?.toString().trim() ?? '',
      mandatory: map['mandatory'] == true,
      releaseNotes: map['release_notes']?.toString().trim() ?? '',
      downloadUrl: _cleanNullable(map['download_url']),
      backend: backendRaw is Map
          ? Map<String, dynamic>.from(backendRaw)
          : const <String, dynamic>{},
    );
  }

  bool get isLatest => status == 'latest';
  bool get updateRequired => mandatory || status == 'update_required';
  bool get updateAvailable =>
      updateRequired || status == 'update_available';

  static String? _cleanNullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
