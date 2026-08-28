class PendingPayment {
  final String id, type, reference, partyId, partyName;
  final DateTime date;
  final DateTime? dueDate;
  final double total, paid, balance;
  const PendingPayment({
    required this.id,
    required this.type,
    required this.reference,
    required this.partyId,
    required this.partyName,
    required this.date,
    required this.dueDate,
    required this.total,
    required this.paid,
    required this.balance,
  });
  factory PendingPayment.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return PendingPayment(
      id: m['id']?.toString() ?? '',
      type: m['type']?.toString() ?? '',
      reference: m['reference']?.toString() ?? '',
      partyId: m['party_id']?.toString() ?? '',
      partyName: m['party_name']?.toString() ?? '',
      date: DateTime.parse(m['date'].toString()),
      dueDate: m['due_date'] == null
          ? null
          : DateTime.tryParse(m['due_date'].toString()),
      total: n(m['total']),
      paid: n(m['paid']),
      balance: n(m['balance']),
    );
  }
}

class PendingPaymentsData {
  final List<PendingPayment> receivables, payables;
  const PendingPaymentsData({
    required this.receivables,
    required this.payables,
  });
  factory PendingPaymentsData.fromMap(
    Map<String, dynamic> m,
  ) => PendingPaymentsData(
    receivables: (m['receivables'] as List? ?? const [])
        .map((e) => PendingPayment.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    payables: (m['payables'] as List? ?? const [])
        .map((e) => PendingPayment.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}
