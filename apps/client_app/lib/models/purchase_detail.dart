class PurchaseDetail {
  final String purchaseId;
  final String purchaseNumber;

  final String supplierId;
  final String supplierName;
  final String? supplierTaxNumber;
  final String? supplierInvoiceNumber;

  final DateTime purchaseDate;
  final DateTime? dueDate;

  final String status;

  final double subtotal;
  final double discountTotal;
  final double taxableTotal;
  final double taxTotal;
  final double additionalCharges;
  final double grandTotal;

  final String? notes;
  final DateTime? createdAt;

  final List<PurchaseDetailItem> items;
  final List<PurchasePayment> payments;

  final double paidAmount;
  final double balanceDue;

  const PurchaseDetail({
    required this.purchaseId,
    required this.purchaseNumber,
    required this.supplierId,
    required this.supplierName,
    required this.supplierTaxNumber,
    required this.supplierInvoiceNumber,
    required this.purchaseDate,
    required this.dueDate,
    required this.status,
    required this.subtotal,
    required this.discountTotal,
    required this.taxableTotal,
    required this.taxTotal,
    required this.additionalCharges,
    required this.grandTotal,
    required this.notes,
    required this.createdAt,
    required this.items,
    required this.payments,
    required this.paidAmount,
    required this.balanceDue,
  });

  String get paymentStatus {
    if (balanceDue <= 0.0001) {
      return 'paid';
    }

    if (paidAmount > 0) {
      return 'partial';
    }

    return 'unpaid';
  }

  factory PurchaseDetail.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final purchaseRaw = map['purchase'];

    if (purchaseRaw is! Map) {
      throw Exception('Invalid purchase detail response.');
    }

    final purchase = Map<String, dynamic>.from(purchaseRaw);

    final itemsRaw = map['items'] as List? ?? [];

    final paymentsRaw = map['payments'] as List? ?? [];

    return PurchaseDetail(
      purchaseId: purchase['purchase_id']?.toString() ?? '',
      purchaseNumber: purchase['purchase_number']?.toString() ?? '',
      supplierId: purchase['supplier_id']?.toString() ?? '',
      supplierName: purchase['supplier_name']?.toString() ?? '',
      supplierTaxNumber: purchase['supplier_tax_number']?.toString(),
      supplierInvoiceNumber: purchase['supplier_invoice_number']?.toString(),
      purchaseDate: DateTime.parse(purchase['purchase_date'].toString()),
      dueDate: purchase['due_date'] == null
          ? null
          : DateTime.tryParse(purchase['due_date'].toString()),
      status: purchase['status']?.toString() ?? '',
      subtotal: number(purchase['subtotal']),
      discountTotal: number(purchase['discount_total']),
      taxableTotal: number(purchase['taxable_total']),
      taxTotal: number(purchase['tax_total']),
      additionalCharges: number(purchase['additional_charges']),
      grandTotal: number(purchase['grand_total']),
      notes: purchase['notes']?.toString(),
      createdAt: DateTime.tryParse(purchase['created_at']?.toString() ?? ''),
      items: itemsRaw
          .map(
            (item) => PurchaseDetailItem.fromMap(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      payments: paymentsRaw
          .map(
            (payment) => PurchasePayment.fromMap(
              Map<String, dynamic>.from(payment as Map),
            ),
          )
          .toList(),
      paidAmount: number(map['paid_amount']),
      balanceDue: number(map['balance_due']),
    );
  }
}

class PurchaseDetailItem {
  final String itemId;
  final String variantId;

  final String productName;
  final String sku;
  final String? partNumber;
  final String? unitCode;

  final double quantity;
  final double unitCost;

  final double discountAmount;
  final double taxRate;

  final double subtotal;
  final double taxableAmount;
  final double taxAmount;
  final double lineTotal;

  const PurchaseDetailItem({
    required this.itemId,
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.partNumber,
    required this.unitCode,
    required this.quantity,
    required this.unitCost,
    required this.discountAmount,
    required this.taxRate,
    required this.subtotal,
    required this.taxableAmount,
    required this.taxAmount,
    required this.lineTotal,
  });

  factory PurchaseDetailItem.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return PurchaseDetailItem(
      itemId: map['item_id']?.toString() ?? '',
      variantId: map['variant_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      partNumber: map['part_number']?.toString(),
      unitCode: map['unit_code']?.toString(),
      quantity: number(map['quantity']),
      unitCost: number(map['unit_cost']),
      discountAmount: number(map['discount_amount']),
      taxRate: number(map['tax_rate']),
      subtotal: number(map['subtotal']),
      taxableAmount: number(map['taxable_amount']),
      taxAmount: number(map['tax_amount']),
      lineTotal: number(map['line_total']),
    );
  }
}

class PurchasePayment {
  final String paymentId;

  final double amount;

  final String paymentMethod;

  final String? referenceNumber;
  final String? notes;

  final DateTime? paidAt;

  const PurchasePayment({
    required this.paymentId,
    required this.amount,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.notes,
    required this.paidAt,
  });

  factory PurchasePayment.fromMap(Map<String, dynamic> map) {
    double number(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }

      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return PurchasePayment(
      paymentId: map['payment_id']?.toString() ?? '',
      amount: number(map['amount']),
      paymentMethod: map['payment_method']?.toString() ?? '',
      referenceNumber: map['reference_number']?.toString(),
      notes: map['notes']?.toString(),
      paidAt: DateTime.tryParse(map['paid_at']?.toString() ?? ''),
    );
  }
}
