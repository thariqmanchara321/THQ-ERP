import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('THQ current release/API contract is available to POS', () {
    expect(ThqReleaseContract.appVersion, '6.1.5');
    expect(ThqReleaseContract.buildNumber, 8);
    expect(ThqReleaseContract.releaseName, 'Customer Receivable Sale Fix');
    expect(ThqReleaseContract.minimumMigration, 213);
    expect(ThqReleaseContract.apiVersion, 'v1');
    expect(ThqApiContract.version, 'v1');
  });
}
