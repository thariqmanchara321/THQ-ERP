/// Shared release contract for THQ ERP v5.2 applications.
///
/// The global THQ backend compatibility API intentionally remains v1 /
/// migration 213 so the additive v5.2 GST layer does not make unrelated
/// legacy modules refuse to start. GST-bearing writes are gated separately by
/// gst_transaction_cutover_contract_v520 and fail closed when v5.2 is not ready.
abstract final class ThqReleaseContract {
  static const String appVersion = '5.2.2';
  static const int buildNumber = 30;
  static const int minimumMigration = 213;
  static const String releaseName = 'GST & Payments / Multi-Payment';
  static const String apiVersion = 'v1';
}
