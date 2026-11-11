import 'dart:math';

import '../identification/identification_models.dart';
import '../scanner/scanner_models.dart';
import 'smart_inventory_session_models.dart';

/// The operation mode for goods receiving.
enum ReceivingMode {
  /// Receiving against an authorized Purchase Order (creates and posts GRN).
  purchaseOrder,

  /// Direct inventory receiving without a prior Purchase Order.
  directInward,
}

/// The delivery and fulfillment status of an individual receiving item line.
enum ReceivingItemStatus {
  /// Not yet received in this session (0 received).
  pending,

  /// Partially received (0 < received < remaining expected).
  partial,

  /// Exactly or fully received (received >= remaining expected).
  complete,

  /// Delivered quantity exceeds ordered / remaining quantity.
  excess,

  /// Delivered product was not listed on the Purchase Order.
  unexpected,
}

/// A line item within a purchase receiving session.
class PurchaseReceivingItem {
  /// Foreign key to `purchase_order_items_v480.id`, null for unexpected lines or direct inward.
  final String? purchaseOrderItemId;

  /// Foreign key to `product_variants.id`.
  final String variantId;

  /// Foreign key to `products.id`.
  final String? productId;

  /// Display product name.
  final String productName;

  /// Variant name (e.g. Size, Color, Grade).
  final String? variantName;

  /// Stock keeping unit code.
  final String sku;

  /// Primary barcode string (leading zeros strictly preserved).
  final String? barcode;

  /// Unit of measurement (e.g. PCS, KG, BAG, MTR).
  final String unitName;

  /// Total quantity originally ordered on the Purchase Order.
  final double orderedQuantity;

  /// Cumulative quantity received on prior GRNs for this PO line.
  final double previouslyReceivedQuantity;

  /// Total physical quantity received in current session:
  /// `receivedQuantity = acceptedQuantity + damagedQuantity + rejectedQuantity`
  double receivedQuantity;

  /// Quantity accepted into active sellable/usable store stock.
  double acceptedQuantity;

  /// Quantity physically damaged upon receipt.
  double damagedQuantity;

  /// Quantity rejected and returned to the supplier.
  double rejectedQuantity;

  /// Unit purchase cost.
  final double unitCost;

  /// Tracking mode: 'none', 'serial', 'batch'.
  final String trackingMode;

  /// Serial / batch tracking payload.
  final Map<String, dynamic> trackingPayload;

  /// Note explaining reason for rejected quantity.
  String? rejectionReason;

  /// Note describing condition of damaged items.
  String? damageNote;

  /// Number of scan occurrences recorded for this line.
  int scanCount;

  /// Timestamp of the most recent scan or manual entry.
  DateTime? lastScannedAt;

  PurchaseReceivingItem({
    this.purchaseOrderItemId,
    required this.variantId,
    this.productId,
    required this.productName,
    this.variantName,
    required this.sku,
    this.barcode,
    required this.unitName,
    this.orderedQuantity = 0.0,
    this.previouslyReceivedQuantity = 0.0,
    this.receivedQuantity = 0.0,
    double? acceptedQuantity,
    this.damagedQuantity = 0.0,
    this.rejectedQuantity = 0.0,
    this.unitCost = 0.0,
    this.trackingMode = 'none',
    this.trackingPayload = const {},
    this.rejectionReason,
    this.damageNote,
    this.scanCount = 0,
    this.lastScannedAt,
  }) : acceptedQuantity = acceptedQuantity ?? (receivedQuantity - (damagedQuantity + rejectedQuantity));

  /// Remaining quantity expected against the PO before this receiving session:
  /// `max(orderedQuantity - previouslyReceivedQuantity, 0)`
  double get remainingExpectedQuantity =>
      max(orderedQuantity - previouslyReceivedQuantity, 0.0);

  /// Excess quantity received beyond the remaining PO expectation.
  double get excessQuantity =>
      receivedQuantity > remainingExpectedQuantity
          ? receivedQuantity - remainingExpectedQuantity
          : 0.0;

  /// Whether the item is fully received against the remaining PO quantity.
  bool get isFullyReceived =>
      remainingExpectedQuantity > 0 && receivedQuantity >= remainingExpectedQuantity;

