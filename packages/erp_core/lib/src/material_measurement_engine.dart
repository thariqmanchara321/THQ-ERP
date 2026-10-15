import 'dart:math' as math;
import 'package:intl/intl.dart';

/// Supported dimension units for truck body / volume measurement.
enum DimensionUnit {
  feet('ft', 'Feet (ft)'),
  inches('in', 'Inches (in)'),
  feetAndInches('ft_in', 'Feet & Inches (ft + in)'),
  metres('m', 'Metres (m)'),
  centimetres('cm', 'Centimetres (cm)');

  final String code;
  final String label;
  const DimensionUnit(this.code, this.label);

  static DimensionUnit fromCode(String? code) {
    return DimensionUnit.values.firstWhere(
      (u) => u.code == code,
      orElse: () => DimensionUnit.feet,
    );
  }
}

/// Supported high-level measurement methods.
enum MaterialMeasurementMethod {
  manual('manual', 'Manual quantity (CFT)'),
  dimensions('dimensions', 'Truck Body Dimensions'),
  weighbridge('weighbridge', 'Weighbridge (Gross - Tare)');

  final String code;
  final String label;
  const MaterialMeasurementMethod(this.code, this.label);

  static MaterialMeasurementMethod fromCode(String? code) {
    return MaterialMeasurementMethod.values.firstWhere(
      (m) => m.code == code,
      orElse: () => MaterialMeasurementMethod.manual,
    );
  }
}

/// Verified calculation engine for Material Yard load measurements.
class MaterialMeasurementEngine {
  // Constant conversion factors from verified standards
  static const double cubicInchesPerCft = 1728.0;
  static const double cftPerCubicMetre = 35.3146667214886;
  static const double cubicCentimetresPerCft = 28316.846592;
  static const double inchesPerMetre = 39.37007874015748;
  static const double centimetresPerInch = 2.54;
  static const double maxPhysicalDimensionInches = 1200000.0;

  // Formatting helpers — centralize two-decimal display with thousands separator
  static final NumberFormat _cftFormatter = NumberFormat('#,##0.00');

  /// Format CFT volume as user-facing string (e.g. `1,067.99 CFT`).
  static String formatCft(double? cft, {bool includeUnit = true}) {
    if (cft == null || !cft.isFinite || cft.isNaN) {
      return includeUnit ? '0.00 CFT' : '0.00';
    }
    final formatted = _cftFormatter.format(cft);
    return includeUnit ? '$formatted CFT' : formatted;
  }

  /// Format physical/billable quantity with specified unit code (e.g. `1,067.99 CFT` or `25.50 TON`).
  static String formatQuantity(double? qty, [String unit = 'CFT']) {
    if (qty == null || !qty.isFinite || qty.isNaN) {
      return '0.00 $unit';
    }
    final formatted = _cftFormatter.format(qty);
    return '$formatted $unit';
  }

  /// Convert a single dimension measurement between units without altering physical length.
  /// Returns a record of `(mainValue, inchesPart)`.
  /// For instance: 120 inches to feet returns (10.0, 0.0).
  /// 10.5 feet to feetAndInches returns (10.0, 6.0).
  static (double, double) convertDimension({
    required double mainValue,
    double inchesPart = 0.0,
    required DimensionUnit from,
    required DimensionUnit to,
  }) {
    if (from == to) return (mainValue, inchesPart);
    if (!mainValue.isFinite || mainValue.isNaN || mainValue <= 0) {
      return (0.0, 0.0);
    }

    // 1. Convert source to total inches
    double totalInches = 0.0;
    switch (from) {
      case DimensionUnit.inches:
        totalInches = mainValue;
        break;
      case DimensionUnit.feet:
        totalInches = mainValue * 12.0;
        break;
      case DimensionUnit.feetAndInches:
        totalInches = (mainValue * 12.0) + (inchesPart > 0 ? inchesPart : 0.0);
        break;
      case DimensionUnit.metres:
        totalInches = mainValue * inchesPerMetre;
        break;
      case DimensionUnit.centimetres:
        totalInches = mainValue / centimetresPerInch;
        break;
    }

    if (!totalInches.isFinite || totalInches <= 0) return (0.0, 0.0);

    // 2. Convert total inches to target unit
    switch (to) {
      case DimensionUnit.inches:
        return (double.parse(totalInches.toStringAsFixed(2)), 0.0);
      case DimensionUnit.feet:
        final feet = totalInches / 12.0;
        return (double.parse(feet.toStringAsFixed(2)), 0.0);
      case DimensionUnit.feetAndInches:
        final feet = (totalInches / 12.0).floorToDouble();
        final remInches = totalInches - (feet * 12.0);
        return (feet, double.parse(remInches.toStringAsFixed(2)));
      case DimensionUnit.metres:
        final metres = totalInches * 0.0254;
        return (double.parse(metres.toStringAsFixed(3)), 0.0);
      case DimensionUnit.centimetres:
        final cm = totalInches * centimetresPerInch;
        return (double.parse(cm.toStringAsFixed(2)), 0.0);
    }
  }

