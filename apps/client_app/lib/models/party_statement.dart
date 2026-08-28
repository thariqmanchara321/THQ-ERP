class PartyStatement {
  final String partyId;
  final String partyName;
  final double openingBalance;
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;
  final List<PartyStatementRow> rows;

  const PartyStatement({
    required this.partyId,
    required this.partyName,
    required this.openingBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
    required this.rows,
  });

  factory PartyStatement.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    final raw = map['rows'] as List? ?? const [];
    return PartyStatement(
      partyId: map['party_id']?.toString() ?? '',
      partyName: map['party_name']?.toString() ?? '',
      openingBalance: n(map['opening_balance']),
      totalDebit: n(map['total_debit']),
      totalCredit: n(map['total_credit']),
      closingBalance: n(map['closing_balance']),
      rows: raw
          .map(
            (e) =>
                PartyStatementRow.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }
}

class PartyStatementRow {
  final DateTime date;
  final String type;
  final String reference;
  final String description;
  final double debit;
  final double credit;
  final double balance;

  const PartyStatementRow({
    required this.date,
    required this.type,
    required this.reference,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  factory PartyStatementRow.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return PartyStatementRow(
      date: DateTime.parse(map['entry_date'].toString()),
      type: map['entry_type']?.toString() ?? '',
      reference: map['reference']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      debit: n(map['debit']),
      credit: n(map['credit']),
      balance: n(map['balance']),
    );
  }
}
