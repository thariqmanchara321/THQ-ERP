import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'purchase_service.dart';

/// Service coordinating Goods Receiving Notes (GRNs) and direct purchase receiving.
class PurchaseReceivingService {
  PurchaseReceivingService._();
  static final PurchaseReceivingService instance = PurchaseReceivingService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<dynamic> Function(String fn, {Map<String, dynamic>? params})? _customRpc;

  /// Custom RPC handler for testing.
  void setCustomRpc(
    Future<dynamic> Function(String fn, {Map<String, dynamic>? params})? handler,
  ) {
    _customRpc = handler;
  }

  Future<dynamic> _invokeRpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    if (_customRpc != null) {
      return _customRpc!(functionName, params: params);
    }
    return _supabase.rpc(functionName, params: params);
  }

  /// Lists open Purchase Orders eligible for physical receiving.
  ///
  /// Filters for orders in `approved`, `ordered`, or `partially_received` status.
  Future<List<PurchaseOrderSummaryRecord>> listReceivablePurchaseOrders({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 200,
  }) async {
    final result = await _invokeRpc(
      'purchase_order_list_v484',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': null, // Fetch all and filter receivable statuses client-side
        'p_query': query.trim(),
        'p_limit': limit,
      },
    );

    if (result is List) {
      return result
          .whereType<Map>()
          .map((e) => PurchaseOrderSummaryRecord.fromRpcMap(Map<String, dynamic>.from(e)))
          .where((po) =>
              po.status == 'approved' ||
              po.status == 'ordered' ||
              po.status == 'confirmed' ||
              po.status == 'partially_received')
          .toList();
    }
    return const [];
  }

  /// Retrieves full detail for a Purchase Order, including expected items and remaining quantities.
  Future<Map<String, dynamic>> getPurchaseOrderDetail({
    required String tenantId,
    required String purchaseOrderId,
  }) async {
    final result = await _invokeRpc(
      'purchase_order_detail_v484',
      params: {
        'p_tenant_id': tenantId,
        'p_purchase_order_id': purchaseOrderId,
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw StateError('Unexpected response from purchase_order_detail_v484: $result');
  }

  /// Constructs receiving line items from an authorized Purchase Order.
  Future<List<PurchaseReceivingItem>> fetchReceivingItemsForPo({
    required String tenantId,
    required String purchaseOrderId,
  }) async {
    final detail = await getPurchaseOrderDetail(
      tenantId: tenantId,
      purchaseOrderId: purchaseOrderId,
    );

    final rawItems = detail['items'];
    if (rawItems is List) {
      return rawItems
          .whereType<Map>()
          .map((m) => PurchaseReceivingItem.fromPoItemMap(Map<String, dynamic>.from(m)))
          .toList();
    }
    return const [];
  }

  /// Creates a draft Goods Receipt Note (GRN) via `goods_receipt_create_v484`.
  Future<Map<String, dynamic>> createGoodsReceipt({
    required String tenantId,
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
    DateTime? receiptDate,
    String? supplierDeliveryNote,
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Cannot create a Goods Receipt with zero lines.');
    }

    final dateStr = (receiptDate ?? DateTime.now()).toIso8601String().substring(0, 10);

    final result = await _invokeRpc(
      'goods_receipt_create_v484',
      params: {
        'p_tenant_id': tenantId,
        'p_purchase_order_id': purchaseOrderId,
        'p_receipt_date': dateStr,
        'p_items': items,
        'p_supplier_delivery_note': supplierDeliveryNote?.trim().isEmpty == true ? null : supplierDeliveryNote?.trim(),
        'p_notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw StateError('Unexpected response from goods_receipt_create_v484: $result');
  }

  /// Posts a Goods Receipt Note (GRN) via `goods_receipt_post_v484`.
  ///
  /// Atomically updates inventory balances, movement history ledger, and PO status.
  Future<Map<String, dynamic>> postGoodsReceipt({
    required String tenantId,
    required String goodsReceiptId,
    String? deviceId,
  }) async {
    final result = await _invokeRpc(
      'goods_receipt_post_v484',
      params: {
        'p_tenant_id': tenantId,
        'p_goods_receipt_id': goodsReceiptId,
        'p_device_id': deviceId,
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    throw StateError('Unexpected response from goods_receipt_post_v484: $result');
  }

  /// Convenience method that creates the GRN draft and immediately posts it atomically.
  Future<Map<String, dynamic>> createAndPostGoodsReceipt({
    required String tenantId,
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
    DateTime? receiptDate,
    String? supplierDeliveryNote,
    String? notes,
    String? deviceId,
  }) async {
    // 1. Create Draft GRN
    final createResult = await createGoodsReceipt(
      tenantId: tenantId,
      purchaseOrderId: purchaseOrderId,
      items: items,
      receiptDate: receiptDate,
      supplierDeliveryNote: supplierDeliveryNote,
      notes: notes,
    );

    final grnId = createResult['goods_receipt_id']?.toString();
    if (grnId == null || grnId.isEmpty) {
      throw StateError('Failed to obtain goods_receipt_id from draft creation.');
    }

    // 2. Post GRN to Ledger
    final postResult = await postGoodsReceipt(
      tenantId: tenantId,
      goodsReceiptId: grnId,
      deviceId: deviceId,
    );

    return {
      ...createResult,
      ...postResult,
    };
  }

  /// Lists historical Goods Receipt Notes (GRNs) for audit review.
  Future<List<GoodsReceiptSummaryRecord>> listPastGoodsReceipts({
    required String tenantId,
    String? locationId,
    String? status,
    String query = '',
    int limit = 200,
  }) async {
    final result = await _invokeRpc(
      'goods_receipt_list_v484',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status,
        'p_query': query.trim(),
        'p_limit': limit,
      },
    );

    if (result is List) {
      return result
          .whereType<Map>()
          .map((e) => GoodsReceiptSummaryRecord.fromRpcMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// Retrieves full line-item details of a specific Goods Receipt Note (GRN).
  Future<Map<String, dynamic>> getGoodsReceiptDetail({
    required String tenantId,
    required String goodsReceiptId,
  }) async {
    final result = await _invokeRpc(
      'goods_receipt_detail_v484',
      params: {
        'p_tenant_id': tenantId,
        'p_goods_receipt_id': goodsReceiptId,
      },
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return const {};
  }

  /// Posts a direct purchase receipt without a Purchase Order via `PurchaseService`.
  Future<Map<String, dynamic>> postDirectInwardReceipt({
    required String tenantId,
    required String supplierId,
    required String supplierInvoiceNumber,
    required DateTime receiptDate,
    required List<Map<String, dynamic>> items,
    required String notes,
    String? locationId,
    String? requestId,
  }) async {
    return PurchaseService().createPurchase(
      tenantId: tenantId,
      supplierId: supplierId,
      supplierInvoiceNumber: supplierInvoiceNumber,
      purchaseDate: receiptDate,
      dueDate: null,
      items: items,
      additionalCharges: 0,
      initialPayment: 0,
      paymentMethod: 'credit',
      notes: notes,
      locationId: locationId,
      requestId: requestId,
    );
  }
}
