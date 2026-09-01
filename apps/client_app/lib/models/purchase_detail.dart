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
  final PurchaseGstDetail? gst;

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
    this.gst,
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
      gst: map['gst'] is Map
          ? PurchaseGstDetail.fromMap(
              Map<String, dynamic>.from(map['gst'] as Map),
            )
          : null,
    );
  }
}

class PurchaseGstDetail {
  final bool authoritative;
  final bool interstate;
  final String? taxMode;
  final String? supplyType;
  final String? placeOfSupplyCode;
  final double taxableTotal;
  final double cgstTotal;
  final double sgstTotal;
  final double utgstTotal;
  final double igstTotal;
  final double cessTotal;
  final double taxCollectedTotal;
  final List<PurchaseGstLine> lines;

  const PurchaseGstDetail({
    required this.authoritative,
    required this.interstate,
    required this.taxMode,
    required this.supplyType,
    required this.placeOfSupplyCode,
    required this.taxableTotal,
    required this.cgstTotal,
    required this.sgstTotal,
    required this.utgstTotal,
    required this.igstTotal,
    required this.cessTotal,
    required this.taxCollectedTotal,
    required this.lines,
  });

  bool get hasComponentTax =>
      cgstTotal.abs() > .0001 ||
      sgstTotal.abs() > .0001 ||
      utgstTotal.abs() > .0001 ||
      igstTotal.abs() > .0001 ||
      cessTotal.abs() > .0001;

  List<PurchaseGstRateSummary> get rateSummaries {
    final grouped = <String, PurchaseGstRateSummary>{};
    for (final line in lines) {
      final key = line.gstRate.toStringAsFixed(4);
      grouped[key] =
          (grouped[key] ?? PurchaseGstRateSummary(rate: line.gstRate)).add(
            line,
          );
    }
    final rows = grouped.values.toList()
      ..sort((a, b) => a.rate.compareTo(b.rate));
    return rows;
  }

  factory PurchaseGstDetail.fromMap(Map<String, dynamic> map) {
    double n(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return PurchaseGstDetail(
      authoritative: map['authoritative'] == true,
      interstate: map['interstate'] == true,
      taxMode: map['tax_mode']?.toString(),
      supplyType: map['supply_type']?.toString(),
      placeOfSupplyCode: map['place_of_supply_code']?.toString(),
      taxableTotal: n(map['taxable_total']),
      cgstTotal: n(map['cgst_total']),
      sgstTotal: n(map['sgst_total']),
      utgstTotal: n(map['utgst_total']),
      igstTotal: n(map['igst_total']),
      cessTotal: n(map['cess_total']),
      taxCollectedTotal: n(map['tax_collected_total']),
      lines: (map['lines'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => PurchaseGstLine.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false),
    );
  }
}

class PurchaseGstLine {
  final String sourceLineId;
  final int lineNo;
  final String hsnSac;
  final double gstRate;
  final double taxableValue;
  final double cgst;
  final double sgst;
  final double utgst;
  final double igst;
  final double cess;
  final double taxAmount;

  const PurchaseGstLine({
    required this.sourceLineId,
    required this.lineNo,
    required this.hsnSac,
    required this.gstRate,
    required this.taxableValue,
    required this.cgst,
    required this.sgst,
    required this.utgst,
    required this.igst,
    required this.cess,
    required this.taxAmount,
  });

  factory PurchaseGstLine.fromMap(Map<String, dynamic> map) {
    double n(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return PurchaseGstLine(
      sourceLineId: map['source_line_id']?.toString() ?? '',
      lineNo: (map['line_no'] as num?)?.toInt() ?? 0,
      hsnSac: map['hsn_sac']?.toString() ?? '',
      gstRate: n(map['gst_rate']),
      taxableValue: n(map['taxable_value']),
      cgst: n(map['cgst']),
      sgst: n(map['sgst']),
      utgst: n(map['utgst']),
      igst: n(map['igst']),
      cess: n(map['cess']),
      taxAmount: n(map['tax_amount']),
    );
  }
}

class PurchaseGstRateSummary {
  final double rate;
  final double taxable;
  final double cgst;
  final double sgst;
  final double utgst;
  final double igst;
  final double cess;

  const PurchaseGstRateSummary({
    required this.rate,
    this.taxable = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.utgst = 0,
    this.igst = 0,
    this.cess = 0,
  });

  double get taxTotal => cgst + sgst + utgst + igst + cess;
  double get total => taxable + taxTotal;

  PurchaseGstRateSummary add(PurchaseGstLine line) => PurchaseGstRateSummary(
    rate: rate,
    taxable: taxable + line.taxableValue,
    cgst: cgst + line.cgst,
    sgst: sgst + line.sgst,
    utgst: utgst + line.utgst,
    igst: igst + line.igst,
    cess: cess + line.cess,
  );
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
