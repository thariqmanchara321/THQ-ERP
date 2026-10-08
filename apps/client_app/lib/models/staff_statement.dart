import 'record_presentation.dart';

class StaffStatement {
  final Map<String, dynamic> data;
  final String currency;
  StaffStatement(this.data, {required this.currency}) {
    if (data['complete'] != true ||
        data['profile'] is! Map ||
        data['summary'] is! Map ||
        data['ledger'] is! List) {
      throw StateError('The complete Staff statement could not be loaded.');
    }
  }
  Map<String, dynamic> get profile =>
      Map<String, dynamic>.from(data['profile']);
  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(data['summary']);
  String get name => '${profile['name'] ?? ''}';
  String get staffCode => '${profile['staff_code'] ?? ''}';
  String get period =>
      '${text('from', data['period']['from'])} – ${text('to', data['period']['to'])}';
  List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
      .whereType<Map>()
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  String text(String key, dynamic value) =>
      RecordPresentation.value(key, value, currency: currency);
  Map<String, dynamic> get report => RecordPresentation.report({
    ...data,
    'earnings': rows('earnings')
        .map(
          (row) => {
            ...row,
            // The saved paid_amount is current, whereas this payslip is as of To.
            'paid_amount': row['paid_through_end'],
            'outstanding':
                number(row['amount']) - number(row['paid_through_end']),
          },
        )
        .toList(),
    'payments': rows('payments')
        .map(
          (row) => {
            ...row,
            'advance_remaining': row['advance_remaining_through_end'],
          },
        )
        .toList(),
  });
  static double number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  static const balanceNote =
      'Positive balances are due to staff; negative balances are available advances. Balances are measured through the statement end date. Salary allocations to loads are informational and are not added to earnings.';
}
