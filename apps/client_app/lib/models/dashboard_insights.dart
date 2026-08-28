class TopProductInsight {
  final String variantId, productName;
  final double quantity, sales;
  const TopProductInsight({
    required this.variantId,
    required this.productName,
    required this.quantity,
    required this.sales,
  });
  factory TopProductInsight.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return TopProductInsight(
      variantId: m['variant_id']?.toString() ?? '',
      productName: m['product_name']?.toString() ?? '',
      quantity: n(m['quantity']),
      sales: n(m['sales']),
    );
  }
}

class TopCustomerInsight {
  final String customerId, customerName;
  final double sales;
  final int invoiceCount;
  const TopCustomerInsight({
    required this.customerId,
    required this.customerName,
    required this.sales,
    required this.invoiceCount,
  });
  factory TopCustomerInsight.fromMap(Map<String, dynamic> m) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return TopCustomerInsight(
      customerId: m['customer_id']?.toString() ?? '',
      customerName: m['customer_name']?.toString() ?? '',
      sales: n(m['sales']),
      invoiceCount: m['invoice_count'] is num
          ? (m['invoice_count'] as num).toInt()
          : int.tryParse(m['invoice_count']?.toString() ?? '') ?? 0,
    );
  }
}

class DailySalesInsight {
  final DateTime date;
  final double sales;
  const DailySalesInsight({required this.date, required this.sales});
  factory DailySalesInsight.fromMap(Map<String, dynamic> m) =>
      DailySalesInsight(
        date: DateTime.parse(m['date'].toString()),
        sales: m['sales'] is num
            ? (m['sales'] as num).toDouble()
            : double.tryParse(m['sales']?.toString() ?? '') ?? 0,
      );
}

class DashboardInsights {
  final List<TopProductInsight> topProducts;
  final List<TopCustomerInsight> topCustomers;
  final List<DailySalesInsight> dailySales;
  const DashboardInsights({
    required this.topProducts,
    required this.topCustomers,
    required this.dailySales,
  });
  factory DashboardInsights.fromMap(
    Map<String, dynamic> m,
  ) => DashboardInsights(
    topProducts: (m['top_products'] as List? ?? const [])
        .map(
          (e) => TopProductInsight.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    topCustomers: (m['top_customers'] as List? ?? const [])
        .map(
          (e) =>
              TopCustomerInsight.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    dailySales: (m['daily_sales'] as List? ?? const [])
        .map(
          (e) => DailySalesInsight.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );
}
