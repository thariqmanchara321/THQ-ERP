List<String> parseTrackingSerials(String text, double quantity) {
  final values = text.split(RegExp(r'[\n,;]+')).map((s) => s.trim())
      .where((s) => s.isNotEmpty).toList();
  if (!quantity.isFinite || quantity < 0 || quantity != quantity.truncateToDouble()) {
    throw const FormatException('Serial tracking requires whole base units.');
  }
  if (values.map((s) => s.toLowerCase()).toSet().length != values.length) {
    throw const FormatException('A serial number appears more than once.');
  }
  if (values.length != quantity) {
    throw FormatException('Enter exactly ${quantity.toStringAsFixed(0)} serial numbers.');
  }
  return values;
}

List<Map<String, dynamic>> parseTrackingBatches(String text, double quantity) {
  if (!quantity.isFinite || quantity < 0) {
    throw const FormatException('Enter a valid base-unit quantity.');
  }
  final rows = <Map<String, dynamic>>[];
  final names = <String>{};
  var total = 0.0;
  for (final line in text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    final separator = line.lastIndexOf('=');
    if (separator < 1) throw const FormatException('Use BATCH=QUANTITY or BATCH=QUANTITY|YYYY-MM-DD.');
    final name = line.substring(0, separator).trim();
    final parts = line.substring(separator + 1).split('|').map((s) => s.trim()).toList();
    final amount = double.tryParse(parts.first);
    if (parts.length > 2 || amount == null || !amount.isFinite || amount <= 0) {
      throw const FormatException('Every batch needs a positive quantity.');
    }
    if (!names.add(name.toLowerCase())) throw const FormatException('A batch appears more than once.');
    final row = <String, dynamic>{'batch_number': name, 'quantity': amount};
    if (parts.length == 2 && parts[1].isNotEmpty) {
      final date = DateTime.tryParse(parts[1]);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[1]) || date == null ||
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' != parts[1]) {
        throw const FormatException('Expiry must be a valid date: YYYY-MM-DD.');
      }
      row['expiry_on'] = parts[1];
    }
    rows.add(row);
    total += amount;
  }
  if ((total - quantity).abs() > 0.000001) {
    throw FormatException('Batch quantities must total $quantity base units.');
  }
  return rows;
}
