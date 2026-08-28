class AccountingSummary {
  final double revenue;
  final double costOfGoodsSold;
  final double grossProfit;
  final double operatingExpenses;
  final double netOperatingProfit;
  final double receivables;
  final double payables;
  final double inventoryValue;

  const AccountingSummary({
    required this.revenue,
    required this.costOfGoodsSold,
    required this.grossProfit,
    required this.operatingExpenses,
    required this.netOperatingProfit,
    required this.receivables,
    required this.payables,
    required this.inventoryValue,
  });

  factory AccountingSummary.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return AccountingSummary(
      revenue: n(map['revenue']),
      costOfGoodsSold: n(map['cost_of_goods_sold']),
      grossProfit: n(map['gross_profit']),
      operatingExpenses: n(map['operating_expenses']),
      netOperatingProfit: n(map['net_operating_profit']),
      receivables: n(map['receivables']),
      payables: n(map['payables']),
      inventoryValue: n(map['inventory_value']),
    );
  }
}

class LedgerRow {
  final DateTime date;
  final String type;
  final String reference;
  final String party;
  final String description;
  final double debit;
  final double credit;

  const LedgerRow({
    required this.date,
    required this.type,
    required this.reference,
    required this.party,
    required this.description,
    required this.debit,
    required this.credit,
  });

  factory LedgerRow.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return LedgerRow(
      date: DateTime.parse(map['entry_date'].toString()),
      type: map['entry_type']?.toString() ?? '',
      reference: map['reference']?.toString() ?? '',
      party: map['party']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      debit: n(map['debit']),
      credit: n(map['credit']),
    );
  }
}
