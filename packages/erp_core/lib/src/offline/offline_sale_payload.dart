/// Unified offline sale payload structures used across Desktop POS and Mobile POS.
library;

/// Helper to safely parse numeric values from dynamic objects.
double _toDouble(dynamic value, [double fallback = 0.0]) {
  if (value is num) return value.toDouble();
  if (value == null) return fallback;
  return double.tryParse(value.toString()) ?? fallback;
}

/// A line item within an offline sale transaction.
class OfflineSaleItem {
  final String variantId;
  final String productName;
  final String sku;
  final double quantity;
  final double baseQuantity;
  final double conversionToBase;
  final String? unitId;
  final String unitCode;
  final double unitPrice;
  final double taxRate;
  final double taxAmount;
  final double discountAmount;
  final double lineTotal;
  final List<String> serialNumbers;
  final String pricingSource;
  final String trackingMode;
  final int trackingRevision;

  const OfflineSaleItem({
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.quantity,
    required this.baseQuantity,
    this.conversionToBase = 1.0,
    this.unitId,
    this.unitCode = 'PCS',
    required this.unitPrice,
    this.taxRate = 0.0,
    this.taxAmount = 0.0,
    this.discountAmount = 0.0,
    this.lineTotal = 0.0,
    this.serialNumbers = const <String>[],
    this.pricingSource = 'cached',
    this.trackingMode = 'none',
    this.trackingRevision = 0,
  });

  factory OfflineSaleItem.fromMap(Map<String, dynamic> map) {
    final qty = _toDouble(map['quantity']);
    final conv = _toDouble(map['conversion_to_base'], 1.0);
    final baseQty = _toDouble(map['base_quantity'], qty * conv);
    final price = _toDouble(map['unit_price']);
    final rate = _toDouble(map['tax_rate']);
    final discount = _toDouble(map['discount_amount']);
    final taxable = (qty * price) - discount;
    final calculatedTax = _toDouble(map['tax_amount'], taxable * (rate / 100.0));
    final calculatedTotal = _toDouble(map['line_total'], taxable + calculatedTax);

    final rawSerials = map['serial_numbers'];
    final serials = rawSerials is List
        ? rawSerials.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
        : const <String>[];

    return OfflineSaleItem(
      variantId: map['variant_id']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      sku: map['sku']?.toString() ?? '',
      quantity: qty,
      baseQuantity: baseQty,
      conversionToBase: conv,
      unitId: map['unit_id']?.toString(),
      unitCode: map['unit_code']?.toString() ?? 'PCS',
      unitPrice: price,
      taxRate: rate,
      taxAmount: calculatedTax,
      discountAmount: discount,
      lineTotal: calculatedTotal,
      serialNumbers: serials,
      pricingSource: map['pricing_source']?.toString() ?? 'cached',
      trackingMode: map['tracking_mode']?.toString() ?? 'none',
      trackingRevision: _toDouble(map['tracking_revision']).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'variant_id': variantId,
        'product_name': productName,
        'sku': sku,
        'quantity': quantity,
        'base_quantity': baseQuantity,
        'conversion_to_base': conversionToBase,
        if (unitId != null && unitId!.isNotEmpty) 'unit_id': unitId,
        'unit_code': unitCode,
        'unit_price': unitPrice,
        'tax_rate': taxRate,
        'tax_amount': taxAmount,
        'discount_amount': discountAmount,
        'line_total': lineTotal,
        'serial_numbers': serialNumbers,
        'pricing_source': pricingSource,
        'tracking_mode': trackingMode,
        'tracking_revision': trackingRevision,
      };
}

/// A payment method allocation within an offline sale.
class OfflineSalePayment {
  final String methodCode;
  final double amount;
  final String? reference;

  const OfflineSalePayment({
    required this.methodCode,
    required this.amount,
    this.reference,
  });

  factory OfflineSalePayment.fromMap(Map<String, dynamic> map) {
    return OfflineSalePayment(
      methodCode: (map['method_code'] ?? map['payment_method'] ?? 'cash').toString(),
      amount: _toDouble(map['amount'] ?? map['paid_amount']),
      reference: (map['reference'] ?? map['payment_reference'])?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'method_code': methodCode,
        'amount': amount,
        if (reference != null && reference!.isNotEmpty) 'reference': reference,
      };
}

/// Complete typed offline sale payload.
class OfflineSalePayload {
  final String requestId;
  final String localInvoiceNumber;
  final String tenantId;
  final String locationId;
  final String deviceId;
  final String? shiftId;
  final String? cashierId;
  final String customerId;
  final String customerName;
  final String saleDate;
  final String saleTime;
  final String? dueDate;
  final List<OfflineSaleItem> items;
  final List<OfflineSalePayment> paymentAllocations;
  final double total;
  final double outstanding;
  final double discountAmount;
  final double roundOff;
  final String notes;
  final String channel;

  const OfflineSalePayload({
    required this.requestId,
    required this.localInvoiceNumber,
    required this.tenantId,
    required this.locationId,
    required this.deviceId,
    this.shiftId,
    this.cashierId,
    required this.customerId,
    required this.customerName,
    required this.saleDate,
    required this.saleTime,
    this.dueDate,
    required this.items,
    required this.paymentAllocations,
    required this.total,
    required this.outstanding,
    this.discountAmount = 0.0,
    this.roundOff = 0.0,
    this.notes = '',
    required this.channel,
  });

  factory OfflineSalePayload.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List? ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map((m) => OfflineSaleItem.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    final rawPayments = (map['payment_allocations'] ?? map['payments']) as List? ?? const [];
    final payments = rawPayments
        .whereType<Map>()
        .map((m) => OfflineSalePayment.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    return OfflineSalePayload(
      requestId: map['request_id']?.toString() ?? '',
      localInvoiceNumber: (map['local_invoice_number'] ?? map['local_number'])?.toString() ?? '',
      tenantId: map['tenant_id']?.toString() ?? '',
      locationId: map['location_id']?.toString() ?? '',
      deviceId: map['device_id']?.toString() ?? '',
      shiftId: map['shift_id']?.toString(),
      cashierId: map['cashier_id']?.toString(),
      customerId: map['customer_id']?.toString() ?? '',
      customerName: map['customer_name']?.toString() ?? '',
      saleDate: map['sale_date']?.toString() ?? '',
      saleTime: map['sale_time']?.toString() ?? '',
      dueDate: map['due_date']?.toString(),
      items: items,
      paymentAllocations: payments,
      total: _toDouble(map['total']),
      outstanding: _toDouble(map['outstanding']),
      discountAmount: _toDouble(map['discount_amount']),
      roundOff: _toDouble(map['round_off']),
      notes: map['notes']?.toString() ?? '',
      channel: map['channel']?.toString() ?? 'pos_offline',
    );
  }

  Map<String, dynamic> toMap() => {
        'request_id': requestId,
        'local_invoice_number': localInvoiceNumber,
        'tenant_id': tenantId,
        'location_id': locationId,
        'device_id': deviceId,
        if (shiftId != null) 'shift_id': shiftId,
        if (cashierId != null) 'cashier_id': cashierId,
        'customer_id': customerId,
        'customer_name': customerName,
        'sale_date': saleDate,
        'sale_time': saleTime,
        if (dueDate != null) 'due_date': dueDate,
        'items': items.map((i) => i.toMap()).toList(),
        'payment_allocations': paymentAllocations.map((p) => p.toMap()).toList(),
        'total': total,
        'outstanding': outstanding,
        'discount_amount': discountAmount,
        'round_off': roundOff,
        'notes': notes,
        'channel': channel,
      };
}
