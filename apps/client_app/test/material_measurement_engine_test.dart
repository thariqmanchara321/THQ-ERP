import 'package:client_app/models/material_measurement_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MaterialMeasurementEngine - Verified Formulas', () {
    test('Inches: CFT = L × W × H / 1728', () {
      // 120 in × 72 in × 48 in = 414720 cubic inches / 1728 = 240 CFT
      final cft = MaterialMeasurementEngine.calculateFromInches(
        lengthIn: 120,
        widthIn: 72,
        heightIn: 48,
      );
      expect(cft, equals(240.0));

      // Another dimension: 36 in × 24 in × 12 in = 10368 / 1728 = 6 CFT
      final cft2 = MaterialMeasurementEngine.calculateFromInches(
        lengthIn: 36,
        widthIn: 24,
        heightIn: 12,
      );
      expect(cft2, equals(6.0));
    });

    test('Feet: CFT = L × W × H', () {
      final cft = MaterialMeasurementEngine.calculateFromFeet(
        lengthFt: 10,
        widthFt: 6,
        heightFt: 4,
      );
      expect(cft, equals(240.0));

      final cftFractional = MaterialMeasurementEngine.calculateFromFeet(
        lengthFt: 12.5,
        widthFt: 7.2,
        heightFt: 3.0,
      );
      expect(cftFractional, equals(270.0));
    });

    test('Metres: CFT = L × W × H × 35.3146667214886', () {
      // 1 cubic metre = 35.3146667214886 CFT
      final cft1 = MaterialMeasurementEngine.calculateFromMetres(
        lengthM: 1,
        widthM: 1,
        heightM: 1,
      );
      expect(cft1, closeTo(35.3146667214886, 0.0000000001));

      // 3m × 2m × 1.5m = 9 m³ = 317.8320004933974 CFT
      final cft2 = MaterialMeasurementEngine.calculateFromMetres(
        lengthM: 3,
        widthM: 2,
        heightM: 1.5,
      );
      expect(cft2, closeTo(9.0 * 35.3146667214886, 0.0000000001));
    });

    test('Centimetres: CFT = L × W × H / 28316.846592', () {
      // 1,000,000 cm³ (= 1 m³) / 28316.846592 = ~35.3146667215 CFT
      final cft1 = MaterialMeasurementEngine.calculateFromCentimetres(
        lengthCm: 100,
        widthCm: 100,
        heightCm: 100,
      );
      expect(cft1, closeTo(35.3146667214886, 0.0001));
    });

    test('Feet + inches: Convert each dimension to inches before calculating', () {
      // 10ft 0in (= 120in) × 6ft 0in (= 72in) × 4ft 0in (= 48in) = 240 CFT
      final cft1 = MaterialMeasurementEngine.calculateFromFeetAndInches(
        lengthFt: 10,
        lengthIn: 0,
        widthFt: 6,
        widthIn: 0,
        heightFt: 4,
        heightIn: 0,
      );
      expect(cft1, equals(240.0));

      // 10ft 6in (= 126in) × 6ft 0in (= 72in) × 3ft 8in (= 44in)
      // 126 × 72 × 44 = 399168 cubic inches / 1728 = 231 CFT
      final cft2 = MaterialMeasurementEngine.calculateFromFeetAndInches(
        lengthFt: 10,
        lengthIn: 6,
        widthFt: 6,
        widthIn: 0,
        heightFt: 3,
        heightIn: 8,
      );
      expect(cft2, equals(231.0));
    });

    test('Weighbridge: Net = Gross - Tare; Weight must NOT convert without approved density', () {
      final net = MaterialMeasurementEngine.calculateNetWeight(
        grossWeight: 25000,
        tareWeight: 9000,
      );
      expect(net, equals(16000));

      // Without approved density: returns null
      final cftUnapproved = MaterialMeasurementEngine.convertWeightToCft(
        netWeight: 16000,
        bulkDensity: 45.0,
        isDensityApproved: false,
      );
      expect(cftUnapproved, isNull);

      final cftNullDensity = MaterialMeasurementEngine.convertWeightToCft(
        netWeight: 16000,
        bulkDensity: null,
        isDensityApproved: true,
      );
      expect(cftNullDensity, isNull);

      // With approved density (e.g. 50 kg/CFT -> 16000 / 50 = 320 CFT):
      final cftApproved = MaterialMeasurementEngine.convertWeightToCft(
        netWeight: 16000,
        bulkDensity: 50.0,
        isDensityApproved: true,
      );
      expect(cftApproved, equals(320.0));
    });

    test('Heap adjustment and approved billable variance', () {
      // 240 CFT body dimensions + 15 CFT heap = 255 CFT physical stock movement
      final res = MaterialMeasurementEngine.process(
        method: MaterialMeasurementMethod.dimensions,
        unit: DimensionUnit.feetAndInches,
        length: 10,
        lengthInchesPart: 0,
        width: 6,
        widthInchesPart: 0,
        height: 4,
        heightInchesPart: 0,
        heapAdjustmentCft: 15.0,
        heapAdjustmentEvidence: 'Crowned load 6 inches above sideboards',
        approvedBillableQuantity: 250.0, // Operator agreed to bill 250
        overrideReason: 'Settled billable quantity after customer inspection',
        approvedByUserId: 'user-uuid-123',
      );

      expect(res.geometricCft, equals(240.0));
      expect(res.heapAdjustmentCft, equals(15.0));
      expect(res.physicalStockQuantity, equals(255.0));
      expect(res.approvedBillableQuantity, equals(250.0));
      expect(res.variance, equals(-5.0)); // 250 - 255 = -5
      expect(res.overrideReason, equals('Settled billable quantity after customer inspection'));

      final json = res.toRawDimensionsJson();
      expect(json['method'], equals('dimensions'));
      expect(json['unit'], equals('ft_in'));
      expect(json['geometric_cft'], equals(240.0));
      expect(json['physical_stock_qty'], equals(255.0));
      expect(json['approved_billable_qty'], equals(250.0));
      expect(json['variance'], equals(-5.0));
    });

    test('Mandatory test values and precision formatting', () {
      // 12 × 12 × 12 inches = 1 CFT
      final cft1 = MaterialMeasurementEngine.calculateFromInches(lengthIn: 12, widthIn: 12, heightIn: 12);
      expect(cft1, equals(1.0));
      expect(MaterialMeasurementEngine.formatCft(cft1), equals('1.00 CFT'));

      // 120 × 72 × 48 inches = 240 CFT
      final cft2 = MaterialMeasurementEngine.calculateFromInches(lengthIn: 120, widthIn: 72, heightIn: 48);
      expect(cft2, equals(240.0));
      expect(MaterialMeasurementEngine.formatCft(cft2), equals('240.00 CFT'));

      // 10 × 6 × 4 feet = 240 CFT
      final cft3 = MaterialMeasurementEngine.calculateFromFeet(lengthFt: 10, widthFt: 6, heightFt: 4);
      expect(cft3, equals(240.0));
      expect(MaterialMeasurementEngine.formatCft(cft3), equals('240.00 CFT'));

      // 1 × 1 × 1 metre ≈ 35.31467 CFT
      final cft4 = MaterialMeasurementEngine.calculateFromMetres(lengthM: 1, widthM: 1, heightM: 1);
      expect(cft4, closeTo(35.31467, 0.0001));
      expect(MaterialMeasurementEngine.formatCft(cft4), equals('35.31 CFT'));

      // 100 × 100 × 100 centimetres ≈ 35.31467 CFT
      final cft5 = MaterialMeasurementEngine.calculateFromCentimetres(lengthCm: 100, widthCm: 100, heightCm: 100);
      expect(cft5, closeTo(35.31467, 0.0001));
      expect(MaterialMeasurementEngine.formatCft(cft5), equals('35.31 CFT'));

      // 123 × 124 × 121 inches ≈ 1067.99305556 CFT -> must display as "1,067.99 CFT"
      final cft6 = MaterialMeasurementEngine.calculateFromInches(lengthIn: 123, widthIn: 124, heightIn: 121);
      expect(cft6, closeTo(1067.99305556, 0.000001));
      expect(MaterialMeasurementEngine.formatCft(cft6), equals('1,067.99 CFT'));
      expect(MaterialMeasurementEngine.formatQuantity(cft6, 'CFT'), equals('1,067.99 CFT'));
    });

    test('Unit conversion preserves physical dimensions and volume', () {
      // 120 inches converted to feet: 10 ft
      final (feet, inchesPart) = MaterialMeasurementEngine.convertDimension(
        mainValue: 120,
        from: DimensionUnit.inches,
        to: DimensionUnit.feet,
      );
      expect(feet, equals(10.0));
      expect(inchesPart, equals(0.0));

      // 10 ft converted to inches: 120 in
      final (inVal, inPart) = MaterialMeasurementEngine.convertDimension(
        mainValue: 10,
        from: DimensionUnit.feet,
        to: DimensionUnit.inches,
      );
      expect(inVal, equals(120.0));
      expect(inPart, equals(0.0));

      // 10.5 ft converted to ft_in: 10 ft 6 in
      final (ftComp, inComp) = MaterialMeasurementEngine.convertDimension(
        mainValue: 10.5,
        from: DimensionUnit.feet,
        to: DimensionUnit.feetAndInches,
      );
      expect(ftComp, equals(10.0));
      expect(inComp, equals(6.0));

      // 10 ft 6 in converted to inches: 126 in
      final (totalIn, _) = MaterialMeasurementEngine.convertDimension(
        mainValue: 10,
        inchesPart: 6,
        from: DimensionUnit.feetAndInches,
        to: DimensionUnit.inches,
      );
      expect(totalIn, equals(126.0));
    });

    test('Validation rejects invalid, negative, NaN, Inf, and excessively large values', () {
      expect(MaterialMeasurementEngine.calculateFromInches(lengthIn: -10, widthIn: 10, heightIn: 10), equals(0.0));
      expect(MaterialMeasurementEngine.calculateFromInches(lengthIn: double.nan, widthIn: 10, heightIn: 10), equals(0.0));
      expect(MaterialMeasurementEngine.calculateFromInches(lengthIn: double.infinity, widthIn: 10, heightIn: 10), equals(0.0));
      expect(MaterialMeasurementEngine.calculateFromInches(lengthIn: 999999999, widthIn: 10, heightIn: 10), equals(0.0));
    });

    test('Truck capacity validation correctly warns or permits supervisor override', () {
      // Within capacity: returns null
      expect(
        MaterialMeasurementEngine.validateTruckCapacity(
          loadQtyCft: 200,
          nominalCapacityCft: 240,
          allowOverride: false,
        ),
        isNull,
      );

      // Over capacity without override: returns warning message
      final warn = MaterialMeasurementEngine.validateTruckCapacity(
        loadQtyCft: 280,
        nominalCapacityCft: 240,
        allowOverride: false,
      );
      expect(warn, isNotNull);
      expect(warn, contains('exceeds truck capacity'));

      // Over capacity with override but missing reason: returns warning message
      final needReason = MaterialMeasurementEngine.validateTruckCapacity(
        loadQtyCft: 280,
        nominalCapacityCft: 240,
        allowOverride: true,
        overrideReason: '',
      );
      expect(needReason, isNotNull);
      expect(needReason, contains('override reason is required'));

      // Over capacity with override and valid reason: returns null (valid)
      expect(
        MaterialMeasurementEngine.validateTruckCapacity(
          loadQtyCft: 280,
          nominalCapacityCft: 240,
          allowOverride: true,
          overrideReason: 'Approved by Yard Supervisor for reinforced sideboard bed',
        ),
        isNull,
      );
    });
  });
}
