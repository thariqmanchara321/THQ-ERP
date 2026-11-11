import '../identification/identification_models.dart';
import '../scanner/scanner_models.dart';
import 'smart_inventory_session_models.dart';

/// Status of a physical stock count session.
enum StockCountStatus {
  draft,
  inProgress,
  review,
  posted,
  cancelled;

  static StockCountStatus fromString(String val) => switch (val.toLowerCase()) {
        'draft' => StockCountStatus.draft,
        'in_progress' || 'inprogress' => StockCountStatus.inProgress,
        'review' => StockCountStatus.review,
        'posted' => StockCountStatus.posted,
        'cancelled' => StockCountStatus.cancelled,
        _ => StockCountStatus.draft,
      };

  String get label => switch (this) {
        StockCountStatus.draft => 'Draft',
        StockCountStatus.inProgress => 'In Progress',
        StockCountStatus.review => 'Under Review',
        StockCountStatus.posted => 'Posted & Reconciled',
        StockCountStatus.cancelled => 'Cancelled',
      };
}

/// Variance classification for a counted product variant.
enum StockCountVarianceType {
  matched,
  shortage,
  excess,
  notCounted;

  String get label => switch (this) {
        StockCountVarianceType.matched => 'Matched',
        StockCountVarianceType.shortage => 'Shortage',
        StockCountVarianceType.excess => 'Excess',
        StockCountVarianceType.notCounted => 'Not Counted',
      };
}

/// An individual product variant line item within a physical stock count.
class StockCountItem {
  final String variantId;
  final String? productId;
  final String productName;
  final String? variantName;
  final String sku;
  final String? barcode;
  final String unitName;
  final double systemQuantity;
  double countedQuantity;
  final String trackingMode;
  final Map<String, dynamic> trackingPayload;
  final double reservedQuantity;
  final double damagedQuantity;
  final double quarantineQuantity;
  bool isCounted;
  int scanCount;
  DateTime? lastScannedAt;
  String? reconciliationNote;

  StockCountItem({
    required this.variantId,
    this.productId,
    required this.productName,
    this.variantName,
    required this.sku,
    this.barcode,
    this.unitName = 'PCS',
    required this.systemQuantity,
    this.countedQuantity = 0.0,
    this.trackingMode = 'none',
    this.trackingPayload = const {},
    this.reservedQuantity = 0.0,
    this.damagedQuantity = 0.0,
    this.quarantineQuantity = 0.0,
    this.isCounted = false,
    this.scanCount = 0,
    this.lastScannedAt,
    this.reconciliationNote,
  });

  /// Variance between physical count and system snapshot:
  /// `Variance = Counted Quantity - System Quantity`
  double get variance => countedQuantity - systemQuantity;

  /// Absolute variance amount.
  double get absoluteVariance => (countedQuantity - systemQuantity).abs();

  /// Whether the item has a non-zero variance.
  bool get hasVariance => (countedQuantity - systemQuantity).abs() > 0.0001;

  /// Variance classification.
  StockCountVarianceType get varianceType {
    if (!isCounted) return StockCountVarianceType.notCounted;
    final diff = countedQuantity - systemQuantity;
    if (diff.abs() <= 0.0001) return StockCountVarianceType.matched;
    if (diff < 0) return StockCountVarianceType.shortage;
    return StockCountVarianceType.excess;
  }

  /// Increments counted quantity (e.g. from a barcode scan).
  void increment([double step = 1.0]) {
    countedQuantity += step;
    scanCount += 1;
    isCounted = true;
    lastScannedAt = DateTime.now();
  }

  /// Decrements counted quantity, clamped to 0.
  void decrement([double step = 1.0]) {
    if (countedQuantity > step) {
      countedQuantity -= step;
    } else {
      countedQuantity = 0.0;
    }
    isCounted = true;
    lastScannedAt = DateTime.now();
  }

  /// Explicitly sets counted quantity.
  void setCounted(double quantity) {
    countedQuantity = quantity < 0 ? 0.0 : quantity;
    isCounted = true;
    lastScannedAt = DateTime.now();
  }