  /// Validate whether load quantity is within vehicle capacity.
  /// Returns null if valid, or a descriptive warning/error string.
  static String? validateTruckCapacity({
    required double loadQtyCft,
    required double? nominalCapacityCft,
    required bool allowOverride,
    String? overrideReason,
  }) {
    if (nominalCapacityCft == null || nominalCapacityCft <= 0) return null;
    if (loadQtyCft <= nominalCapacityCft) return null;

    if (!allowOverride) {
      return 'Load volume (${formatCft(loadQtyCft)}) exceeds truck capacity (${formatCft(nominalCapacityCft)}). '
          'Please enable "Allow Truck Capacity Override" with supervisor reason.';
    }
    if (overrideReason == null || overrideReason.trim().isEmpty) {
      return 'Truck capacity override enabled, but a supervisor override reason is required.';
    }
    return null;
  }

  /// Calculate CFT directly from dimensions in inches:
  /// CFT = Length × Width × Height / 1728
  static double calculateFromInches({
    required double lengthIn,
    required double widthIn,
    required double heightIn,
  }) {
    if (!lengthIn.isFinite || !widthIn.isFinite || !heightIn.isFinite) return 0.0;
    if (lengthIn <= 0 || widthIn <= 0 || heightIn <= 0) return 0.0;
    if (lengthIn > maxPhysicalDimensionInches ||
        widthIn > maxPhysicalDimensionInches ||
        heightIn > maxPhysicalDimensionInches) {
      return 0.0;
    }
    return (lengthIn * widthIn * heightIn) / cubicInchesPerCft;
  }

  /// Calculate CFT directly from dimensions in feet:
  /// CFT = Length × Width × Height
  static double calculateFromFeet({
    required double lengthFt,
    required double widthFt,
    required double heightFt,
  }) {
    if (!lengthFt.isFinite || !widthFt.isFinite || !heightFt.isFinite) return 0.0;
    if (lengthFt <= 0 || widthFt <= 0 || heightFt <= 0) return 0.0;
    if (lengthFt > (maxPhysicalDimensionInches / 12) ||
        widthFt > (maxPhysicalDimensionInches / 12) ||
        heightFt > (maxPhysicalDimensionInches / 12)) {
      return 0.0;
    }
    return lengthFt * widthFt * heightFt;
  }

  /// Calculate CFT from dimensions in metres:
  /// CFT = Length × Width × Height × 35.3146667214886
  static double calculateFromMetres({
    required double lengthM,
    required double widthM,
    required double heightM,
  }) {
    if (!lengthM.isFinite || !widthM.isFinite || !heightM.isFinite) return 0.0;
    if (lengthM <= 0 || widthM <= 0 || heightM <= 0) return 0.0;
    return lengthM * widthM * heightM * cftPerCubicMetre;
  }

  /// Calculate CFT from dimensions in centimetres:
  /// CFT = Length × Width × Height / 28316.846592
  static double calculateFromCentimetres({
    required double lengthCm,
    required double widthCm,
    required double heightCm,
  }) {
    if (!lengthCm.isFinite || !widthCm.isFinite || !heightCm.isFinite) return 0.0;
    if (lengthCm <= 0 || widthCm <= 0 || heightCm <= 0) return 0.0;
    return (lengthCm * widthCm * heightCm) / cubicCentimetresPerCft;
  }

