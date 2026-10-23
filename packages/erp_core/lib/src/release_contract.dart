/// Shared release contract for THQ ERP v8.1 applications.
///
/// The global THQ backend compatibility API intentionally remains v1 /
/// migration 213. GST-bearing writes are gated separately by the authoritative
/// GST cutover contract and continue to fail closed when compliance is not ready.
abstract final class ThqReleaseContract {
  static const String appVersion = '8.2.2';
  static const int buildNumber = 19;
  static const int minimumMigration = 213;
  static const String releaseName = 'THQ ERP v8.2.2 System Health Release';
  static const String apiVersion = 'v1';
}