  /// Constructs a StockCountItem directly from the `inventory_stock_count_snapshot_v485` RPC record.
  factory StockCountItem.fromSnapshotMap(Map<String, dynamic> map) {
    return StockCountItem(
      variantId: map['variant_id']?.toString() ?? '',
      productId: map['product_id']?.toString(),
      productName: map['product_name']?.toString() ?? 'Unknown Product',
      variantName: map['variant_name']?.toString(),
      sku: map['sku']?.toString() ?? '',
      barcode: map['barcode']?.toString(),
      unitName: map['unit_name']?.toString() ?? 'PCS',
      systemQuantity: (map['system_quantity'] as num?)?.toDouble() ?? 0.0,
      countedQuantity: 0.0,
      trackingMode: map['tracking_mode']?.toString() ?? 'none',
      trackingPayload: map['tracking'] is Map ? Map<String, dynamic>.from(map['tracking']) : const {},
      reservedQuantity: (map['reserved_quantity'] as num?)?.toDouble() ?? 0.0,
      damagedQuantity: (map['damaged_quantity'] as num?)?.toDouble() ?? 0.0,
      quarantineQuantity: (map['quarantine_quantity'] as num?)?.toDouble() ?? 0.0,
      isCounted: false,
    );
  }

  /// Formats line for `inventory_stock_count_post_v485` JSON parameter.
  Map<String, dynamic> toPostItemMap() => {
        'variant_id': variantId,
        'counted_quantity': countedQuantity,
        if (trackingMode != 'none' && trackingPayload.isNotEmpty)
          'tracking': trackingPayload,
      };

  Map<String, dynamic> toMap() => {
        'variant_id': variantId,
        'product_id': productId,
        'product_name': productName,
        'variant_name': variantName,
        'sku': sku,
        'barcode': barcode,
        'unit_name': unitName,
        'system_quantity': systemQuantity,
        'counted_quantity': countedQuantity,
        'variance': variance,
        'tracking_mode': trackingMode,
        'tracking_payload': trackingPayload,
        'reserved_quantity': reservedQuantity,
        'damaged_quantity': damagedQuantity,
        'quarantine_quantity': quarantineQuantity,
        'is_counted': isCounted,
        'scan_count': scanCount,
        'last_scanned_at': lastScannedAt?.toIso8601String(),
        'reconciliation_note': reconciliationNote,
      };
}

/// Calculated metrics and progress summary for an active or completed stock count.
class StockCountSummary {
  final int totalItems;
  final int countedItems;
  final int uncountedItems;
  final int matchedItems;
  final int shortageItems;
  final int excessItems;
  final int unresolvedCount;
  final double totalSystemQuantity;
  final double totalCountedQuantity;
  final double netVarianceQuantity;
  final double completionPercentage;

  const StockCountSummary({
    required this.totalItems,
    required this.countedItems,
    required this.uncountedItems,
    required this.matchedItems,
    required this.shortageItems,
    required this.excessItems,
    required this.unresolvedCount,
    required this.totalSystemQuantity,
    required this.totalCountedQuantity,
    required this.netVarianceQuantity,
    required this.completionPercentage,
  });

  factory StockCountSummary.fromItems(
    List<StockCountItem> items, {
    int unresolvedCount = 0,
  }) {
    final total = items.length;
    var counted = 0;
    var matched = 0;
    var shortage = 0;
    var excess = 0;
    var sysTotal = 0.0;
    var cntTotal = 0.0;

    for (final item in items) {
      sysTotal += item.systemQuantity;
      if (item.isCounted) {
        counted++;
        cntTotal += item.countedQuantity;
        final v = item.variance;
        if (v.abs() <= 0.0001) {
          matched++;
        } else if (v < 0) {
          shortage++;
        } else {
          excess++;
        }
      }
    }

    final uncounted = total - counted;
    final pct = total > 0 ? (counted / total) * 100.0 : 0.0;

    return StockCountSummary(
      totalItems: total,
      countedItems: counted,
      uncountedItems: uncounted,
      matchedItems: matched,
      shortageItems: shortage,
      excessItems: excess,
      unresolvedCount: unresolvedCount,
      totalSystemQuantity: sysTotal,
      totalCountedQuantity: cntTotal,
      netVarianceQuantity: cntTotal - sysTotal,
      completionPercentage: pct,
    );
  }
}

/// Complete physical stock count session container.
class StockCountSession {
  final String id;
  String countNumber;
  final String tenantId;
  final String locationId;
  final String locationName;
  final String sessionName;
  StockCountStatus status;
  String? notes;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  String? postedBy;
  DateTime? postedAt;
  final String requestId;
  final List<StockCountItem> items;
  final List<UnresolvedScanItem> unresolvedScans;

