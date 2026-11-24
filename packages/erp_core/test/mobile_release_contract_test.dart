import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Build 19 mobile release contracts are aligned', () {
    expect(ThqClientMobileReleaseContract.appVersion, '8.2.2');
    expect(ThqClientMobileReleaseContract.buildNumber, 19);
    expect(ThqClientMobileReleaseContract.platform, 'android');
    expect(ThqPosMobileReleaseContract.appVersion, '8.2.2');
    expect(ThqPosMobileReleaseContract.buildNumber, 19);
    expect(ThqPosMobileReleaseContract.platform, 'android');
  });

  test('legacy shared mobile foundation stays pinned', () {
    expect(ThqMobileReleaseContract.appVersion, '6.2.0');
    expect(ThqMobileReleaseContract.buildNumber, 5);
  });
}