  /// Calculate CFT from composite Feet + Inches:
  /// Convert each dimension to total inches: (ft * 12) + in
  /// Then CFT = (L_in * W_in * H_in) / 1728
  /// Example: 10ft (120in) * 6ft (72in) * 4ft (48in) = 240 CFT
  static double calculateFromFeetAndInches({
    required double lengthFt,
    double lengthIn = 0.0,
    required double widthFt,
    double widthIn = 0.0,
    required double heightFt,
    double heightIn = 0.0,
  }) {
    if (!lengthFt.isFinite || !widthFt.isFinite || !heightFt.isFinite) return 0.0;
    if (!lengthIn.isFinite || !widthIn.isFinite || !heightIn.isFinite) return 0.0;
    final totalLengthIn = (lengthFt * 12.0) + (lengthIn > 0 ? lengthIn : 0.0);
    final totalWidthIn = (widthFt * 12.0) + (widthIn > 0 ? widthIn : 0.0);
    final totalHeightIn = (heightFt * 12.0) + (heightIn > 0 ? heightIn : 0.0);

    return calculateFromInches(
      lengthIn: totalLengthIn,
      widthIn: totalWidthIn,
      heightIn: totalHeightIn,
    );
  }

  /// Calculate volume in CFT from dimensions across any supported DimensionUnit.
  static double calculateDimensionsVolume({
    required double length,
    double lengthInchesPart = 0.0,
    required double width,
    double widthInchesPart = 0.0,
    required double height,
    double heightInchesPart = 0.0,
    DimensionUnit unit = DimensionUnit.feet,
  }) {
    return process(
      method: MaterialMeasurementMethod.dimensions,
      unit: unit,
      length: length,
      lengthInchesPart: lengthInchesPart,
      width: width,
      widthInchesPart: widthInchesPart,
      height: height,
      heightInchesPart: heightInchesPart,
    ).geometricCft;
  }

  /// Calculate net weighbridge weight: Gross - Tare.
  static double calculateNetWeight({
    required double grossWeight,
    required double tareWeight,
  }) {
    if (!grossWeight.isFinite || !tareWeight.isFinite) return 0.0;
    final net = grossWeight - tareWeight;
    return net > 0 ? net : 0.0;
  }

  /// Convert weight to CFT only if an approved material bulk density is explicitly provided.
  /// Bulk density can be expressed as:
  /// - bulkDensityKgPerCft: e.g. 45.0 kg/CFT -> CFT = netKg / bulkDensityKgPerCft
  /// - bulkDensityTonPerCft: e.g. 0.045 ton/CFT -> CFT = netTon / bulkDensityTonPerCft
  /// If bulk density is null or <= 0, returns null because unapproved conversion is prohibited.
  static double? convertWeightToCft({
    required double netWeight,
    required double? bulkDensity,
    required bool isDensityApproved,
  }) {
    if (!isDensityApproved || bulkDensity == null || !bulkDensity.isFinite || bulkDensity <= 0) {
      return null;
    }
    if (!netWeight.isFinite || netWeight <= 0) return 0.0;
    return netWeight / bulkDensity;
  }

