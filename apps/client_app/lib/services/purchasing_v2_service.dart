import 'package:erp_core/erp_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_session.dart';
import '../features/gst/gst_v520_gateway.dart';
import 'gst_v520_request_id_store.dart';
import 'location_scope_service.dart';
import 'thq_api_service.dart';

class PurchasingV2Service {
  final ThqApiService _api = ThqApiService();
  final GstV520RequestIdStore _gstRequestIds = GstV520RequestIdStore();
  SupabaseClient get _supabase => Supabase.instance.client;

  bool _isReadOnly(ThqApiRequest request) {
    if (request.resource == 'purchasing-dashboard' ||
        request.resource == 'supplier-ledger-v2' ||
        request.resource == 'purchase-price-history' ||
        request.resource == 'purchase-cycle') {
      return true;
    }
    return request.action == 'list' || request.action == 'detail';
  }

  bool _isCompatibilityFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('unknown thq api resource') ||
        message.contains('unsupported ') ||
        message.contains('function not found') ||
        message.contains('404');
  }

  /// THQ API is the primary transport. Read operations can safely retry by RPC.
  /// Mutations use the RPC path only for a clear stale/missing edge contract,
  /// preventing a network response failure from accidentally creating twice.
  Future<dynamic> _call(ThqApiRequest request) async {
    try {
      return await _api.call(request);
    } catch (apiError) {
      if (!_isReadOnly(request) && !_isCompatibilityFailure(apiError)) {
        rethrow;
      }
      try {
        return await _rpcFallback(request);
      } catch (rpcError) {
        throw StateError(
          'Purchasing request failed through THQ API ($apiError) and the compatibility RPC path ($rpcError).',
        );
      }
    }
  }

  Future<dynamic> _rpcFallback(ThqApiRequest request) {
    final payload = request.payload;
    final base = <String, dynamic>{'p_tenant_id': request.tenantId};
    late String rpc;
    late Map<String, dynamic> params;

    switch (request.resource) {
      case 'purchase-requests':
        switch (request.action) {
          case 'list':
            rpc = 'purchase_request_list_v484';
            params = {
              ...base,
              'p_location_id': payload['location_id'],
              'p_status': payload['status'],
              'p_query': payload['query'] ?? '',
              'p_limit': payload['limit'] ?? 500,
            };
          case 'detail':
            rpc = 'purchase_request_detail_v484';
            params = {...base, 'p_request_id': payload['request_id']};
          case 'create':
            rpc = 'purchase_request_create_v484';
            params = {
              ...base,
              'p_location_id': payload['location_id'],
              'p_items': payload['items'] ?? const [],
              'p_required_date': payload['required_date'],
              'p_priority': payload['priority'] ?? 'normal',
              'p_preferred_supplier_id': payload['preferred_supplier_id'],
              'p_purpose': payload['purpose'] ?? '',
              'p_notes': payload['notes'] ?? '',
            };
          case 'status':
            rpc = 'purchase_request_status_v484';
            params = {
              ...base,
              'p_request_id': payload['request_id'],
              'p_status': payload['status'],
              'p_note': payload['note'] ?? '',
            };
          default:
            throw UnsupportedError(
              'Unsupported purchase-requests action ${request.action}.',
            );
        }
      case 'purchase-orders':
        switch (request.action) {
          case 'list':
            rpc = 'purchase_order_list_v484';
            params = {
              ...base,
              'p_location_id': payload['location_id'],
              'p_status': payload['status'],
              'p_query': payload['query'] ?? '',
              'p_limit': payload['limit'] ?? 500,
            };
          case 'detail':
            rpc = 'purchase_order_detail_v484';
            params = {
              ...base,
              'p_purchase_order_id': payload['purchase_order_id'],
            };
          case 'create':
            rpc = 'purchase_order_create_v484';
            params = {
              ...base,
              'p_location_id': payload['location_id'],
              'p_supplier_id': payload['supplier_id'],
              'p_items': payload['items'] ?? const [],
              'p_expected_date': payload['expected_date'],
              'p_notes': payload['notes'] ?? '',
              'p_request_id': payload['request_id'],
            };
          case 'status':
            rpc = 'purchase_order_status_v480';
            params = {
              ...base,
              'p_purchase_order_id': payload['purchase_order_id'],
              'p_status': payload['status'],
              'p_reason': payload['reason'] ?? '',
            };
          case 'decide':
            rpc = 'purchase_order_decide_v484';
            params = {
              ...base,
              'p_purchase_order_id': payload['purchase_order_id'],
              'p_approve': payload['approve'] ?? false,
              'p_note': payload['note'] ?? '',
            };
          default:
            throw UnsupportedError(
              'Unsupported purchase-orders action ${request.action}.',
            );
        }
      case 'goods-receipts':
        switch (request.action) {
          case 'list':
            rpc = 'goods_receipt_list_v484';
            params = {
              ...base,
              'p_location_id': payload['location_id'],
              'p_status': payload['status'],
              'p_query': payload['query'] ?? '',
              'p_limit': payload['limit'] ?? 500,
            };
          case 'detail':
            rpc = 'goods_receipt_detail_v484';
            params = {
              ...base,
              'p_goods_receipt_id': payload['goods_receipt_id'],
            };
          case 'create':
            rpc = 'goods_receipt_create_v484';
            params = {
              ...base,
              'p_purchase_order_id': payload['purchase_order_id'],
              'p_receipt_date': payload['receipt_date'],
              'p_items': payload['items'] ?? const [],
              'p_supplier_delivery_note':
                  payload['supplier_delivery_note'] ?? '',
              'p_notes': payload['notes'] ?? '',
            };
          case 'post':
            rpc = 'goods_receipt_post_v484';
            params = {
              ...base,
              'p_goods_receipt_id': payload['goods_receipt_id'],
              'p_device_id': payload['device_id'],
            };
          case 'cancel':
            rpc = 'goods_receipt_cancel_v490';
            params = {
              ...base,
              'p_goods_receipt_id': payload['goods_receipt_id'],
              'p_reason': payload['reason'] ?? '',
            };
          default:
            throw UnsupportedError(
              'Unsupported goods-receipts action ${request.action}.',
            );
        }
      case 'purchase-invoices':
        switch (request.action) {
          case 'list':
            rpc = 'purchase_invoice_list_v484';
            params = {
              ...base,
              'p_location_id': payload['location_id'],
              'p_status': payload['status'],
              'p_query': payload['query'] ?? '',
              'p_limit': payload['limit'] ?? 500,
            };
          case 'detail':
            rpc = 'purchase_invoice_detail_v484';
            params = {
              ...base,
              'p_purchase_invoice_id': payload['purchase_invoice_id'],
            };
          case 'create':
            rpc = 'purchase_invoice_create_v489';
            params = {
              ...base,
              'p_purchase_order_id': payload['purchase_order_id'],
              'p_supplier_invoice_number': payload['supplier_invoice_number'],
              'p_invoice_date': payload['invoice_date'],
              'p_due_date': payload['due_date'],
              'p_items': payload['items'] ?? const [],
              'p_additional_charges': payload['additional_charges'] ?? 0,
              'p_round_off': payload['round_off'] ?? 0,
              'p_notes': payload['notes'] ?? '',
            };
          case 'post':
            rpc = 'purchase_invoice_post_v484';
            params = {
              ...base,
              'p_purchase_invoice_id': payload['purchase_invoice_id'],
            };
          case 'void':
            rpc = 'purchase_invoice_void_v490';
            params = {
              ...base,
              'p_purchase_invoice_id': payload['purchase_invoice_id'],
              'p_reason': payload['reason'] ?? '',
            };
          default:
            throw UnsupportedError(
              'Unsupported purchase-invoices action ${request.action}.',
            );
        }
      case 'supplier-payments-v2':
        switch (request.action) {
          case 'list':
            rpc = 'supplier_payment_list_v484';
            params = {
              ...base,
              'p_location_id': payload['location_id'],
              'p_supplier_id': payload['supplier_id'],
              'p_query': payload['query'] ?? '',
              'p_limit': payload['limit'] ?? 500,
            };
          case 'create':
            rpc = 'supplier_payment_create_v490';
            params = {
              ...base,
              'p_location_id': payload['location_id'],
              'p_supplier_id': payload['supplier_id'],
              'p_payment_date': payload['payment_date'],
              'p_amount': payload['amount'],
              'p_payment_method': payload['payment_method'],
              'p_allocations': payload['allocations'] ?? const [],
              'p_reference_number': payload['reference_number'] ?? '',
              'p_notes': payload['notes'] ?? '',
              'p_device_id': payload['device_id'],
            };
          case 'void':
            rpc = 'supplier_payment_void_v490';
            params = {
              ...base,
              'p_supplier_payment_id': payload['supplier_payment_id'],
              'p_reason': payload['reason'] ?? '',
            };
          default:
            throw UnsupportedError(
              'Unsupported supplier-payments-v2 action ${request.action}.',
            );
        }
      case 'supplier-ledger-v2':
        rpc = 'suppliers_get_statement_v484';
        params = {
          ...base,
          'p_supplier_id': payload['supplier_id'],
          'p_from': payload['from'],
          'p_to': payload['to'],
          'p_location_id': payload['location_id'],
        };
      case 'purchase-price-history':
        rpc = 'purchase_price_history_v484';
        params = {
          ...base,
          'p_variant_id': payload['variant_id'],
          'p_supplier_id': payload['supplier_id'],
          'p_location_id': payload['location_id'],
          'p_query': payload['query'] ?? '',
          'p_limit': payload['limit'] ?? 1000,
        };
      case 'purchasing-dashboard':
        rpc = 'purchasing_dashboard_v484';
        params = {...base, 'p_location_id': payload['location_id']};
      case 'purchase-cycle':
        rpc = 'purchase_cycle_summary_v490';
        params = {...base, 'p_purchase_order_id': payload['purchase_order_id']};
      default:
        throw UnsupportedError('No compatibility RPC for ${request.resource}.');
    }

    return _supabase.rpc(rpc, params: params);
  }

  String? _readLocation(ClientSession session) =>
      LocationScopeService.currentForRead(session);

  String _writeLocation(ClientSession session) =>
      LocationScopeService.currentForCreate(session);

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List? ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);

  Map<String, dynamic> _map(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  Future<Map<String, dynamic>> dashboard(ClientSession session) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchasing-dashboard',
        payload: {'location_id': _readLocation(session)},
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> requests(
    ClientSession session, {
    String? status,
    String query = '',
  }) async => _rows(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-requests',
        action: 'list',
        payload: {
          'location_id': _readLocation(session),
          'status': status,
          'query': query,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> requestDetail(
    ClientSession session,
    String requestId,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-requests',
        action: 'detail',
        payload: {'request_id': requestId},
      ),
    ),
  );

  Future<Map<String, dynamic>> createRequest(
    ClientSession session, {
    required List<Map<String, dynamic>> items,
    DateTime? requiredDate,
    String priority = 'normal',
    String? preferredSupplierId,
    String purpose = '',
    String notes = '',
  }) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-requests',
        action: 'create',
        payload: {
          'location_id': _writeLocation(session),
          'items': items,
          'required_date': requiredDate?.toIso8601String().split('T').first,
          'priority': priority,
          'preferred_supplier_id': preferredSupplierId,
          'purpose': purpose,
          'notes': notes,
        },
      ),
    ),
  );

  Future<void> setRequestStatus(
    ClientSession session, {
    required String requestId,
    required String status,
    String note = '',
  }) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-requests',
        action: 'status',
        payload: {'request_id': requestId, 'status': status, 'note': note},
      ),
    );
  }

  Future<List<Map<String, dynamic>>> orders(
    ClientSession session, {
    String? status,
    String query = '',
  }) async => _rows(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-orders',
        action: 'list',
        payload: {
          'location_id': _readLocation(session),
          'status': status,
          'query': query,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> orderDetail(
    ClientSession session,
    String orderId,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-orders',
        action: 'detail',
        payload: {'purchase_order_id': orderId},
      ),
    ),
  );

  Future<Map<String, dynamic>> createOrder(
    ClientSession session, {
    required String supplierId,
    required List<Map<String, dynamic>> items,
    String? requestId,
    DateTime? expectedDate,
    String notes = '',
  }) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-orders',
        action: 'create',
        payload: {
          'location_id': _writeLocation(session),
          'supplier_id': supplierId,
          'items': items,
          'request_id': requestId,
          'expected_date': expectedDate?.toIso8601String().split('T').first,
          'notes': notes,
        },
      ),
    ),
  );

  Future<void> setOrderStatus(
    ClientSession session, {
    required String orderId,
    required String status,
    String reason = '',
  }) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-orders',
        action: 'status',
        payload: {
          'purchase_order_id': orderId,
          'status': status,
          'reason': reason,
        },
      ),
    );
  }

  Future<void> decideOrder(
    ClientSession session, {
    required String orderId,
    required bool approve,
    String note = '',
  }) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-orders',
        action: 'decide',
        payload: {
          'purchase_order_id': orderId,
          'approve': approve,
          'note': note,
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> grns(
    ClientSession session, {
    String? status,
    String query = '',
  }) async => _rows(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'goods-receipts',
        action: 'list',
        payload: {
          'location_id': _readLocation(session),
          'status': status,
          'query': query,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> grnDetail(
    ClientSession session,
    String grnId,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'goods-receipts',
        action: 'detail',
        payload: {'goods_receipt_id': grnId},
      ),
    ),
  );

  Future<Map<String, dynamic>> createGrn(
    ClientSession session, {
    required String purchaseOrderId,
    required List<Map<String, dynamic>> items,
    DateTime? receiptDate,
    String deliveryNote = '',
    String notes = '',
  }) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'goods-receipts',
        action: 'create',
        payload: {
          'purchase_order_id': purchaseOrderId,
          'receipt_date': (receiptDate ?? DateTime.now())
              .toIso8601String()
              .split('T')
              .first,
          'items': items,
          'supplier_delivery_note': deliveryNote,
          'notes': notes,
        },
      ),
    ),
  );

  Future<void> postGrn(ClientSession session, String grnId) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'goods-receipts',
        action: 'post',
        payload: {
          'goods_receipt_id': grnId,
          'device_id': session.device?.deviceId,
        },
      ),
    );
  }

  Future<void> cancelGrn(
    ClientSession session,
    String grnId,
    String reason,
  ) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'goods-receipts',
        action: 'cancel',
        payload: {'goods_receipt_id': grnId, 'reason': reason},
      ),
    );
  }

  Future<List<Map<String, dynamic>>> invoices(
    ClientSession session, {
    String? status,
    String query = '',
  }) async => _rows(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-invoices',
        action: 'list',
        payload: {
          'location_id': _readLocation(session),
          'status': status,
          'query': query,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> invoiceDetail(
    ClientSession session,
    String invoiceId,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-invoices',
        action: 'detail',
        payload: {'purchase_invoice_id': invoiceId},
      ),
    ),
  );

  Future<Map<String, dynamic>> createInvoice(
    ClientSession session, {
    required String purchaseOrderId,
    required String supplierInvoiceNumber,
    required List<Map<String, dynamic>> items,
    DateTime? invoiceDate,
    DateTime? dueDate,
    double additionalCharges = 0,
    double roundOff = 0,
    String notes = '',
  }) async {
    final invoiceDay = (invoiceDate ?? DateTime.now())
        .toIso8601String()
        .split('T')
        .first;
    final dueDay = dueDate?.toIso8601String().split('T').first;
    final payload = <String, dynamic>{
      'purchase_order_id': purchaseOrderId,
      'supplier_invoice_number': supplierInvoiceNumber.trim(),
      'invoice_date': invoiceDay,
      'due_date': dueDay,
      'items': items,
      'additional_charges': additionalCharges,
      'round_off': roundOff,
      'notes': notes.trim(),
    };

    final lease = await _gstRequestIds.acquire(
      tenantId: session.business.id,
      operation: 'purchase_invoice_v2',
      payload: payload,
    );
    final gateway = GstV520Gateway(
      client: _supabase,
      tenantId: session.business.id,
      channel: GstV520Channel.client,
      deviceId: session.device?.deviceId,
    );
    await gateway.initialize();
    final rpc = gateway.routeFor('purchase_invoice_v2');

    try {
      final raw = await _supabase.rpc(
        rpc,
        params: {
          'p_tenant_id': session.business.id,
          'p_purchase_order_id': purchaseOrderId,
          'p_supplier_invoice_number': supplierInvoiceNumber.trim(),
          'p_invoice_date': invoiceDay,
          'p_due_date': dueDay,
          'p_items': items,
          'p_additional_charges': additionalCharges,
          'p_round_off': roundOff,
          'p_notes': notes.trim(),
          'p_request_id': lease.requestId,
        },
      );
      if (raw is! Map) throw StateError('Unexpected response from $rpc.');
      await _gstRequestIds.complete(lease);
      return Map<String, dynamic>.from(raw);
    } catch (error) {
      throw StateError(
        'Authoritative GST v5.2 Purchase Invoice failed. Legacy invoice '
        'fallback is disabled. Retry the unchanged invoice. $error',
      );
    }
  }

  Future<void> postInvoice(ClientSession session, String invoiceId) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-invoices',
        action: 'post',
        payload: {'purchase_invoice_id': invoiceId},
      ),
    );
  }

  Future<void> voidInvoice(
    ClientSession session,
    String invoiceId,
    String reason,
  ) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-invoices',
        action: 'void',
        payload: {'purchase_invoice_id': invoiceId, 'reason': reason},
      ),
    );
  }

  Future<List<Map<String, dynamic>>> payments(
    ClientSession session, {
    String? supplierId,
    String query = '',
  }) async => _rows(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'supplier-payments-v2',
        action: 'list',
        payload: {
          'location_id': _readLocation(session),
          'supplier_id': supplierId,
          'query': query,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> createPayment(
    ClientSession session, {
    required String supplierId,
    required double amount,
    required String paymentMethod,
    List<Map<String, dynamic>> allocations = const [],
    DateTime? paymentDate,
    String reference = '',
    String notes = '',
  }) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'supplier-payments-v2',
        action: 'create',
        payload: {
          'location_id': _writeLocation(session),
          'supplier_id': supplierId,
          'payment_date': (paymentDate ?? DateTime.now())
              .toIso8601String()
              .split('T')
              .first,
          'amount': amount,
          'payment_method': paymentMethod,
          'allocations': allocations,
          'reference_number': reference,
          'notes': notes,
          'device_id': session.device?.deviceId,
        },
      ),
    ),
  );

  Future<void> voidPayment(
    ClientSession session,
    String paymentId,
    String reason,
  ) async {
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'supplier-payments-v2',
        action: 'void',
        payload: {'supplier_payment_id': paymentId, 'reason': reason},
      ),
    );
  }

  Future<Map<String, dynamic>> supplierLedger(
    ClientSession session, {
    required String supplierId,
    DateTime? from,
    DateTime? to,
  }) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'supplier-ledger-v2',
        payload: {
          'supplier_id': supplierId,
          'location_id': _readLocation(session),
          'from': from?.toIso8601String().split('T').first,
          'to': to?.toIso8601String().split('T').first,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> cycleSummary(
    ClientSession session,
    String purchaseOrderId,
  ) async => _map(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-cycle',
        payload: {'purchase_order_id': purchaseOrderId},
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> priceHistory(
    ClientSession session, {
    String? variantId,
    String? supplierId,
    String query = '',
  }) async => _rows(
    await _call(
      ThqApiRequest(
        tenantId: session.business.id,
        resource: 'purchase-price-history',
        payload: {
          'variant_id': variantId,
          'supplier_id': supplierId,
          'location_id': _readLocation(session),
          'query': query,
          'limit': 1000,
        },
      ),
    ),
  );
}
