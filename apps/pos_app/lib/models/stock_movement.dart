class StockMovement {
  final String id;
  final String type;

  final double quantityDelta;
  final double? unitCost;
  final String? unitCode;
  final double baseQuantityDelta;
  final double? balanceBefore;
  final double? balanceAfter;
  final double conversionToBase;

  final String locationName;

  final String? referenceType;
  final String? referenceNumber;

  final String? note;

  final DateTime? occurredAt;
  final DateTime? createdAt;

  const StockMovement({
    required this.id,
    required this.type,
    required this.quantityDelta,
    required this.unitCost,
    required this.unitCode,
    required this.baseQuantityDelta,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.conversionToBase,
    required this.locationName,
    required this.referenceType,
    required this.referenceNumber,
    required this.note,
    required this.occurredAt,
    required this.createdAt,
  });

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    double? nullableNumber(dynamic value) {
      if (value == null) {
        return null;
      }

      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value.toString());
    }

    return StockMovement(
      id: map['movement_id']?.toString() ?? '',
      type: map['movement_type']?.toString() ?? '',
      quantityDelta: number(map['quantity_delta']),
      unitCost: nullableNumber(map['unit_cost']),
      unitCode: map['unit_code']?.toString(),
      baseQuantityDelta: number(
        map['base_quantity_delta'] ?? map['quantity_delta'],
      ),
      balanceBefore: nullableNumber(map['balance_before']),
      balanceAfter: nullableNumber(map['balance_after']),
      conversionToBase: number(map['conversion_to_base']) == 0
          ? 1
          : number(map['conversion_to_base']),
      locationName: map['location_name']?.toString() ?? '',
      referenceType: map['reference_type']?.toString(),
      referenceNumber: map['reference_number']?.toString(),
      note: map['note']?.toString(),
      occurredAt: DateTime.tryParse(map['occurred_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}