  /// Compute full measurement result including heap adjustment and billable variance.
  static MeasurementResult process({
    required MaterialMeasurementMethod method,
    DimensionUnit unit = DimensionUnit.feet,
    // Dimension inputs
    double length = 0.0,
    double lengthInchesPart = 0.0,
    double width = 0.0,
    double widthInchesPart = 0.0,
    double height = 0.0,
    double heightInchesPart = 0.0,
    // Weighbridge inputs
    double grossWeight = 0.0,
    double tareWeight = 0.0,
    double? bulkDensity,
    bool isDensityApproved = false,
    // Manual input
    double manualQuantity = 0.0,
    String manualUnit = 'CFT',
    // Heap adjustment
    double heapAdjustmentCft = 0.0,
    String? heapAdjustmentEvidence,
    // Billable quantity override
    double? approvedBillableQuantity,
    String? overrideReason,
    String? approvedByUserId,
  }) {
    double geometricCft = 0.0;
    double netWeight = 0.0;
    double? weighbridgeCft;

    switch (method) {
      case MaterialMeasurementMethod.manual:
        geometricCft = manualQuantity;
        break;

      case MaterialMeasurementMethod.dimensions:
        switch (unit) {
          case DimensionUnit.feet:
            geometricCft = calculateFromFeet(
              lengthFt: length,
              widthFt: width,
              heightFt: height,
            );
            break;
          case DimensionUnit.inches:
            geometricCft = calculateFromInches(
              lengthIn: length,
              widthIn: width,
              heightIn: height,
            );
            break;
          case DimensionUnit.feetAndInches:
            geometricCft = calculateFromFeetAndInches(
              lengthFt: length,
              lengthIn: lengthInchesPart,
              widthFt: width,
              widthIn: widthInchesPart,
              heightFt: height,
              heightIn: heightInchesPart,
            );
            break;
          case DimensionUnit.metres:
            geometricCft = calculateFromMetres(
              lengthM: length,
              widthM: width,
              heightM: height,
            );
            break;
          case DimensionUnit.centimetres:
            geometricCft = calculateFromCentimetres(
              lengthCm: length,
              widthCm: width,
              heightCm: height,
            );
            break;
        }
        break;

      case MaterialMeasurementMethod.weighbridge:
        netWeight = calculateNetWeight(
          grossWeight: grossWeight,
          tareWeight: tareWeight,
        );
        weighbridgeCft = convertWeightToCft(
          netWeight: netWeight,
          bulkDensity: bulkDensity,
          isDensityApproved: isDensityApproved,
        );
        geometricCft = weighbridgeCft ?? 0.0;
        break;
    }

    // Physical stock movement in CFT (including authorized heap adjustment)
    final physicalStockQty = math.max(0.0, geometricCft + heapAdjustmentCft);

    // Billable quantity: defaults to physical stock quantity unless explicitly overridden
    final billableQty = approvedBillableQuantity ?? physicalStockQty;

    // Variance between billable and physical stock
    final variance = billableQty - physicalStockQty;

    return MeasurementResult(
      method: method,
      unit: unit,
      length: length,
      lengthInchesPart: lengthInchesPart,
      width: width,
      widthInchesPart: widthInchesPart,
      height: height,
      heightInchesPart: heightInchesPart,
      grossWeight: grossWeight,
      tareWeight: tareWeight,
      netWeight: netWeight,
      bulkDensity: bulkDensity,
      isDensityApproved: isDensityApproved,
      geometricCft: geometricCft,
      heapAdjustmentCft: heapAdjustmentCft,
      heapAdjustmentEvidence: heapAdjustmentEvidence,
      physicalStockQuantity: physicalStockQty,
      approvedBillableQuantity: billableQty,
      variance: variance,
      overrideReason: overrideReason,
      approvedByUserId: approvedByUserId,
      timestamp: DateTime.now(),
    );
  }
}

/// Immutable result of a measurement calculation with full audit data.
class MeasurementResult {
  final MaterialMeasurementMethod method;
  final DimensionUnit unit;
  final double length;
  final double lengthInchesPart;
  final double width;
  final double widthInchesPart;
  final double height;
  final double heightInchesPart;
  final double grossWeight;
  final double tareWeight;
  final double netWeight;
  final double? bulkDensity;
  final bool isDensityApproved;
  final double geometricCft;
  final double heapAdjustmentCft;
  final String? heapAdjustmentEvidence;
  final double physicalStockQuantity;
  final double approvedBillableQuantity;
  final double variance;
  final String? overrideReason;
  final String? approvedByUserId;
  final DateTime timestamp;

  const MeasurementResult({
    required this.method,
    required this.unit,
    required this.length,
    required this.lengthInchesPart,
    required this.width,
    required this.widthInchesPart,
    required this.height,
    required this.heightInchesPart,
    required this.grossWeight,
    required this.tareWeight,
    required this.netWeight,
    this.bulkDensity,
    required this.isDensityApproved,
    required this.geometricCft,
    required this.heapAdjustmentCft,
    this.heapAdjustmentEvidence,
    required this.physicalStockQuantity,
    required this.approvedBillableQuantity,
    required this.variance,
    this.overrideReason,
    this.approvedByUserId,
    required this.timestamp,
  });

