class ReportSummary {
  final DateTime from;
  final DateTime to;
  final double sales;
  final double salesTax;
  final double purchases;
  final double purchaseTax;
  final double expenses;
  final double salesReturns;
  final double purchaseReturns;
  final double grossProfit;
  final double netProfit;
  final double receivables;
  final double payables;
  final double stockValue;
  final int saleCount;
  final int purchaseCount;
  final int expenseCount;

  const ReportSummary({
    required this.from,
    required this.to,
    required this.sales,
    required this.salesTax,
    required this.purchases,
    required this.purchaseTax,
    required this.expenses,
    required this.salesReturns,
    required this.purchaseReturns,
    required this.grossProfit,
    required this.netProfit,
    required this.receivables,
    required this.payables,
    required this.stockValue,
    required this.saleCount,
    required this.purchaseCount,
    required this.expenseCount,
  });

  factory ReportSummary.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    int i(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    return ReportSummary(
      from: DateTime.parse(map['from_date'].toString()),
      to: DateTime.parse(map['to_date'].toString()),
      sales: n(map['sales']),
      salesTax: n(map['sales_tax']),
      purchases: n(map['purchases']),
      purchaseTax: n(map['purchase_tax']),
      expenses: n(map['expenses']),
      salesReturns: n(map['sales_returns']),
      purchaseReturns: n(map['purchase_returns']),
      grossProfit: n(map['gross_profit']),
      netProfit: n(map['net_profit']),
      receivables: n(map['receivables']),
      payables: n(map['payables']),
      stockValue: n(map['stock_value']),
      saleCount: i(map['sale_count']),
      purchaseCount: i(map['purchase_count']),
      expenseCount: i(map['expense_count']),
    );
  }
}
