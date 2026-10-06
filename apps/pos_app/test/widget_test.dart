import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('THQ current release/API contract is available to POS', () {
    expect(ThqReleaseContract.appVersion, '7.0.0');
    expect(ThqReleaseContract.buildNumber, 14);
    expect(
      ThqReleaseContract.releaseName,
      'Futuristic UI & Compact Workspaces',
    );
    expect(ThqReleaseContract.minimumMigration, 213);
    expect(ThqReleaseContract.apiVersion, 'v1');
    expect(ThqApiContract.version, 'v1');
  });
}
