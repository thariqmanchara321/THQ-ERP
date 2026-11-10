import 'package:erp_core/erp_core.dart';

/// An in-memory or locally persisted record of an individual item in a bulk scan session.
class BulkScanItem {
  final ProductIdentificationMatch match;
  double quantity;
  int scanCount;
  DateTime lastScannedAt;

  BulkScanItem({
    required this.match,
    this.quantity = 1.0,
    this.scanCount = 1,
    DateTime? lastScannedAt,
  }) : lastScannedAt = lastScannedAt ?? DateTime.now();

  String get productId => match.productId;
  String get variantId => match.variantId;
  String get productName => match.productName;
  String get variantName => match.variantName;
  String get sku => match.sku;
  String? get barcode => match.barcode;
  String get unitCode => match.unitCode;
  double get sellingPrice => match.sellingPrice;
  double get currentStock => match.stockQuantity;

  void increment([double step = 1.0]) {
    quantity += step;
    scanCount += 1;
    lastScannedAt = DateTime.now();
  }

  void decrement([double step = 1.0]) {
    if (quantity > step) {
      quantity -= step;
    } else {
      quantity = 0.0;
    }
    lastScannedAt = DateTime.now();
  }

  Map<String, dynamic> toMap() => {
        'product_id': match.productId,
        'variant_id': match.variantId,
        'product_name': match.productName,
        'variant_name': match.variantName,
        'sku': match.sku,
        'barcode': match.barcode,
        'quantity': quantity,
        'scan_count': scanCount,
        'unit_code': match.unitCode,
        'selling_price': match.sellingPrice,
        'last_scanned_at': lastScannedAt.toIso8601String(),
      };
}

/// A scanned barcode or identifier that could not be resolved to any existing product.
class UnresolvedScanItem {
  final String id;
  final String rawCode;
  final ScannerSource source;
  final DateTime scannedAt;
  final String? note;

  const UnresolvedScanItem({
    required this.id,
    required this.rawCode,
    required this.source,
    required this.scannedAt,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'raw_code': rawCode,
        'source': source.name,
        'scanned_at': scannedAt.toIso8601String(),
        'note': note,
      };
}

/// A container representing a temporary bulk scanning session.
class SmartScanSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final String? locationId;
  final String? locationName;
  final String operatorName;
  final List<BulkScanItem> items;
  final List<UnresolvedScanItem> unresolvedScans;
  bool isCompleted;
  DateTime? completedAt;

  SmartScanSession({
    required this.id,
    required this.title,
    DateTime? createdAt,
    this.locationId,
    this.locationName,
    required this.operatorName,
    List<BulkScanItem>? items,
    List<UnresolvedScanItem>? unresolvedScans,
    this.isCompleted = false,
    this.completedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        items = items ?? <BulkScanItem>[],
        unresolvedScans = unresolvedScans ?? <UnresolvedScanItem>[];

  int get totalDistinctProducts => items.length;

  double get totalQuantity =>
      items.fold<double>(0.0, (acc, item) => acc + item.quantity);

  int get totalScans =>
      items.fold<int>(0, (acc, item) => acc + item.scanCount) +
      unresolvedScans.length;

  int get totalUnresolved => unresolvedScans.length;

  void addOrIncrementMatch(ProductIdentificationMatch match, [double step = 1.0]) {
    final key = match.variantId.isNotEmpty ? match.variantId : match.productId;
    final index = items.indexWhere(
      (item) =>
          (item.variantId.isNotEmpty ? item.variantId : item.productId) == key,
    );

    if (index >= 0) {
      items[index].increment(step);
    } else {
      items.insert(
        0,
        BulkScanItem(
          match: match,
          quantity: step,
          scanCount: 1,
        ),
      );
    }
  }

  void addUnresolved(String rawCode, ScannerSource source, [String? note]) {
    unresolvedScans.insert(
      0,
      UnresolvedScanItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        rawCode: rawCode,
        source: source,
        scannedAt: DateTime.now(),
        note: note,
      ),
    );
  }

  void removeUnresolved(String id) {
    unresolvedScans.removeWhere((item) => item.id == id);
  }

  void removeItem(String variantId) {
    items.removeWhere((item) => item.variantId == variantId);
  }

  void clear() {
    items.clear();
    unresolvedScans.clear();
  }

  void complete() {
    isCompleted = true;
    completedAt = DateTime.now();
  }
}

/// A lightweight audit entry for the recent scan activity feed.
class ScanActivityLogEntry {
  final String id;
  final String rawCode;
  final ProductIdentificationStatus status;
  final String? productName;
  final String? sku;
  final ScannerSource source;
  final DateTime timestamp;
  final String? errorMessage;

  const ScanActivityLogEntry({
    required this.id,
    required this.rawCode,
    required this.status,
    this.productName,
    this.sku,
    required this.source,
    required this.timestamp,
    this.errorMessage,
  });

  bool get isSuccess => status == ProductIdentificationStatus.exactMatch;
}

