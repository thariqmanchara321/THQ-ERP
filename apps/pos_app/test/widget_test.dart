import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('THQ V4.8 release/API contract is available to POS', () {
    expect(ThqReleaseContract.appVersion, '4.8.2');
    expect(ThqReleaseContract.minimumMigration, 134);
    expect(ThqReleaseContract.apiVersion, 'v1');
    expect(ThqApiContract.version, 'v1');
  });
}
