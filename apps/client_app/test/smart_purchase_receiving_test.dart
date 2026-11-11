import 'package:client_app/models/client_session.dart';
import 'package:client_app/screens/smart_inventory/tabs/smart_purchase_receiving_tab.dart';
import 'package:client_app/services/client_smart_inventory_service.dart';
import 'package:client_app/services/purchase_receiving_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tenantId = 'tenant-test-pr-01';
  const locationId = 'loc-wh-01';

  const testBusiness = ClientBusiness(
    id: tenantId,
    membershipId: 'mem-1',
    name: 'THQ Hardware Supplies',
    slug: 'thq-hardware',
    businessType: 'wholesale',
    status: 'active',
  );

  const managerSession = ClientSession(
    business: testBusiness,
    userId: 'user-pr-manager',
    username: 'Alice Receiving',
    modules: [
      ClientModule(
        key: 'inventory',
        name: 'Inventory',
        description: null,
        category: 'Inventory',
        sortOrder: 10,
      ),
      ClientModule(
        key: 'purchases',
        name: 'Purchases',
        description: null,
        category: 'Purchases',
        sortOrder: 20,
      ),
    ],
    roles: {'manager'},
    permissions: {'inventory.view', 'inventory.manage', 'purchases.manage'},
    currencyCode: 'INR',
    timezone: 'Asia/Kolkata',
    locale: 'en_IN',
  );

  final samplePoListRows = [
    {
      'id': 'po-101',
      'order_number': 'PO-261111-0001',
      'supplier_id': 'sup-01',
      'supplier_name': 'Steel Corp India',
      'location_id': locationId,
      'location_name': 'Main Warehouse',
      'status': 'confirmed',
      'order_date': '2026-11-10T10:00:00Z',
      'expected_delivery_date': '2026-11-15T00:00:00Z',
      'line_count': 2,
      'ordered_quantity': 150.0,
      'received_quantity': 50.0,
      'remaining_receive_quantity': 100.0,
      'net_total': 45000.0,
    },
    {
      'id': 'po-102',
      'order_number': 'PO-261111-0002',
      'supplier_id': 'sup-02',
      'supplier_name': 'UltraTech Direct',
      'location_id': locationId,
      'location_name': 'Main Warehouse',
      'status': 'partially_received',
      'order_date': '2026-11-08T09:00:00Z',
      'expected_delivery_date': '2026-11-12T00:00:00Z',
      'line_count': 1,
      'ordered_quantity': 200.0,
      'received_quantity': 100.0,
      'remaining_receive_quantity': 100.0,
      'net_total': 76000.0,
    },
  ];

  final samplePoDetailMap = {
    'id': 'po-101',
    'order_number': 'PO-261111-0001',
    'supplier_id': 'sup-01',
    'supplier_name': 'Steel Corp India',
    'location_id': locationId,
    'location_name': 'Main Warehouse',
    'status': 'confirmed',
    'items': [
      {
        'id': 'poi-01',
        'product_id': 'prod-001',
        'variant_id': 'var-001',
        'product_name': 'Steel TMT Bar 12mm',
        'variant_name': '12 Meter Bundle',
        'sku': 'SKU-TMT-12',
        'barcode': '8901234567001',
        'unit_name': 'BDL',
        'ordered_quantity': 100.0,
        'received_quantity': 50.0,
        'remaining_receive_quantity': 50.0,
        'unit_cost': 350.0,
        'tracking_mode': 'none',
      },
      {
        'id': 'poi-02',
        'product_id': 'prod-002',
        'variant_id': 'var-002',
        'product_name': 'Binding Wire 18G',
        'variant_name': 'Roll 25kg',
        'sku': 'SKU-WIRE-18',
        'barcode': '8901234567002',
        'unit_name': 'ROL',
        'ordered_quantity': 50.0,
        'received_quantity': 0.0,
        'remaining_receive_quantity': 50.0,
        'unit_cost': 200.0,
        'tracking_mode': 'none',
      },
    ],
  };

  final sampleGrnListRows = [
    {
      'id': 'grn-501',
      'grn_number': 'GRN-261111-000001',
      'purchase_order_id': 'po-101',
      'purchase_order_number': 'PO-261111-0001',
      'supplier_id': 'sup-01',
      'supplier_name': 'Steel Corp India',
      'location_id': locationId,
      'location_name': 'Main Warehouse',
      'status': 'posted',
      'receipt_date': '2026-11-11T12:00:00Z',
      'supplier_delivery_note': 'DN-STEEL-99',
      'notes': 'Initial 50 bundles received',
      'line_count': 1,
      'total_received_quantity': 50.0,
      'total_accepted_quantity': 50.0,
      'total_damaged_quantity': 0.0,
      'total_rejected_quantity': 0.0,
      'created_at': '2026-11-11T12:00:00Z',
      'posted_at': '2026-11-11T12:05:00Z',
    },
  ];

  group('PurchaseReceivingService Unit Tests', () {
    late PurchaseReceivingService service;

    setUp(() {
      service = PurchaseReceivingService.instance;
    });

    test('listReceivablePurchaseOrders parses open PO records correctly', () async {
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'purchase_order_list_v484') {
          return samplePoListRows;
        }
        return null;
      });

      final orders = await service.listReceivablePurchaseOrders(tenantId: tenantId);

      expect(orders.length, 2);
      expect(orders.first.orderNumber, 'PO-261111-0001');
      expect(orders.first.supplierName, 'Steel Corp India');
      expect(orders.first.remainingReceiveQuantity, 100.0);
      expect(orders.last.orderNumber, 'PO-261111-0002');
    });

    test('fetchReceivingItemsForPo retrieves line items with remaining expected quantities', () async {
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'purchase_order_detail_v484') {
          return samplePoDetailMap;
        }
        return null;
      });

      final items = await service.fetchReceivingItemsForPo(
        tenantId: tenantId,
        purchaseOrderId: 'po-101',
      );

      expect(items.length, 2);
      expect(items.first.productName, 'Steel TMT Bar 12mm');
      expect(items.first.orderedQuantity, 100.0);
      expect(items.first.previouslyReceivedQuantity, 50.0);
      expect(items.first.remainingExpectedQuantity, 50.0);
      expect(items.first.receivedQuantity, 0.0);
      expect(items.last.productName, 'Binding Wire 18G');
      expect(items.last.remainingExpectedQuantity, 50.0);
    });

    test('createGoodsReceipt creates draft GRN via RPC', () async {
      Map<String, dynamic>? calledParams;

      service.setCustomRpc((fn, {params}) async {
        if (fn == 'goods_receipt_create_v484') {
          calledParams = params;
          return {
            'goods_receipt_id': 'grn-new-001',
            'grn_number': 'GRN-261111-000002',
            'status': 'draft',
          };
        }
        return null;
      });

      final result = await service.createGoodsReceipt(
        tenantId: tenantId,
        purchaseOrderId: 'po-101',
        items: [
          {
            'purchase_order_item_id': 'poi-01',
            'received_quantity': 50.0,
            'accepted_quantity': 50.0,
            'damaged_quantity': 0.0,
            'rejected_quantity': 0.0,
          }
        ],
        supplierDeliveryNote: 'DN-101-BATCH2',
        notes: 'Warehouse dock receiving',
      );

      expect(result['goods_receipt_id'], 'grn-new-001');
      expect(calledParams?['p_purchase_order_id'], 'po-101');
      expect(calledParams?['p_supplier_delivery_note'], 'DN-101-BATCH2');
    });

    test('postGoodsReceipt posts GRN atomically to ledger via RPC', () async {
      Map<String, dynamic>? calledParams;

      service.setCustomRpc((fn, {params}) async {
        if (fn == 'goods_receipt_post_v484') {
          calledParams = params;
          return {
            'goods_receipt_id': 'grn-new-001',
            'status': 'posted',
            'posted_at': '2026-11-11T12:10:00Z',
          };
        }
        return null;
      });

      final result = await service.postGoodsReceipt(
        tenantId: tenantId,
        goodsReceiptId: 'grn-new-001',
        deviceId: 'device-test-1',
      );

      expect(result['status'], 'posted');
      expect(calledParams?['p_goods_receipt_id'], 'grn-new-001');
      expect(calledParams?['p_device_id'], 'device-test-1');
    });

    test('createAndPostGoodsReceipt chains create and post atomically', () async {
      final calls = <String>[];

      service.setCustomRpc((fn, {params}) async {
        calls.add(fn);
        if (fn == 'goods_receipt_create_v484') {
          return {
            'goods_receipt_id': 'grn-atomic-01',
            'grn_number': 'GRN-261111-000003',
          };
        }
        if (fn == 'goods_receipt_post_v484') {
          return {
            'goods_receipt_id': 'grn-atomic-01',
            'status': 'posted',
            'purchase_order_status': 'received',
          };
        }
        return null;
      });

      final result = await service.createAndPostGoodsReceipt(
        tenantId: tenantId,
        purchaseOrderId: 'po-101',
        items: [
          {
            'purchase_order_item_id': 'poi-01',
            'received_quantity': 50.0,
            'accepted_quantity': 50.0,
          }
        ],
        supplierDeliveryNote: 'DN-ATOMIC-01',
      );

      expect(calls, ['goods_receipt_create_v484', 'goods_receipt_post_v484']);
      expect(result['status'], 'posted');
      expect(result['grn_number'], 'GRN-261111-000003');
    });

    test('listPastGoodsReceipts retrieves historical audit records', () async {
      service.setCustomRpc((fn, {params}) async {
        if (fn == 'goods_receipt_list_v484') {
          return sampleGrnListRows;
        }
        return null;
      });

      final grns = await service.listPastGoodsReceipts(tenantId: tenantId);

      expect(grns.length, 1);
      expect(grns.first.grnNumber, 'GRN-261111-000001');
      expect(grns.first.supplierName, 'Steel Corp India');
      expect(grns.first.acceptedQuantity, 50.0);
    });
  });

  group('SmartPurchaseReceivingTab Widget Tests', () {
    setUp(() {
      final receivingService = PurchaseReceivingService.instance;
      receivingService.setCustomRpc((fn, {params}) async {
        if (fn == 'purchase_order_list_v484') {
          return samplePoListRows;
        }
        if (fn == 'purchase_order_detail_v484') {
          return samplePoDetailMap;
        }
        if (fn == 'goods_receipt_list_v484') {
          return sampleGrnListRows;
        }
        if (fn == 'goods_receipt_create_v484') {
          return {
            'goods_receipt_id': 'grn-widget-001',
            'grn_number': 'GRN-261111-W001',
          };
        }
        if (fn == 'goods_receipt_post_v484') {
          return {
            'goods_receipt_id': 'grn-widget-001',
            'status': 'posted',
            'purchase_order_status': 'received',
          };
        }
        return null;
      });

      final identService = ClientSmartInventoryService.instance;
      identService.setCustomRpc((fn, {params}) async {
        if (fn == 'inventory_product_lookup_v482') {
          final code = params?['p_code']?.toString();
          if (code == '8901234567001' || code == 'SKU-TMT-12') {
            return {
              'product_id': 'prod-001',
              'variant_id': 'var-001',
              'product_name': 'Steel TMT Bar 12mm',
              'variant_name': '12 Meter Bundle',
              'sku': 'SKU-TMT-12',
              'barcode': '8901234567001',
              'selling_price': 400.0,
              'cost_price': 350.0,
              'stock_quantity': 50.0,
            };
          }
          return null;
        }
        return null;
      });
    });

    testWidgets('renders Setup view with Open POs tab and past GRN subtabs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartPurchaseReceivingTab(session: managerSession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Smart Purchase Receiving & Inward'), findsOneWidget);
      expect(find.text('Purchase Orders'), findsOneWidget);
      expect(find.text('Direct Inward'), findsOneWidget);
      expect(find.text('GRN Audit History'), findsOneWidget);

      // Open POs are rendered
      expect(find.text('PO-261111-0001'), findsOneWidget);
      expect(find.text('Steel Corp India • Location: Main Warehouse • Remaining: 100 of 150 units'), findsOneWidget);
      expect(find.text('PO-261111-0002'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Receive Goods'), findsWidgets);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping "Receive Goods" on a PO starts an active receiving session', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartPurchaseReceivingTab(session: managerSession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Receive Goods on first PO
      final receiveBtn = find.widgetWithText(FilledButton, 'Receive Goods').first;
      await tester.tap(receiveBtn);
      await tester.pumpAndSettle();

      // Should now be in Active Receiving view
      expect(find.text('Receiving • PO-261111-0001'), findsOneWidget);
      expect(find.text('Steel TMT Bar 12mm'), findsOneWidget);
      expect(find.text('Binding Wire 18G'), findsOneWidget);

      // Metric Chips rendered
      expect(find.textContaining('Ordered'), findsWidgets);
      expect(find.textContaining('Received'), findsWidgets);
      expect(find.textContaining('Accepted'), findsWidgets);

      // Action buttons rendered
      expect(find.widgetWithText(OutlinedButton, 'Receive All'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Review & Post Inward'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('Receive All button matches all line items to remaining expected quantities', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartPurchaseReceivingTab(session: managerSession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start session
      await tester.tap(find.widgetWithText(FilledButton, 'Receive Goods').first);
      await tester.pumpAndSettle();

      // Before Receive All: 0 received (0%)
      expect(find.textContaining('0 (0%)'), findsOneWidget);

      // Tap Receive All
      await tester.tap(find.widgetWithText(OutlinedButton, 'Receive All'));
      await tester.pumpAndSettle();

      // After Receive All: 100 received (100%)
      expect(find.textContaining('100 (100%)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('Stepper increment and decrement buttons adjust line received quantity', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartPurchaseReceivingTab(session: managerSession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Receive Goods').first);
      await tester.pumpAndSettle();

      // Find "+" icon buttons for line quantity increment
      final addIcons = find.byIcon(Icons.add);
      expect(addIcons, findsWidgets);

      // Tap "+" once on the first line item
      await tester.tap(addIcons.first);
      await tester.pumpAndSettle();

      // Received quantity should now be 1
      expect(find.text('1'), findsWidgets);

      // Find "-" icon button and tap it to decrease
      final removeIcons = find.byIcon(Icons.remove);
      await tester.tap(removeIcons.first);
      await tester.pumpAndSettle();

      // Received quantity returns to 0
      expect(find.textContaining('0 (0%)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('Manual barcode entry increments matching item count', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartPurchaseReceivingTab(session: managerSession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Receive Goods').first);
      await tester.pumpAndSettle();

      // Enter barcode in manual input field
      final inputField = find.byType(TextField).first;
      await tester.enterText(inputField, '8901234567001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // TMT Bar 12mm received quantity should have incremented to 1
      expect(find.text('1'), findsWidgets);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('Review & Post Inward dialog validates and completes inward receipt', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmartPurchaseReceivingTab(session: managerSession),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Receive Goods').first);
      await tester.pumpAndSettle();

      // Click Receive All to receive full shipment
      await tester.tap(find.widgetWithText(OutlinedButton, 'Receive All'));
      await tester.pumpAndSettle();

      // Tap Review & Post Inward
      await tester.tap(find.widgetWithText(FilledButton, 'Review & Post Inward'));
      await tester.pumpAndSettle();

      // Dialog appears
      expect(find.textContaining('Approve Goods Receipt'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Confirm & Post Receipt'), findsOneWidget);

      // Check the explicit confirmation checkbox
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Tap Confirm & Post Receipt button inside dialog
      final postButton = find.widgetWithText(FilledButton, 'Confirm & Post Receipt');
      await tester.ensureVisible(postButton);
      await tester.tap(postButton);
      await tester.pumpAndSettle();

      // Success notification shown and returns to setup view
      expect(find.text('Smart Purchase Receiving & Inward'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  });
}
