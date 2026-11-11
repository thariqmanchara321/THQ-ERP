import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StockCountItem Model Tests', () {
    test('Calculates variance and absolute variance accurately', () {
      final item = StockCountItem(
        variantId: 'var-1',
        productName: 'Portland Cement 50kg',
        sku: 'SKU-CEM-01',
        systemQuantity: 100.0,
      );

      // Initially not counted
      expect(item.isCounted, isFalse);
      expect(item.varianceType, StockCountVarianceType.notCounted);
      expect(item.variance, -100.0);

      // Set matching quantity
      item.setCounted(100.0);
      expect(item.isCounted, isTrue);
      expect(item.variance, 0.0);
      expect(item.absoluteVariance, 0.0);
      expect(item.hasVariance, isFalse);
      expect(item.varianceType, StockCountVarianceType.matched);

      // Shortage (found 92 instead of 100)
      item.setCounted(92.0);
      expect(item.variance, -8.0);
      expect(item.absoluteVariance, 8.0);
      expect(item.hasVariance, isTrue);
      expect(item.varianceType, StockCountVarianceType.shortage);

      // Excess (found 105 instead of 100)
      item.setCounted(105.0);
      expect(item.variance, 5.0);
      expect(item.absoluteVariance, 5.0);
      expect(item.hasVariance, isTrue);
      expect(item.varianceType, StockCountVarianceType.excess);
    });

    test('Increment and decrement update counts and tracking timestamps', () {
      final item = StockCountItem(
        variantId: 'var-2',
        productName: 'Steel Rebar 12mm',
        sku: 'SKU-REB-12',
        systemQuantity: 50.0,
      );

      item.increment(1.0);
      expect(item.countedQuantity, 1.0);
      expect(item.scanCount, 1);
      expect(item.isCounted, isTrue);
      expect(item.lastScannedAt, isNotNull);

      item.increment(4.0);
      expect(item.countedQuantity, 5.0);
      expect(item.scanCount, 2);

      item.decrement(2.0);
      expect(item.countedQuantity, 3.0);

      // Clamps to 0
      item.decrement(10.0);
      expect(item.countedQuantity, 0.0);
    });

    test('Constructs from RPC snapshot map correctly', () {
      final snapshotMap = {
        'variant_id': 'v-uuid-1',
        'product_id': 'p-uuid-1',
        'product_name': 'Sand Gravel Mix',
        'variant_name': 'Bulk 1 Ton',
        'sku': 'SKU-SND-01',
        'barcode': '280000000025',
        'unit_name': 'TON',
        'system_quantity': 24.5,
        'tracking_mode': 'none',
        'tracking': {},
        'reserved_quantity': 0.0,
        'damaged_quantity': 0.0,
        'quarantine_quantity': 0.0,
      };

      final item = StockCountItem.fromSnapshotMap(snapshotMap);
      expect(item.variantId, 'v-uuid-1');
      expect(item.productName, 'Sand Gravel Mix');
      expect(item.systemQuantity, 24.5);
      expect(item.countedQuantity, 0.0);
      expect(item.isCounted, isFalse);

      final postMap = item.toPostItemMap();
      expect(postMap['variant_id'], 'v-uuid-1');
      expect(postMap['counted_quantity'], 0.0);
    });
  });

  group('StockCountSummary Calculations', () {
    test('Calculates aggregated metrics and completion percentage', () {
      final items = [
        StockCountItem(
          variantId: 'v-1',
          productName: 'Item 1',
          sku: 'SKU-1',
          systemQuantity: 10.0,
          countedQuantity: 10.0,
          isCounted: true,
        ),
        StockCountItem(
          variantId: 'v-2',
          productName: 'Item 2',
          sku: 'SKU-2',
          systemQuantity: 20.0,
          countedQuantity: 15.0, // Shortage (-5)
          isCounted: true,
        ),
        StockCountItem(
          variantId: 'v-3',
          productName: 'Item 3',
          sku: 'SKU-3',
          systemQuantity: 5.0,
          countedQuantity: 8.0, // Excess (+3)
          isCounted: true,
        ),
        StockCountItem(
          variantId: 'v-4',
          productName: 'Item 4',
          sku: 'SKU-4',
          systemQuantity: 50.0,
          countedQuantity: 0.0, // Uncounted
          isCounted: false,
        ),
      ];

      final summary = StockCountSummary.fromItems(items, unresolvedCount: 2);

      expect(summary.totalItems, 4);
      expect(summary.countedItems, 3);
      expect(summary.uncountedItems, 1);
      expect(summary.matchedItems, 1);
      expect(summary.shortageItems, 1);
      expect(summary.excessItems, 1);
      expect(summary.unresolvedCount, 2);
      expect(summary.totalSystemQuantity, 85.0);
      expect(summary.totalCountedQuantity, 33.0);
      expect(summary.netVarianceQuantity, -52.0);
      expect(summary.completionPercentage, 75.0);
    });
  });

  group('StockCountSession Workflow Tests', () {
    test('Session tracks matches, adds unstocked items, and records unresolved scans', () {
      final session = StockCountSession(
        id: 'sess-1',
        countNumber: 'CNT-261111-000001',
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        locationName: 'Main Depot',
        sessionName: 'Annual Stock Audit',
        requestId: 'req-uuid-1',
        items: [
          StockCountItem(
            variantId: 'var-100',
            productName: 'Standard Brick',
            sku: 'SKU-BRK-STD',
            barcode: '280000000100',
            systemQuantity: 500.0,
          ),
        ],
      );

      expect(session.items.length, 1);
      expect(session.summary.countedItems, 0);

      // Scan known item
      final matchKnown = ProductIdentificationMatch(
        matchMethod: MatchMethod.exactBarcode,
        matchedCode: '280000000100',
        productId: 'prod-100',
        variantId: 'var-100',
        productName: 'Standard Brick',
        variantName: 'Red Clay',
        sku: 'SKU-BRK-STD',
        barcode: '280000000100',
        unitCode: 'PCS',
        sellingPrice: 15.0,
        stockQuantity: 500.0,
      );

      session.recordScanMatch(matchKnown, 50.0);
      expect(session.itemsByVariantId['var-100']!.countedQuantity, 50.0);
      expect(session.itemsByVariantId['var-100']!.isCounted, isTrue);

      // Scan unstocked product found in warehouse
      final matchNew = ProductIdentificationMatch(
        matchMethod: MatchMethod.exactBarcode,
        matchedCode: '280000000200',
        productId: 'prod-200',
        variantId: 'var-200',
        productName: 'Paving Stone Grey',
        variantName: 'Hexagonal',
        sku: 'SKU-PAV-GRY',
        barcode: '280000000200',
        unitCode: 'PCS',
        sellingPrice: 45.0,
        stockQuantity: 0.0,
      );

      session.recordScanMatch(matchNew, 12.0);
      expect(session.items.length, 2);
      expect(session.itemsByVariantId['var-200']!.systemQuantity, 0.0);
      expect(session.itemsByVariantId['var-200']!.countedQuantity, 12.0);
      expect(session.itemsByVariantId['var-200']!.variance, 12.0);

      // Record unresolved scan
      session.recordUnresolvedScan('9999999999', ScannerSource.camera, 'Scratched barcode');
      expect(session.unresolvedScans.length, 1);
      expect(session.unresolvedScans.first.rawCode, '9999999999');

      // Post payload only includes counted items
      final postPayload = session.toPostPayload();
      expect(postPayload.length, 2);
      expect(postPayload.first['variant_id'], 'var-100');
      expect(postPayload.first['counted_quantity'], 50.0);
      expect(postPayload.last['variant_id'], 'var-200');
      expect(postPayload.last['counted_quantity'], 12.0);
    });

    test('StockCountAuditRecord deserializes accurately from RPC list map', () {
      final rpcMap = {
        'id': 'audit-uuid-1',
        'count_number': 'CNT-261110-000042',
        'location_id': 'loc-1',
        'location_name': 'DEPOT • Main Depot',
        'status': 'posted',
        'reconciliation_status': 'variance',
        'notes': 'Quarterly audit reconciliation',
        'line_count': 18,
        'total_system_quantity': 1500.0,
        'total_counted_quantity': 1488.0,
        'total_variance': -12.0,
        'created_at': '2026-11-10T10:00:00Z',
        'posted_at': '2026-11-10T14:30:00Z',
      };

      final record = StockCountAuditRecord.fromRpcMap(rpcMap);
      expect(record.id, 'audit-uuid-1');
      expect(record.countNumber, 'CNT-261110-000042');
      expect(record.lineCount, 18);
      expect(record.totalVariance, -12.0);
      expect(record.reconciliationStatus, 'variance');
    });
  });
}
