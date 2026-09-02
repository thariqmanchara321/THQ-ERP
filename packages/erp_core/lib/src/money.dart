/// Fixed two-decimal money value backed by integer minor units.
/// Financial truth remains server-authoritative; this prevents avoidable
/// binary floating-point drift in shared client-side calculations.
class Money implements Comparable<Money> {
  final int minorUnits;
  const Money._(this.minorUnits);

  const Money.zero() : minorUnits = 0;

  factory Money.fromDouble(double value) => Money._((value * 100).round());

  factory Money.fromMinorUnits(int value) => Money._(value);

  double get asDouble => minorUnits / 100.0;

  Money operator +(Money other) => Money._(minorUnits + other.minorUnits);
  Money operator -(Money other) => Money._(minorUnits - other.minorUnits);

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  String toString() => asDouble.toStringAsFixed(2);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;
}
