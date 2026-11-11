import 'package:erp_core/erp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PurchaseReceivingItem Model Tests', () {
    test('Calculates remaining, excess, and status accurately', () {
      final item = PurchaseReceivingItem(
        purchaseOrderItemId: 'poi-1',
        variantId: 'var-1',
        productName: 'Cement 50kg',
        sku: 'SKU-CEM-50',
        unitName: 'BAG',
        orderedQuantity: 100.0,
        previouslyReceivedQuantity: 20.0,
      );

      // Initially 0 received -> 80 remaining expected, status is pending / missing
      expect(item.remainingExpectedQuantity, 80.0);
      expect(item.excessQuantity, 0.0);
      expect(item.isMissing, true);
      expect(item.isFullyReceived, false);
      expect(item.status, ReceivingItemStatus.pending);

      // Receive partial: 30 bags
      item.setReceived(30.0);
      expect(item.receivedQuantity, 30.0);
      expect(item.acceptedQuantity, 30.0);
      expect(item.isPartiallyReceived, true);
      expect(item.isFullyReceived, false);
      expect(item.status, ReceivingItemStatus.partial);

      // Receive full remaining: 80 bags
      item.matchRemaining();
      expect(item.receivedQuantity, 80.0);
      expect(item.isFullyReceived, true);
      expect(item.status, ReceivingItemStatus.complete);

      // Over-delivery: 95 bags (15 excess)
      item.setReceived(95.0);
      expect(item.receivedQuantity, 95.0);
      expect(item.excessQuantity, 15.0);
      expect(item.status, ReceivingItemStatus.excess);
    });

    test('Damaged and rejected allocations update accepted quantities cleanly', () {
      final item = PurchaseReceivingItem(
        purchaseOrderItemId: 'poi-2',
        variantId: 'var-2',
        productName: 'Ceramic Floor Tiles 60x60',
        sku: 'SKU-TILE-60',
        unitName: 'BOX',
        orderedQuantity: 50.0,
      );

      item.setReceived(50.0);
      expect(item.acceptedQuantity, 50.0);

      // 4 boxes found broken with cracked tiles
      item.setDamaged(4.0, 'Broken cartons during transit');
      expect(item.damagedQuantity, 4.0);
      expect(item.acceptedQuantity, 46.0);
      expect(item.damageNote, 'Broken cartons during transit');

      // 2 boxes rejected for wrong color shade
      item.setRejected(2.0, 'Incorrect shade code delivered');
      expect(item.rejectedQuantity, 2.0);
      expect(item.acceptedQuantity, 44.0);
      expect(item.rejectionReason, 'Incorrect shade code delivered');
      expect(item.hasDiscrepancy, true);

      // Format for goods_receipt_create_v484
      final grnMap = item.toGrnItemMap();
      expect(grnMap['purchase_order_item_id'], 'poi-2');
      expect(grnMap['received_quantity'], 50.0);
      expect(grnMap['accepted_quantity'], 44.0);
      expect(grnMap['damaged_quantity'], 4.0);
      expect(grnMap['rejected_quantity'], 2.0);
      expect(grnMap['damage_note'], 'Broken cartons during transit');
      expect(grnMap['rejection_reason'], 'Incorrect shade code delivered');
    });

    test('Constructs from PO item RPC map accurately', () {
      final map = {
        'id': 'po-line-001',
        'variant_id': 'var-999',
        'product_id': 'prod-999',
        'product_name': 'Steel TMT 16mm',
        'variant_name': 'Fe 550D',
        'sku': 'SKU-TMT-16',
        'barcode': '8901234567890',
        'unit_name': 'TON',
        'quantity': 25.0,
        'received_quantity': 10.0,
        'unit_cost': 62000.0,
        'tracking_mode': 'batch',
      };

      final item = PurchaseReceivingItem.fromPoItemMap(map);
      expect(item.purchaseOrderItemId, 'po-line-001');
      expect(item.variantId, 'var-999');
      expect(item.productName, 'Steel TMT 16mm');
      expect(item.orderedQuantity, 25.0);
      expect(item.previouslyReceivedQuantity, 10.0);
      expect(item.remainingExpectedQuantity, 15.0);
      expect(item.unitCost, 62000.0);
      expect(item.trackingMode, 'batch');
      expect(item.barcode, '8901234567890');
    });
  });

  group('PurchaseReceivingSummary Calculations', () {
    test('Calculates aggregated lines, quantities, and progress percentage', () {
      final items = [
        PurchaseReceivingItem(
          purchaseOrderItemId: '1',
          variantId: 'v1',
          productName: 'Item 1',
          sku: 'SKU1',
          unitName: 'PCS',
          orderedQuantity: 10.0,
          receivedQuantity: 10.0,
        ),
        PurchaseReceivingItem(
          purchaseOrderItemId: '2',
          variantId: 'v2',
          productName: 'Item 2',
          sku: 'SKU2',
          unitName: 'PCS',
          orderedQuantity: 20.0,
          receivedQuantity: 15.0,
          damagedQuantity: 2.0,
        ),
        PurchaseReceivingItem(
          purchaseOrderItemId: '3',
          variantId: 'v3',
          productName: 'Item 3',
          sku: 'SKU3',
          unitName: 'PCS',
          orderedQuantity: 10.0,
          receivedQuantity: 0.0,
        ),
        PurchaseReceivingItem(
          purchaseOrderItemId: null, // unexpected delivery
          variantId: 'v4',
          productName: 'Unexpected Item 4',
          sku: 'SKU4',
          unitName: 'PCS',
          orderedQuantity: 0.0,
          receivedQuantity: 5.0,
        ),
      ];

      final summary = PurchaseReceivingSummary.fromItems(items, unresolvedCount: 1);

      expect(summary.totalOrderedLines, 3);
      expect(summary.totalReceivedLines, 3);
      expect(summary.fullyReceivedLines, 1);
      expect(summary.partiallyReceivedLines, 1);
      expect(summary.missingLines, 1);
      expect(summary.unexpectedLines, 1);
      expect(summary.totalOrderedQuantity, 40.0);
      expect(summary.totalReceivedQuantity, 30.0);
      expect(summary.totalDamagedQuantity, 2.0);
      expect(summary.totalAcceptedQuantity, 28.0);
      expect(summary.completionPercentage, 75.0); // 30 / 40 * 100 = 75%
      expect(summary.unresolvedScanCount, 1);
    });
  });

  group('PurchaseReceivingSession Workflow Tests', () {
    test('Session records scan matches, adds unexpected items, and captures unresolved scans', () {
      final item1 = PurchaseReceivingItem(
        purchaseOrderItemId: 'poi-cement',
        variantId: 'var-cement',
        productName: 'Cement 50kg',
        sku: 'SKU-CEM',
        barcode: '8901234567001',
        unitName: 'BAG',
        orderedQuantity: 50.0,
      );

      final session = PurchaseReceivingSession(
        id: 'sess-01',
        sessionName: 'Morning Delivery',
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        locationName: 'Central Depot',
        supplierId: 'supp-1',
        supplierName: 'UltraTech Corp',
        purchaseOrderId: 'po-01',
        purchaseOrderNumber: 'PO-261111-0001',
        requestId: 'req-uuid-001',
        items: [item1],
      );

      // Scan known PO item
      session.recordScanMatch(
        ProductIdentificationMatch(
          productId: 'prod-cement',
          variantId: 'var-cement',
          productName: 'Cement 50kg',
          sku: 'SKU-CEM',
          barcode: '8901234567001',
          unitCode: 'BAG',
          stockQuantity: 100.0,
          sellingPrice: 380.0,
          matchMethod: MatchMethod.exactBarcode,
          matchedCode: '8901234567001',
        ),
        5.0,
      );

      expect(item1.receivedQuantity, 5.0);
      expect(item1.scanCount, 1);

      // Scan an unexpected product not on the PO
      session.recordScanMatch(
        ProductIdentificationMatch(
          productId: 'prod-primer',
          variantId: 'var-primer',
          productName: 'Wall Primer 20L',
          sku: 'SKU-PRIMER-20',
          barcode: '8901234567999',
          unitCode: 'CAN',
          stockQuantity: 10.0,
          sellingPrice: 1200.0,
          matchMethod: MatchMethod.exactBarcode,
          matchedCode: '8901234567999',
        ),
        2.0,
      );

      expect(session.items.length, 2);
      final unexpected = session.items.last;
      expect(unexpected.isUnexpected, true);
      expect(unexpected.receivedQuantity, 2.0);
      expect(unexpected.orderedQuantity, 0.0);

      // Record an unrecognized barcode
      session.recordUnresolvedScan('9999999999999', ScannerSource.usb, 'Unmapped supplier code');
      expect(session.unresolvedScans.length, 1);
      expect(session.unresolvedScans.first.rawCode, '9999999999999');

      // GRN payload includes only PO items with received > 0
      final grnPayload = session.toGrnPayload();
      expect(grnPayload.length, 1);
      expect(grnPayload.first['purchase_order_item_id'], 'poi-cement');
      expect(grnPayload.first['received_quantity'], 5.0);
    });

    test('PurchaseOrderSummaryRecord and GoodsReceiptSummaryRecord deserialize accurately', () {
      final poMap = {
        'id': 'po-100',
        'order_number': 'PO-261111-000100',
        'order_date': '2026-11-11',
        'expected_date': '2026-11-15',
        'status': 'approved',
        'supplier_id': 'sup-1',
        'supplier_name': 'Tata Steel Ltd',
        'location_id': 'loc-1',
        'location_name': 'Warehouse A',
        'item_count': 5,
        'ordered_quantity': 150.0,
        'received_quantity': 50.0,
        'remaining_receive_quantity': 100.0,
        'grand_total': 450000.0,
      };

      final po = PurchaseOrderSummaryRecord.fromRpcMap(poMap);
      expect(po.orderNumber, 'PO-261111-000100');
      expect(po.remainingReceiveQuantity, 100.0);
      expect(po.supplierName, 'Tata Steel Ltd');

      final grnMap = {
        'id': 'grn-500',
        'grn_number': 'GRN-261111-000500',
        'receipt_date': '2026-11-11',
        'status': 'posted',
        'purchase_order_id': 'po-100',
        'order_number': 'PO-261111-000100',
        'supplier_id': 'sup-1',
        'supplier_name': 'Tata Steel Ltd',
        'location_id': 'loc-1',
        'location_name': 'Warehouse A',
        'line_count': 4,
        'received_quantity': 50.0,
        'accepted_quantity': 48.0,
        'damaged_quantity': 2.0,
        'rejected_quantity': 0.0,
        'created_at': '2026-11-11T12:00:00Z',
      };

      final grn = GoodsReceiptSummaryRecord.fromRpcMap(grnMap);
      expect(grn.grnNumber, 'GRN-261111-000500');
      expect(grn.status, 'posted');
      expect(grn.acceptedQuantity, 48.0);
      expect(grn.damagedQuantity, 2.0);
    });
  });
}