  /// Convert raw dimensions into JSON for storage in `raw_dimensions` column.
  Map<String, dynamic> toRawDimensionsJson() => {
    'method': method.code,
    'unit': unit.code,
    'length': length,
    'length_in': lengthInchesPart,
    'width': width,
    'width_in': widthInchesPart,
    'height': height,
    'height_in': heightInchesPart,
    'gross_weight': grossWeight,
    'tare_weight': tareWeight,
    'net_weight': netWeight,
    if (bulkDensity != null) 'bulk_density': bulkDensity,
    'is_density_approved': isDensityApproved,
    'geometric_cft': geometricCft,
    'heap_adjustment_cft': heapAdjustmentCft,
    if (heapAdjustmentEvidence != null) 'heap_evidence': heapAdjustmentEvidence,
    'physical_stock_qty': physicalStockQuantity,
    'approved_billable_qty': approvedBillableQuantity,
    'variance': variance,
    if (overrideReason != null) 'override_reason': overrideReason,
    if (approvedByUserId != null) 'approved_by': approvedByUserId,
    'timestamp': timestamp.toIso8601String(),
  };

  /// Equivalent length, width, height in decimal feet for backward-compatible columns.
  double? get lengthFtEquivalent {
    if (method != MaterialMeasurementMethod.dimensions) return null;
    switch (unit) {
      case DimensionUnit.feet:
        return length;
      case DimensionUnit.inches:
        return length / 12.0;
      case DimensionUnit.feetAndInches:
        return length + (lengthInchesPart / 12.0);
      case DimensionUnit.metres:
        return length * 3.28084;
      case DimensionUnit.centimetres:
        return (length / 100.0) * 3.28084;
    }
  }

  double? get widthFtEquivalent {
    if (method != MaterialMeasurementMethod.dimensions) return null;
    switch (unit) {
      case DimensionUnit.feet:
        return width;
      case DimensionUnit.inches:
        return width / 12.0;
      case DimensionUnit.feetAndInches:
        return width + (widthInchesPart / 12.0);
      case DimensionUnit.metres:
        return width * 3.28084;
      case DimensionUnit.centimetres:
        return (width / 100.0) * 3.28084;
    }
  }

  double? get heightFtEquivalent {
    if (method != MaterialMeasurementMethod.dimensions) return null;
    switch (unit) {
      case DimensionUnit.feet:
        return height;
      case DimensionUnit.inches:
        return height / 12.0;
      case DimensionUnit.feetAndInches:
        return height + (heightInchesPart / 12.0);
      case DimensionUnit.metres:
        return height * 3.28084;
      case DimensionUnit.centimetres:
        return (height / 100.0) * 3.28084;
    }
  }
}

/// State representation for Material Yard measurement form and load entry across Desktop & Mobile.
class MaterialMeasurementData {
  String method; // 'manual', 'dimensions', 'weighbridge'
  String unitCode; // 'CFT', 'TON', 'CBM', 'LOAD', 'BRASS'
  String dimensionUnit; // 'ft', 'in', 'ft_in', 'm', 'cm'

  // Dimensions
  double? length;
  double? lengthIn;
  double? width;
  double? widthIn;
  double? height;
  double? heightIn;

  // Weighbridge
  double? grossWeight;
  double? tareWeight;
  double? bulkDensity;
  bool isDensityApproved;

  // Volume & Adjustment
  double calculatedCft;
  double heapAdjustmentCft;
  String heapAdjustmentReason;

  // Final Quantities & Audits
  double physicalQty;
  double approvedBillableQty;
  String? approvedBy;
  String? varianceReason;
  String? notes;

  MaterialMeasurementData({
    this.method = 'manual',
    this.unitCode = 'CFT',
    this.dimensionUnit = 'ft',
    this.length,
    this.lengthIn,
    this.width,
    this.widthIn,
    this.height,
    this.heightIn,
    this.grossWeight,
    this.tareWeight,
    this.bulkDensity,
    this.isDensityApproved = false,
    this.calculatedCft = 0.0,
    this.heapAdjustmentCft = 0.0,
    this.heapAdjustmentReason = '',
    this.physicalQty = 0.0,
    this.approvedBillableQty = 0.0,
    this.approvedBy,
    this.varianceReason,
    this.notes,
  });

  Map<String, dynamic> toRawDimensionsMap() {
    return {
      'method': method,
      'unit': dimensionUnit,
      'length': length,
      'length_in': lengthIn,
      'width': width,
      'width_in': widthIn,
      'height': height,
      'height_in': heightIn,
      'gross_weight': grossWeight,
      'tare_weight': tareWeight,
      'bulk_density': bulkDensity,
      'density_approved': isDensityApproved,
      'heap_adjustment_cft': heapAdjustmentCft,
      'heap_adjustment_reason': heapAdjustmentReason,
    };
  }
}