  /// Whether the item is partially received.
  bool get isPartiallyReceived =>
      receivedQuantity > 0 && receivedQuantity < remainingExpectedQuantity;

  /// Whether this ordered item has zero received quantity so far.
  bool get isMissing =>
      remainingExpectedQuantity > 0 && receivedQuantity == 0;

  /// Whether this item was not originally part of the Purchase Order.
  bool get isUnexpected =>
      purchaseOrderItemId == null && orderedQuantity == 0;

  /// Discrepancy indicator (anything other than exact full delivery).
  bool get hasDiscrepancy =>
      !isFullyReceived || damagedQuantity > 0 || rejectedQuantity > 0 || excessQuantity > 0;

  /// Detailed status category.
  ReceivingItemStatus get status {
    if (isUnexpected) return ReceivingItemStatus.unexpected;
    if (excessQuantity > 0.0001) return ReceivingItemStatus.excess;
    if (isFullyReceived) return ReceivingItemStatus.complete;
    if (isPartiallyReceived) return ReceivingItemStatus.partial;
    return ReceivingItemStatus.pending;
  }

  /// Increments received quantity (default step 1.0) and updates accepted balance.
  void increment([double step = 1.0]) {
    receivedQuantity += step;
    acceptedQuantity = max(receivedQuantity - damagedQuantity - rejectedQuantity, 0.0);
    scanCount += 1;
    lastScannedAt = DateTime.now();
  }

  /// Decrements received quantity, ensuring non-negative values.
  void decrement([double step = 1.0]) {
    if (receivedQuantity > step) {
      receivedQuantity -= step;
    } else {
      receivedQuantity = 0.0;
    }
    acceptedQuantity = max(receivedQuantity - damagedQuantity - rejectedQuantity, 0.0);
    lastScannedAt = DateTime.now();
  }

  /// Explicitly sets total received quantity.
  void setReceived(double quantity) {
    receivedQuantity = quantity < 0 ? 0.0 : quantity;
    acceptedQuantity = max(receivedQuantity - damagedQuantity - rejectedQuantity, 0.0);
    lastScannedAt = DateTime.now();
  }

  /// Records damaged quantity with optional inspection note.
  void setDamaged(double quantity, [String? note]) {
    damagedQuantity = quantity < 0 ? 0.0 : quantity;
    damageNote = note;
    acceptedQuantity = max(receivedQuantity - damagedQuantity - rejectedQuantity, 0.0);
    lastScannedAt = DateTime.now();
  }

  /// Records rejected quantity with required rejection reason.
  void setRejected(double quantity, [String? reason]) {
    rejectedQuantity = quantity < 0 ? 0.0 : quantity;
    rejectionReason = reason;
    acceptedQuantity = max(receivedQuantity - damagedQuantity - rejectedQuantity, 0.0);
    lastScannedAt = DateTime.now();
  }

  /// Quickly fills received quantity to match remaining expected PO quantity.
  void matchRemaining() {
    receivedQuantity = remainingExpectedQuantity;
    acceptedQuantity = max(receivedQuantity - damagedQuantity - rejectedQuantity, 0.0);
    lastScannedAt = DateTime.now();
  }

  /// Constructs a line item from a PO line map returned by `purchase_order_detail_v484`.
  factory PurchaseReceivingItem.fromPoItemMap(Map<String, dynamic> map) {
    final ordered = ((map['quantity'] ?? map['ordered_quantity']) as num?)?.toDouble() ?? 0.0;
    final previouslyReceived = (map['received_quantity'] as num?)?.toDouble() ?? 0.0;

    return PurchaseReceivingItem(
      purchaseOrderItemId: map['id']?.toString(),
      variantId: map['variant_id']?.toString() ?? '',
      productId: map['product_id']?.toString(),
      productName: map['product_name']?.toString() ?? 'Product',
      variantName: map['variant_name']?.toString(),
      sku: map['sku']?.toString() ?? '',
      barcode: map['barcode']?.toString(),
      unitName: map['unit_name']?.toString() ?? 'PCS',
      orderedQuantity: ordered,
      previouslyReceivedQuantity: previouslyReceived,
      receivedQuantity: 0.0,
      unitCost: (map['unit_cost'] as num?)?.toDouble() ?? 0.0,
      trackingMode: map['tracking_mode']?.toString() ?? 'none',
    );
  }

