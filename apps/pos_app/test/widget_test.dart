import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('THQ v5.1 release/API contract is available to POS', () {
    expect(ThqReleaseContract.appVersion, '5.1.0');
    expect(ThqReleaseContract.minimumMigration, 213);
    expect(ThqReleaseContract.apiVersion, 'v1');
    expect(ThqApiContract.version, 'v1');
  });
}
