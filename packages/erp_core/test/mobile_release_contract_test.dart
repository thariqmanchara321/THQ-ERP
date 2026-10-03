import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Build 13 mobile release contracts are aligned', () {
    expect(ThqClientMobileReleaseContract.appVersion, '6.2.8');
    expect(ThqClientMobileReleaseContract.buildNumber, 13);
    expect(ThqClientMobileReleaseContract.platform, 'android');
    expect(ThqPosMobileReleaseContract.appVersion, '6.2.8');
    expect(ThqPosMobileReleaseContract.buildNumber, 13);
    expect(ThqPosMobileReleaseContract.platform, 'android');
  });

  test('legacy shared mobile foundation stays pinned', () {
    expect(ThqMobileReleaseContract.appVersion, '6.2.0');
    expect(ThqMobileReleaseContract.buildNumber, 5);
  });
}
