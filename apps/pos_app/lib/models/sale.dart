class Sale {
  final String id;
  final String number;

  final String? rawInvoiceNumber;

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
    this.rawInvoiceNumber,
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

  static String cleanTrackingNumber(
    String raw, {
    String fallbackPrefix = 'SAL',
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final docMatch = RegExp(
      r'(?:^|[-_\s])((?:INV|EST|PUR|EXP|BILL|SAL|TAX|RET)\s*[-_]\s*\d+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (docMatch != null) {
      return docMatch.group(1)!.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    }
    final parts = trimmed.split('-');
    if (parts.length >= 3) {
      final last = parts.last.trim();
      final prev = parts[parts.length - 2].trim();
      if (RegExp(r'^\d+$').hasMatch(last) &&
          RegExp(r'^[A-Za-z]+$').hasMatch(prev)) {
        return '$prev-$last'.toUpperCase();
      }
      if (RegExp(r'^\d+$').hasMatch(last)) {
        return '$fallbackPrefix-$last';
      }
    }
    return trimmed;
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final saleNum = map['sale_number']?.toString().trim();
    final invNum = map['invoice_number']?.toString().trim();
    final numField = map['number']?.toString().trim();
    final rawCandidate = (saleNum != null && saleNum.isNotEmpty)
        ? saleNum
        : ((invNum != null && invNum.isNotEmpty)
            ? invNum
            : (numField ?? ''));

    return Sale(
      id: map['sale_id']?.toString() ?? '',
      number: cleanTrackingNumber(rawCandidate, fallbackPrefix: 'SAL'),
      rawInvoiceNumber: invNum,
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
