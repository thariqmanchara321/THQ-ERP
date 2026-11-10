import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('THQ current release/API contract is available to Client', () {
    expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(ThqReleaseContract.appVersion), isTrue);
    expect(ThqReleaseContract.buildNumber, greaterThanOrEqualTo(16));
    expect(ThqReleaseContract.releaseName, isNotEmpty);
    expect(ThqReleaseContract.minimumMigration, 213);
    expect(ThqReleaseContract.apiVersion, 'v1');
    expect(ThqApiContract.adapter, 'supabase');
  });
}
