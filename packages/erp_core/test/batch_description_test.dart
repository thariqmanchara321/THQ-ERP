import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invoice describes each captured quality quantity and rate', () {
    expect(
      documentBatchDescription([
        {
          'batch_number': 'LOT-A',
          'quality_label': 'Fine',
          'quantity': 10,
          'base_unit_code': 'CFT',
          'rate': 20,
        },
        {
          'batch_number': 'LOT-B',
          'quality_label': 'Coarse',
          'quantity': 30,
          'base_unit_code': 'CFT',
          'rate': 30,
        },
      ]),
      'LOT-A / Fine • 10 CFT @ 20\nLOT-B / Coarse • 30 CFT @ 30',
    );
  });
  test(
    'old allocations without quality retain their number and captured rate',
    () {
      expect(
        documentBatchDescription([
          {
            'batch_number': 'OLD',
            'quantity': '0.125',
            'base_unit_code': 'CFT',
            'rate': '17.5000',
          },
        ]),
        'OLD • 0.125 CFT @ 17.5',
      );
      expect(documentBatchDescription([]), '');
    },
  );
}
