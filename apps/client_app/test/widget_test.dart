import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('THQ current release/API contract is available to Client', () {
    expect(ThqReleaseContract.appVersion, '6.0.0');
    expect(ThqReleaseContract.buildNumber, 1);
    expect(ThqReleaseContract.releaseName, 'Audit Intelligence & Explainability');
    expect(ThqReleaseContract.minimumMigration, 213);
    expect(ThqReleaseContract.apiVersion, 'v1');
    expect(ThqApiContract.adapter, 'supabase');
  });
}
