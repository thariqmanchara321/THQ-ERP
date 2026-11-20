import 'package:erp_core/erp_core.dart';

import 'thq_api_service.dart';

class OperationsIntelligenceService {
  final ThqApiService _api = ThqApiService();

  Future<Map<String, dynamic>> attention({
    required String tenantId,
    String? locationId,
    int days = 30,
    String? version,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'attention',
        payload: {
          'location_id': locationId,
          'days': days,
          'version': ?version,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> operationsSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'operations-summary',
        payload: {'location_id': locationId, 'days': days},
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> salesIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'sales-intelligence',
        payload: {
          'location_id': locationId,
          'days': days,
          'query': query,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> purchaseIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'purchase-intelligence',
        payload: {
          'location_id': locationId,
          'days': days,
          'query': query,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> supplierIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 200,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'supplier-intelligence',
        payload: {
          'location_id': locationId,
          'days': days,
          'query': query,
          'limit': limit,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> procurementIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 500,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'procurement-intelligence',
        payload: {
          'location_id': locationId,
          'days': days,
          'query': query,
          'limit': limit,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> inventory({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    bool useV830 = false,
  }) async => _rows(
    await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'inventory-intelligence',
        payload: {
          'location_id': locationId,
          'days': days,
          'query': query,
          if (useV830) 'version': 'v830',
        },
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> rebalancing({
    required String tenantId,
    String? locationId,
    int days = 30,
    int limit = 100,
  }) async => _rows(
    await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'inventory-rebalancing',
        payload: {
          'location_id': locationId,
          'days': days,
          'limit': limit,
        },
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> customerCredit({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async => _rows(
    await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'customer-credit',
        payload: {'location_id': locationId, 'query': query},
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> supplierPayables({
    required String tenantId,
    String? locationId,
    String query = '',
  }) async => _rows(
    await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'supplier-payables',
        payload: {'location_id': locationId, 'query': query},
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> reorder({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async => _rows(
    await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'reorder-suggestions',
        payload: {'location_id': locationId, 'days': days, 'query': query},
      ),
    ),
  );

  Future<List<Map<String, dynamic>>> purchaseOrders({
    required String tenantId,
    String? locationId,
    String? status,
    String query = '',
  }) async => _rows(
    await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'purchase-orders',
        action: 'list',
        payload: {'location_id': locationId, 'status': status, 'query': query},
      ),
    ),
  );

  Future<Map<String, dynamic>> purchaseOrderDetail({
    required String tenantId,
    required String purchaseOrderId,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'purchase-orders',
        action: 'detail',
        payload: {'purchase_order_id': purchaseOrderId},
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createPurchaseOrder({
    required String tenantId,
    required String locationId,
    required String supplierId,
    required List<Map<String, dynamic>> items,
    String notes = '',
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'purchase-orders',
        action: 'create',
        payload: {
          'location_id': locationId,
          'supplier_id': supplierId,
          'items': items,
          'notes': notes,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<void> setPurchaseOrderStatus({
    required String tenantId,
    required String purchaseOrderId,
    required String status,
    String reason = '',
  }) async {
    await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'purchase-orders',
        action: 'status',
        payload: {
          'purchase_order_id': purchaseOrderId,
          'status': status,
          'reason': reason,
        },
      ),
    );
  }

  Future<void> decidePurchaseOrder({
    required String tenantId,
    required String purchaseOrderId,
    required bool approve,
    String note = '',
  }) async {
    await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'purchase-orders',
        action: 'decide',
        payload: {
          'purchase_order_id': purchaseOrderId,
          'approve': approve,
          'note': note,
        },
      ),
    );
  }

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List? ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}