  /// Formats line for `public.goods_receipt_create_v484` JSON payload.
  Map<String, dynamic> toGrnItemMap() => {
        'purchase_order_item_id': purchaseOrderItemId,
        'received_quantity': receivedQuantity,
        'accepted_quantity': acceptedQuantity,
        'damaged_quantity': damagedQuantity,
        'rejected_quantity': rejectedQuantity,
        if (damageNote != null && damageNote!.trim().isNotEmpty)
          'damage_note': damageNote!.trim(),
        if (rejectionReason != null && rejectionReason!.trim().isNotEmpty)
          'rejection_reason': rejectionReason!.trim(),
        if (trackingMode != 'none' && trackingPayload.isNotEmpty)
          'tracking': trackingPayload,
      };

  /// Formats line for direct purchase receiving (`PurchaseService.createPurchase`).
  Map<String, dynamic> toDirectInwardItemMap() => {
        'variant_id': variantId,
        'quantity': acceptedQuantity + damagedQuantity,
        'unit_cost': unitCost,
        'tax_rate': 0.0,
        if (damageNote != null && damageNote!.trim().isNotEmpty)
          'damage_note': damageNote!.trim(),
        if (trackingMode != 'none' && trackingPayload.isNotEmpty)
          'tracking': trackingPayload,
      };
}

/// Aggregated metrics and discrepancy summary for a receiving session.
class PurchaseReceivingSummary {
  final int totalOrderedLines;
  final int totalReceivedLines;
  final int fullyReceivedLines;
  final int partiallyReceivedLines;
  final int missingLines;
  final int excessLines;
  final int unexpectedLines;
  final double totalOrderedQuantity;
  final double totalReceivedQuantity;
  final double totalAcceptedQuantity;
  final double totalDamagedQuantity;
  final double totalRejectedQuantity;
  final int unresolvedScanCount;
  final double completionPercentage;

  const PurchaseReceivingSummary({
    required this.totalOrderedLines,
    required this.totalReceivedLines,
    required this.fullyReceivedLines,
    required this.partiallyReceivedLines,
    required this.missingLines,
    required this.excessLines,
    required this.unexpectedLines,
    required this.totalOrderedQuantity,
    required this.totalReceivedQuantity,
    required this.totalAcceptedQuantity,
    required this.totalDamagedQuantity,
    required this.totalRejectedQuantity,
    required this.unresolvedScanCount,
    required this.completionPercentage,
  });

  factory PurchaseReceivingSummary.fromItems(
    List<PurchaseReceivingItem> items, {
    int unresolvedCount = 0,
  }) {
    int orderedLines = 0;
    int receivedLines = 0;
    int fullyReceived = 0;
    int partiallyReceived = 0;
    int missing = 0;
    int excess = 0;
    int unexpected = 0;

    double totalOrdered = 0.0;
    double totalReceived = 0.0;
    double totalAccepted = 0.0;
    double totalDamaged = 0.0;
    double totalRejected = 0.0;

    for (final item in items) {
      if (item.orderedQuantity > 0) {
        orderedLines++;
        totalOrdered += item.remainingExpectedQuantity;
      }
      if (item.receivedQuantity > 0) {
        receivedLines++;
      }

      totalReceived += item.receivedQuantity;
      totalAccepted += item.acceptedQuantity;
      totalDamaged += item.damagedQuantity;
      totalRejected += item.rejectedQuantity;

      switch (item.status) {
        case ReceivingItemStatus.complete:
          fullyReceived++;
        case ReceivingItemStatus.partial:
          partiallyReceived++;
        case ReceivingItemStatus.excess:
          excess++;
        case ReceivingItemStatus.unexpected:
          unexpected++;
        case ReceivingItemStatus.pending:
          if (item.remainingExpectedQuantity > 0) {
            missing++;
          }
      }
    }

    final pct = totalOrdered > 0 ? (totalReceived / totalOrdered) * 100.0 : 0.0;

    return PurchaseReceivingSummary(
      totalOrderedLines: orderedLines,
      totalReceivedLines: receivedLines,
      fullyReceivedLines: fullyReceived,
      partiallyReceivedLines: partiallyReceived,
      missingLines: missing,
      excessLines: excess,
      unexpectedLines: unexpected,
      totalOrderedQuantity: totalOrdered,
      totalReceivedQuantity: totalReceived,
      totalAcceptedQuantity: totalAccepted,
      totalDamagedQuantity: totalDamaged,
      totalRejectedQuantity: totalRejected,
      unresolvedScanCount: unresolvedCount,
      completionPercentage: pct,
    );
  }
}

