class DashboardData {
  final double todaySales;
  final double monthSales;
  final double monthPurchases;
  final double monthExpenses;
  final double monthGrossProfit;
  final double monthNetProfit;
  final double receivables;
  final double payables;
  final int lowStockCount;
  final int productCount;
  final int customerCount;
  final int supplierCount;

  const DashboardData({
    required this.todaySales,
    required this.monthSales,
    required this.monthPurchases,
    required this.monthExpenses,
    required this.monthGrossProfit,
    required this.monthNetProfit,
    required this.receivables,
    required this.payables,
    required this.lowStockCount,
    required this.productCount,
    required this.customerCount,
    required this.supplierCount,
  });

  factory DashboardData.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    int i(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    return DashboardData(
      todaySales: n(map['today_sales']),
      monthSales: n(map['month_sales']),
      monthPurchases: n(map['month_purchases']),
      monthExpenses: n(map['month_expenses']),
      monthGrossProfit: n(map['month_gross_profit']),
      monthNetProfit: n(map['month_net_profit']),
      receivables: n(map['receivables']),
      payables: n(map['payables']),
      lowStockCount: i(map['low_stock_count']),
      productCount: i(map['product_count']),
      customerCount: i(map['customer_count']),
      supplierCount: i(map['supplier_count']),
    );
  }
}
