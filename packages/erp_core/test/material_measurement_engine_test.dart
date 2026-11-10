import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MaterialMeasurementEngine Unit & Calculation Tests', () {
    test('calculateFromInches: 120in x 72in x 48in = 240.0 CFT', () {
      final cft = MaterialMeasurementEngine.calculateFromInches(
        lengthIn: 120.0,
        widthIn: 72.0,
        heightIn: 48.0,
      );
      // (120 * 72 * 48) / 1728 = 414720 / 1728 = 240.0
      expect(cft, closeTo(240.0, 0.0001));
    });

    test('calculateFromFeet: 10ft x 6ft x 4ft = 240.0 CFT', () {
      final cft = MaterialMeasurementEngine.calculateFromFeet(
        lengthFt: 10.0,
        widthFt: 6.0,
        heightFt: 4.0,
      );
      expect(cft, closeTo(240.0, 0.0001));
    });

    test(
      'calculateFromFeetAndInches: 10ft 0in x 6ft 0in x 4ft 0in = 240.0 CFT',
      () {
        final cft = MaterialMeasurementEngine.calculateFromFeetAndInches(
          lengthFt: 10.0,
          lengthIn: 0.0,
          widthFt: 6.0,
          widthIn: 0.0,
          heightFt: 4.0,
          heightIn: 0.0,
        );
        expect(cft, closeTo(240.0, 0.0001));
      },
    );

    test('calculateFromMetres: 2m x 1.5m x 1m = 105.944 CFT', () {
      final cft = MaterialMeasurementEngine.calculateFromMetres(
        lengthM: 2.0,
        widthM: 1.5,
        heightM: 1.0,
      );
      // 3.0 m3 * 35.31466672 = 105.944
      expect(cft, closeTo(105.944, 0.01));
    });

    test('Heap adjustment adds and subtracts CFT accurately', () {
      final resPlus = MaterialMeasurementEngine.process(
        method: MaterialMeasurementMethod.dimensions,
        unit: DimensionUnit.feet,
        length: 10,
        width: 6,
        height: 4,
        heapAdjustmentCft: 15.0,
      );
      expect(resPlus.geometricCft, closeTo(240.0, 0.0001));
      expect(resPlus.physicalStockQuantity, closeTo(255.0, 0.0001));

      final resMinus = MaterialMeasurementEngine.process(
        method: MaterialMeasurementMethod.dimensions,
        unit: DimensionUnit.feet,
        length: 10,
        width: 6,
        height: 4,
        heapAdjustmentCft: -20.0,
      );
      expect(resMinus.geometricCft, closeTo(240.0, 0.0001));
      expect(resMinus.physicalStockQuantity, closeTo(220.0, 0.0001));
    });

    test(
      'validateTruckCapacity returns warning when exceeding nominal capacity without override',
      () {
        final warning = MaterialMeasurementEngine.validateTruckCapacity(
          loadQtyCft: 250.0,
          nominalCapacityCft: 200.0,
          allowOverride: false,
        );
        expect(warning, isNotNull);
        expect(warning, contains('exceeds truck capacity'));

        final validWithOverride =
            MaterialMeasurementEngine.validateTruckCapacity(
              loadQtyCft: 250.0,
              nominalCapacityCft: 200.0,
              allowOverride: true,
              overrideReason: 'Approved by Site Supervisor',
            );
        expect(validWithOverride, isNull);
      },
    );

    test('Formatters output consistent CFT and units', () {
      expect(MaterialMeasurementEngine.formatCft(150.0), '150.00 CFT');
      expect(
        MaterialMeasurementEngine.formatQuantity(25.5, 'TON'),
        '25.50 TON',
      );
    });
  });
}