/// Active goods receiving session container.
class PurchaseReceivingSession {
  final String id;
  final String sessionName;
  final String tenantId;
  final String locationId;
  final String locationName;
  final String supplierId;
  final String supplierName;
  final ReceivingMode mode;
  final String? purchaseOrderId;
  final String? purchaseOrderNumber;
  String? supplierDeliveryNote;
  DateTime receiptDate;
  String? notes;
  final String requestId;
  final List<PurchaseReceivingItem> items;
  final List<UnresolvedScanItem> unresolvedScans;
  final DateTime createdAt;

  PurchaseReceivingSession({
    required this.id,
    required this.sessionName,
    required this.tenantId,
    required this.locationId,
    required this.locationName,
    required this.supplierId,
    required this.supplierName,
    this.mode = ReceivingMode.purchaseOrder,
    this.purchaseOrderId,
    this.purchaseOrderNumber,
    this.supplierDeliveryNote,
    DateTime? receiptDate,
    this.notes,
    required this.requestId,
    List<PurchaseReceivingItem>? items,
    List<UnresolvedScanItem>? unresolvedScans,
    DateTime? createdAt,
  })  : receiptDate = receiptDate ?? DateTime.now(),
        items = items ?? [],
        unresolvedScans = unresolvedScans ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// Calculates real-time session summary metrics.
  PurchaseReceivingSummary get summary => PurchaseReceivingSummary.fromItems(
        items,
        unresolvedCount: unresolvedScans.length,
      );

  /// Fast lookup map by variantId.
  Map<String, PurchaseReceivingItem> get itemsByVariantId => {
        for (final item in items) item.variantId: item,
      };

  /// Records a successful product scan match and increments quantity.
  bool recordScanMatch(ProductIdentificationMatch match, [double quantity = 1.0]) {
    // 1. Check if the matched product exists in the session items
    for (final item in items) {
      if (item.variantId == match.variantId) {
        item.increment(quantity);
        return true;
      }
    }

    // 2. Product is not in the PO list: treat as unexpected delivery
    final unexpectedItem = PurchaseReceivingItem(
      purchaseOrderItemId: null, // Not on the PO
      variantId: match.variantId,
      productId: match.productId,
      productName: match.productName,
      variantName: match.variantName,
      sku: match.sku,
      barcode: match.barcode,
      unitName: match.unitCode,
      orderedQuantity: 0.0,
      previouslyReceivedQuantity: 0.0,
      receivedQuantity: quantity,
      acceptedQuantity: quantity,
      unitCost: match.sellingPrice > 0 ? match.sellingPrice * 0.7 : 0.0,
      scanCount: 1,
      lastScannedAt: DateTime.now(),
    );
    items.add(unexpectedItem);
    return true;
  }

  /// Records an unresolvable barcode scan in the session audit list.
  void recordUnresolvedScan(String rawCode, ScannerSource source, [String? note]) {
    unresolvedScans.insert(
      0,
      UnresolvedScanItem(
        id: 'unres-rcv-${DateTime.now().microsecondsSinceEpoch}',
        rawCode: rawCode.trim(),
        source: source,
        scannedAt: DateTime.now(),
        note: note,
      ),
    );
  }

  /// Formats all PO items with `receivedQuantity > 0` for `goods_receipt_create_v484`.
  List<Map<String, dynamic>> toGrnPayload() {
    return items
        .where((i) => i.purchaseOrderItemId != null && i.receivedQuantity > 0)
        .map((i) => i.toGrnItemMap())
        .toList();
  }
}

/// Lightweight summary model representing an open Purchase Order eligible for goods receiving.
class PurchaseOrderSummaryRecord {
  final String id;
  final String orderNumber;
  final DateTime orderDate;
  final DateTime? expectedDate;
  final String status;
  final String supplierId;
  final String supplierName;
  final String locationId;
  final String locationName;
  final int itemCount;
  final double orderedQuantity;
  final double receivedQuantity;
  final double remainingReceiveQuantity;
  final double grandTotal;

