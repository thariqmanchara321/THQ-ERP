/// Shared release contract for THQ ERP v6.1.5 applications.
///
/// The global THQ backend compatibility API intentionally remains v1 /
/// migration 213. GST-bearing writes are gated separately by the authoritative
/// GST cutover contract and continue to fail closed when compliance is not ready.
abstract final class ThqReleaseContract {
  static const String appVersion = '6.1.5';
  static const int buildNumber = 8;
  static const int minimumMigration = 213;
  static const String releaseName = 'Customer Receivable Sale Fix';
  static const String apiVersion = 'v1';
}
