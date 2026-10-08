import 'package:intl/intl.dart';

/// Human report projection. Never used for persistence or transaction requests.
class RecordPresentation {
  static bool internal(String key) =>
      key == 'id' ||
      key.endsWith('_id') ||
      key.endsWith('_ids') ||
      const {
        'ids',
        'created_by',
        'updated_by',
        'request_payload',
      }.contains(key);

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static dynamic clean(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!internal('${entry.key}') &&
              !(entry.value is String && _uuid.hasMatch(entry.value)))
            '${entry.key}': clean(entry.value),
      };
    }
    if (value is List) return value.map(clean).toList();
    return value is String && _uuid.hasMatch(value) ? '—' : value;
  }

  static Map<String, dynamic> report(Map<String, dynamic> record) =>
      Map<String, dynamic>.from(clean(record) as Map);

  static String label(String key) {
    const labels = {
      'staff_code': 'Staff ID',
      'entry_number': 'Document reference',
      'document_reference': 'Document reference',
      'load_number': 'Load ticket',
      'staff_name': 'Staff name',
      'period_from': 'Period from',
      'period_to': 'Period to',
      'paid_through_end': 'Paid through statement end',
      'advance_remaining_through_end':
          'Advance remaining through statement end',
      'load_allocations': 'Salary allocations to loads',
      'history': 'Activity history',
      'balances_by_location': 'Balances by store',
    };
    if (labels.containsKey(key)) return labels[key]!;
    final text = key.replaceAll('_', ' ').replaceAll('.', ' ');
    return text.isEmpty ? '' : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  static String value(String key, dynamic value, {String currency = ''}) {
    if (value == null || value == '') return '—';
    if (value is num) {
      final money =
          key.endsWith('_amount') ||
          key.endsWith('_total') ||
          key.endsWith('_balance') ||
          key.endsWith('_rate') ||
          const {
            'amount',
            'rate',
            'balance',
            'earned',
            'paid',
            'outstanding',
            'earning',
            'payment',
            'allowances',
            'deductions',
            'period_earnings',
            'period_payments',
            'opening_balance',
            'closing_balance',
            'closing_due',
            'closing_advance',
            'current_due',
            'current_advance',
            'paid_through_end',
            'advance_remaining_through_end',
            'advance_remaining',
          }.contains(key);
      return money
          ? '${currency.isEmpty ? '' : '$currency '}${NumberFormat('#,##0.00').format(value)}'
          : NumberFormat('#,##0.####').format(value);
    }
    if (value is bool) return value ? 'Yes' : 'No';
    if (key.endsWith('_at') ||
        key.endsWith('_date') ||
        const {
          'date',
          'from',
          'to',
          'period_from',
          'period_to',
          'joined_on',
          'left_on',
        }.contains(key)) {
      final date = DateTime.tryParse('$value');
      if (date != null) {
        return key.endsWith('_at')
            ? '${DateFormat('dd MMM yyyy HH:mm').format(date)}${date.isUtc ? ' UTC' : ''}'
            : DateFormat('dd MMM yyyy').format(date);
      }
    }
    if (const {
      'kind',
      'wage_basis',
      'event_type',
      'payment_method',
      'staff_mode',
      'status',
      'job_role',
      'action',
    }.contains(key)) {
      return label('$value');
    }
    return '$value';
  }
}
