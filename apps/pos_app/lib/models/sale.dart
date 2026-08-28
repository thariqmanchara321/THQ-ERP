class Sale {
  final String id;
  final String number;

  final String customerId;
  final String customerName;

  final DateTime saleDate;
  final DateTime? dueDate;

  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double additionalCharges;

  final double grandTotal;

  final double paidAmount;
  final double balanceDue;

  final String paymentStatus;

  final double costTotal;
  final double grossProfit;

  final String status;

  final DateTime? createdAt;

  const Sale({
    required this.id,
    required this.number,
    required this.customerId,
    required this.customerName,
    required this.saleDate,
    required this.dueDate,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.additionalCharges,
    required this.grandTotal,
    required this.paidAmount,
    required this.balanceDue,
    required this.paymentStatus,
    required this.costTotal,
    required this.grossProfit,
    required this.status,
    required this.createdAt,
  });

  factory Sale.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return Sale(
      id: map['sale_id']?.toString() ?? '',
      number: (map['invoice_number'] ?? map['sale_number'])?.toString() ?? '',
      customerId: map['customer_id']?.toString() ?? '',
      customerName: map['customer_name']?.toString() ?? '',
      saleDate: DateTime.parse(map['sale_date'].toString()),
      dueDate: map['due_date'] == null
          ? null
          : DateTime.tryParse(map['due_date'].toString()),
      subtotal: number(map['subtotal']),
      discountTotal: number(map['discount_total']),
      taxTotal: number(map['tax_total']),
      additionalCharges: number(map['additional_charges']),
      grandTotal: number(map['grand_total']),
      paidAmount: number(map['paid_amount']),
      balanceDue: number(map['balance_due']),
      paymentStatus: map['payment_status']?.toString() ?? 'unpaid',
      costTotal: number(map['cost_total']),
      grossProfit: number(map['gross_profit']),
      status: map['status']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}
