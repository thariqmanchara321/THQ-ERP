import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('THQ current release/API contract is available to POS', () {
    expect(ThqReleaseContract.appVersion, '7.0.1');
    expect(ThqReleaseContract.buildNumber, 15);
    expect(
      ThqReleaseContract.releaseName,
      'Classic / V7 Switchable UI',
    );
    expect(ThqReleaseContract.minimumMigration, 213);
    expect(ThqReleaseContract.apiVersion, 'v1');
    expect(ThqApiContract.version, 'v1');
  });
}
