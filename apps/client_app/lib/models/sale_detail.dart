class SaleDetail {
  final String saleId;
  final String saleNumber;
  final String customerId;
  final String customerName;
  final String? customerTaxNumber;
  final String? customerPhone;
  final String? customerEmail;
  final String? customerAddress;
  final DateTime saleDate;
  final DateTime? dueDate;
  final String status;
  final double subtotal;
  final double discountTotal;
  final double taxableTotal;
  final double taxTotal;
  final double additionalCharges;
  final double grandTotal;
  final double costTotal;
  final double grossProfit;
  final String? notes;
  final DateTime? createdAt;
  final List<SaleDetailItem> items;
  final List<SalePayment> payments;
  final double paidAmount;
  final double balanceDue;
  final SaleGstDetail? gst;

  const SaleDetail({
    required this.saleId,
    required this.saleNumber,
    required this.customerId,
    required this.customerName,
    required this.customerTaxNumber,
    required this.customerPhone,
    required this.customerEmail,
    required this.customerAddress,
    required this.saleDate,
    required this.dueDate,
    required this.status,
    required this.subtotal,
    required this.discountTotal,
    required this.taxableTotal,
    required this.taxTotal,
    required this.additionalCharges,
    required this.grandTotal,
    required this.costTotal,
    required this.grossProfit,
    required this.notes,
    required this.createdAt,
    required this.items,
    required this.payments,
    required this.paidAmount,
    required this.balanceDue,
    this.gst,
  });

  String get paymentStatus =>
      balanceDue <= 0.0001 ? 'paid' : (paidAmount > 0 ? 'partial' : 'unpaid');

  factory SaleDetail.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    final rawSale = map['sale'];
    if (rawSale is! Map) throw Exception('Invalid sale detail response.');
    final sale = Map<String, dynamic>.from(rawSale);
    final itemsRaw = map['items'] as List? ?? const [];
    final paymentsRaw = map['payments'] as List? ?? const [];
    return SaleDetail(
      saleId: sale['sale_id']?.toString() ?? '',
      saleNumber: sale['sale_number']?.toString() ?? '',
      customerId: sale['customer_id']?.toString() ?? '',
      customerName: sale['customer_name']?.toString() ?? '',
      customerTaxNumber: sale['customer_tax_number']?.toString(),
      customerPhone: sale['customer_phone']?.toString(),
      customerEmail: sale['customer_email']?.toString(),
      customerAddress:
          [
                sale['customer_address_line1'],
                sale['customer_address_line2'],
                sale['customer_city'],
                sale['customer_state'],
                sale['customer_postal_code'],
                sale['customer_country'],
              ]
              .where(
                (value) => value != null && value.toString().trim().isNotEmpty,
              )
              .map((value) => value.toString().trim())
              .join(', '),
      saleDate: DateTime.parse(sale['sale_date'].toString()),
      dueDate: sale['due_date'] == null
          ? null
          : DateTime.tryParse(sale['due_date'].toString()),
      status: sale['status']?.toString() ?? '',
      subtotal: n(sale['subtotal']),
      discountTotal: n(sale['discount_total']),
      taxableTotal: n(sale['taxable_total']),
      taxTotal: n(sale['tax_total']),
      additionalCharges: n(sale['additional_charges']),
      grandTotal: n(sale['grand_total']),
      costTotal: n(sale['cost_total']),
      grossProfit: n(sale['gross_profit']),
      notes: sale['notes']?.toString(),
      createdAt: DateTime.tryParse(sale['created_at']?.toString() ?? ''),
      items: itemsRaw
          .map(
            (e) => SaleDetailItem.fromMap(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      payments: paymentsRaw
          .map((e) => SalePayment.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      paidAmount: n(map['paid_amount']),
      balanceDue: n(map['balance_due']),
      gst: map['gst'] is Map
          ? SaleGstDetail.fromMap(Map<String, dynamic>.from(map['gst'] as Map))
          : null,
    );
  }
}

class SaleGstDetail {
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
  final List<SaleGstLine> lines;

  const SaleGstDetail({
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
      cgstTotal.abs() > 0.0001 ||
      sgstTotal.abs() > 0.0001 ||
      utgstTotal.abs() > 0.0001 ||
      igstTotal.abs() > 0.0001 ||
      cessTotal.abs() > 0.0001;

  List<SaleGstRateSummary> get rateSummaries {
    final grouped = <String, SaleGstRateSummary>{};
    for (final line in lines) {
      final key = line.gstRate.toStringAsFixed(4);
      grouped[key] = (grouped[key] ?? SaleGstRateSummary(rate: line.gstRate))
          .add(line);
    }
    final rows = grouped.values.toList()
      ..sort((a, b) => a.rate.compareTo(b.rate));
    return rows;
  }

  factory SaleGstDetail.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return SaleGstDetail(
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
          .map((row) => SaleGstLine.fromMap(Map<String, dynamic>.from(row)))
          .toList(growable: false),
    );
  }
}

class SaleGstLine {
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

  const SaleGstLine({
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

  factory SaleGstLine.fromMap(Map<String, dynamic> map) {
    double n(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return SaleGstLine(
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

class SaleGstRateSummary {
  final double rate;
  final double taxable;
  final double cgst;
  final double sgst;
  final double utgst;
  final double igst;
  final double cess;

  const SaleGstRateSummary({
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

  SaleGstRateSummary add(SaleGstLine line) => SaleGstRateSummary(
    rate: rate,
    taxable: taxable + line.taxableValue,
    cgst: cgst + line.cgst,
    sgst: sgst + line.sgst,
    utgst: utgst + line.utgst,
    igst: igst + line.igst,
    cess: cess + line.cess,
  );
}

class SaleDetailItem {
  final String itemId;
  final String variantId;
  final String productName;
  final String sku;
  final String? partNumber;
  final String? unitCode;
  final String? hsnSac;
  final double quantity;
  final double unitPrice;
  final double discountAmount;
  final double taxRate;
  final double subtotal;
  final double taxableAmount;
  final double taxAmount;
  final double lineTotal;
  final double unitCost;
  final double costTotal;
  final double grossProfit;

  const SaleDetailItem({
    required this.itemId,
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.partNumber,
    required this.unitCode,
    required this.hsnSac,
    required this.quantity,
    required this.unitPrice,
    required this.discountAmount,
    required this.taxRate,
    required this.subtotal,
    required this.taxableAmount,
    required this.taxAmount,
    required this.lineTotal,
    required this.unitCost,
    required this.costTotal,
    required this.grossProfit,
  });

  factory SaleDetailItem.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return SaleDetailItem(
      itemId: map['item_id']?.toString() ?? '',
      variantId: map['variant_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      partNumber: map['part_number']?.toString(),
      unitCode: map['unit_code']?.toString(),
      hsnSac: map['hsn_sac']?.toString(),
      quantity: n(map['quantity']),
      unitPrice: n(map['unit_price']),
      discountAmount: n(map['discount_amount']),
      taxRate: n(map['tax_rate']),
      subtotal: n(map['subtotal']),
      taxableAmount: n(map['taxable_amount']),
      taxAmount: n(map['tax_amount']),
      lineTotal: n(map['line_total']),
      unitCost: n(
        map['unit_cost'] ?? map['unit_cost_snapshot'] ?? map['cost_price'],
      ),
      costTotal: n(map['cost_total']),
      grossProfit: n(map['gross_profit']),
    );
  }
}

class SalePayment {
  final String paymentId;
  final double amount;
  final String paymentMethod;
  final String? referenceNumber;
  final String? notes;
  final DateTime? paidAt;

  const SalePayment({
    required this.paymentId,
    required this.amount,
    required this.paymentMethod,
    required this.referenceNumber,
    required this.notes,
    required this.paidAt,
  });

  factory SalePayment.fromMap(Map<String, dynamic> map) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return SalePayment(
      paymentId: map['payment_id']?.toString() ?? '',
      amount: n(map['amount']),
      paymentMethod: map['payment_method']?.toString() ?? '',
      referenceNumber:
          (map['reference_number'] ??
                  map['payment_reference'] ??
                  map['reference'])
              ?.toString(),
      notes: map['notes']?.toString(),
      paidAt: DateTime.tryParse(map['paid_at']?.toString() ?? ''),
    );
  }
}
