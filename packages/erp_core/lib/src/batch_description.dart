/// Invoice descriptions use captured allocation values, never current prices.
String documentBatchDescription(List<Map<String, dynamic>> allocations) {
  String number(dynamic value, int decimals) {
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    if (n == null) {
      return '';
    }
    return n.toStringAsFixed(decimals).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  return allocations
      .map((batch) {
        final quality = batch['quality_label']?.toString().trim() ?? '';
        return '${batch['batch_number'] ?? 'Batch'}'
            '${quality.isEmpty ? '' : ' / $quality'}'
            ' • ${number(batch['quantity'], 3)} ${batch['base_unit_code'] ?? ''}'
            ' @ ${number(batch['rate'], 4)}';
      })
      .join('\n');
}
