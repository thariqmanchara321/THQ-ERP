import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serial identities keep case but reject duplicate identities', () {
    expect(parseTrackingSerials('Aa\nBb', 2), ['Aa', 'Bb']);
    expect(() => parseTrackingSerials('Aa\naa', 2), throwsFormatException);
    expect(() => parseTrackingSerials('Aa', 0.5), throwsFormatException);
  });
  test('batch allocations preserve decimal totals and expiry dates', () {
    expect(parseTrackingBatches('A=0.3|2027-01-31\nB=0.7', 1), [
      {'batch_number': 'A', 'quantity': 0.3, 'expiry_on': '2027-01-31'},
      {'batch_number': 'B', 'quantity': 0.7},
    ]);
    expect(() => parseTrackingBatches('A=1', 2), throwsFormatException);
    expect(() => parseTrackingBatches('A=1\na=1', 2), throwsFormatException);
    expect(() => parseTrackingBatches('A=1|2027-02-30', 1), throwsFormatException);
    expect(() => parseTrackingBatches('A=NaN', 1), throwsFormatException);
    expect(parseTrackingBatches('', 0), isEmpty);
  });
}