  const PurchaseOrderSummaryRecord({
    required this.id,
    required this.orderNumber,
    required this.orderDate,
    this.expectedDate,
    required this.status,
    required this.supplierId,
    required this.supplierName,
    required this.locationId,
    required this.locationName,
    required this.itemCount,
    required this.orderedQuantity,
    required this.receivedQuantity,
    required this.remainingReceiveQuantity,
    required this.grandTotal,
  });

  factory PurchaseOrderSummaryRecord.fromRpcMap(Map<String, dynamic> map) {
    return PurchaseOrderSummaryRecord(
      id: map['id']?.toString() ?? '',
      orderNumber: map['order_number']?.toString() ?? '',
      orderDate: DateTime.tryParse(map['order_date']?.toString() ?? '') ?? DateTime.now(),
      expectedDate: map['expected_date'] != null
          ? DateTime.tryParse(map['expected_date'].toString())
          : null,
      status: map['status']?.toString() ?? 'approved',
      supplierId: map['supplier_id']?.toString() ?? '',
      supplierName: map['supplier_name']?.toString() ?? 'Unknown Supplier',
      locationId: map['location_id']?.toString() ?? '',
      locationName: map['location_name']?.toString() ?? 'Store Location',
      itemCount: (map['item_count'] as num?)?.toInt() ?? 0,
      orderedQuantity: (map['ordered_quantity'] as num?)?.toDouble() ?? 0.0,
      receivedQuantity: (map['received_quantity'] as num?)?.toDouble() ?? 0.0,
      remainingReceiveQuantity: (map['remaining_receive_quantity'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (map['grand_total'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Historical Goods Receipt Note (GRN) audit record parsed from `public.goods_receipt_list_v484`.
class GoodsReceiptSummaryRecord {
  final String id;
  final String grnNumber;
  final DateTime receiptDate;
  final String status;
  final String purchaseOrderId;
  final String orderNumber;
  final String supplierId;
  final String supplierName;
  final String locationId;
  final String locationName;
  final int lineCount;
  final double receivedQuantity;
  final double acceptedQuantity;
  final double damagedQuantity;
  final double rejectedQuantity;
  final DateTime createdAt;

  const GoodsReceiptSummaryRecord({
    required this.id,
    required this.grnNumber,
    required this.receiptDate,
    required this.status,
    required this.purchaseOrderId,
    required this.orderNumber,
    required this.supplierId,
    required this.supplierName,
    required this.locationId,
    required this.locationName,
    required this.lineCount,
    required this.receivedQuantity,
    required this.acceptedQuantity,
    required this.damagedQuantity,
    required this.rejectedQuantity,
    required this.createdAt,
  });

  factory GoodsReceiptSummaryRecord.fromRpcMap(Map<String, dynamic> map) {
    return GoodsReceiptSummaryRecord(
      id: map['id']?.toString() ?? '',
      grnNumber: map['grn_number']?.toString() ?? '',
      receiptDate: DateTime.tryParse(map['receipt_date']?.toString() ?? '') ?? DateTime.now(),
      status: map['status']?.toString() ?? 'draft',
      purchaseOrderId: map['purchase_order_id']?.toString() ?? '',
      orderNumber: map['order_number']?.toString() ?? '',
      supplierId: map['supplier_id']?.toString() ?? '',
      supplierName: map['supplier_name']?.toString() ?? '',
      locationId: map['location_id']?.toString() ?? '',
      locationName: map['location_name']?.toString() ?? '',
      lineCount: (map['line_count'] as num?)?.toInt() ?? 0,
      receivedQuantity: ((map['received_quantity'] ?? map['total_received_quantity']) as num?)?.toDouble() ?? 0.0,
      acceptedQuantity: ((map['accepted_quantity'] ?? map['total_accepted_quantity']) as num?)?.toDouble() ?? 0.0,
      damagedQuantity: ((map['damaged_quantity'] ?? map['total_damaged_quantity']) as num?)?.toDouble() ?? 0.0,
      rejectedQuantity: ((map['rejected_quantity'] ?? map['total_rejected_quantity']) as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