  StockCountSession({
    required this.id,
    required this.countNumber,
    required this.tenantId,
    required this.locationId,
    required this.locationName,
    required this.sessionName,
    this.status = StockCountStatus.inProgress,
    this.notes,
    this.createdBy,
    this.createdByName,
    DateTime? createdAt,
    this.postedBy,
    this.postedAt,
    required this.requestId,
    List<StockCountItem>? items,
    List<UnresolvedScanItem>? unresolvedScans,
  })  : createdAt = createdAt ?? DateTime.now(),
        items = items ?? [],
        unresolvedScans = unresolvedScans ?? [];

  /// Summary statistics for the session.
  StockCountSummary get summary => StockCountSummary.fromItems(
        items,
        unresolvedCount: unresolvedScans.length,
      );

  /// Fast lookup map by variantId.
  Map<String, StockCountItem> get itemsByVariantId => {
        for (final item in items) item.variantId: item,
      };

  /// Adds or increments a counted product by match.
  bool recordScanMatch(ProductIdentificationMatch match, [double quantity = 1.0]) {
    for (final item in items) {
      if (item.variantId == match.variantId) {
        item.increment(quantity);
        return true;
      }
    }
    // If not found in snapshot (e.g. unstocked product found in warehouse)
    final newItem = StockCountItem(
      variantId: match.variantId,
      productId: match.productId,
      productName: match.productName,
      variantName: match.variantName,
      sku: match.sku,
      barcode: match.barcode,
      unitName: match.unitCode,
      systemQuantity: 0.0, // Was not in system snapshot
      countedQuantity: quantity,
      isCounted: true,
      scanCount: 1,
      lastScannedAt: DateTime.now(),
      reconciliationNote: 'Unstocked item found during physical count',
    );
    items.add(newItem);
    return true;
  }

  /// Records an unresolvable barcode scan.
  void recordUnresolvedScan(String rawCode, ScannerSource source, [String? note]) {
    unresolvedScans.insert(
      0,
      UnresolvedScanItem(
        id: 'unres-${DateTime.now().microsecondsSinceEpoch}',
        rawCode: rawCode.trim(),
        source: source,
        scannedAt: DateTime.now(),
        note: note,
      ),
    );
  }

  /// Prepares the payload for `inventory_stock_count_post_v485`.
  List<Map<String, dynamic>> toPostPayload() {
    return items
        .where((i) => i.isCounted)
        .map((i) => i.toPostItemMap())
        .toList();
  }
}

/// Historical audit record of a past stock count fetched from `stock_counts_list_v485`.
class StockCountAuditRecord {
  final String id;
  final String countNumber;
  final String locationId;
  final String locationName;
  final String status;
  final String reconciliationStatus;
  final String? notes;
  final int lineCount;
  final double totalSystemQuantity;
  final double totalCountedQuantity;
  final double totalVariance;
  final DateTime createdAt;
  final DateTime? postedAt;

  const StockCountAuditRecord({
    required this.id,
    required this.countNumber,
    required this.locationId,
    required this.locationName,
    required this.status,
    required this.reconciliationStatus,
    this.notes,
    required this.lineCount,
    required this.totalSystemQuantity,
    required this.totalCountedQuantity,
    required this.totalVariance,
    required this.createdAt,
    this.postedAt,
  });

  factory StockCountAuditRecord.fromRpcMap(Map<String, dynamic> map) {
    return StockCountAuditRecord(
      id: map['id']?.toString() ?? '',
      countNumber: map['count_number']?.toString() ?? '',
      locationId: map['location_id']?.toString() ?? '',
      locationName: map['location_name']?.toString() ?? '',
      status: map['status']?.toString() ?? 'posted',
      reconciliationStatus: map['reconciliation_status']?.toString() ?? 'reconciled',
      notes: map['notes']?.toString(),
      lineCount: (map['line_count'] as num?)?.toInt() ?? 0,
      totalSystemQuantity: (map['total_system_quantity'] as num?)?.toDouble() ?? 0.0,
      totalCountedQuantity: (map['total_counted_quantity'] as num?)?.toDouble() ?? 0.0,
      totalVariance: (map['total_variance'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      postedAt: map['posted_at'] != null ? DateTime.tryParse(map['posted_at'].toString()) : null,
    );
  }
}
