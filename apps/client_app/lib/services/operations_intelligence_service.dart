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

  Future<Map<String, dynamic>> financialIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'financial-intelligence',
        payload: {
          'location_id': locationId,
          'days': days,
          'query': query,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> expenseIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'expense-intelligence',
        payload: {
          'location_id': locationId,
          'days': days,
          'query': query,
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

  Future<Map<String, dynamic>> actionCentre({
    required String tenantId,
    String? locationId,
    String? engine,
    String? severity,
    String? status,
    String? category,
    String query = '',
    int limit = 100,
    int offset = 0,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'action-centre',
        payload: {
          'location_id': locationId,
          'engine': engine,
          'severity': severity,
          'status': status,
          'category': category,
          'query': query,
          'limit': limit,
          'offset': offset,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> actionCentreScan({
    required String tenantId,
    String? locationId,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'action-centre-scan',
        payload: {
          'location_id': locationId,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> transitionFinding({
    required String tenantId,
    required String findingId,
    required String toStatus,
    String reviewNotes = '',
    String? assignedTo,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'finding-transition',
        payload: {
          'finding_id': findingId,
          'to_status': toStatus,
          'review_notes': reviewNotes,
          'assigned_to': assignedTo,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> findingReviews({
    required String tenantId,
    required String findingId,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'finding-reviews',
        payload: {
          'finding_id': findingId,
        },
      ),
    );
    return _rows(data);
  }

  Future<Map<String, dynamic>> operationalEfficiency({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'operational-efficiency',
        payload: {
          'location_id': locationId,
          'days': days,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> operationalEfficiencyScan({
    required String tenantId,
    String? locationId,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'operational-efficiency-scan',
        payload: {
          'location_id': locationId,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> workforceIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'workforce-intelligence',
        payload: {
          'location_id': locationId,
          'days': days,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> workforceIntelligenceScan({
    required String tenantId,
    String? locationId,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'workforce-intelligence-scan',
        payload: {
          'location_id': locationId,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> predictiveIntelligence({
    required String tenantId,
    String? locationId,
    int horizonDays = 30,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'predictive-intelligence',
        payload: {
          'location_id': locationId,
          'horizon_days': horizonDays,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> predictiveIntelligenceScan({
    required String tenantId,
    String? locationId,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'predictive-intelligence-scan',
        payload: {
          'location_id': locationId,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> simulateBusinessScenario({
    required String tenantId,
    required String category,
    required Map<String, dynamic> params,
    String? locationId,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'business-simulation',
        action: 'simulate',
        payload: {
          'category': category,
          'params': params,
          'location_id': locationId,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> saveBusinessSimulation({
    required String tenantId,
    required String scenarioName,
    required String category,
    required Map<String, dynamic> params,
    required Map<String, dynamic> results,
    String? locationId,
    String? notes,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'business-simulation',
        action: 'save',
        payload: {
          'scenario_name': scenarioName,
          'category': category,
          'params': params,
          'results': results,
          'location_id': locationId,
          'notes': notes,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> listBusinessSimulations({
    required String tenantId,
    String? category,
    String? locationId,
    int limit = 50,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'business-simulation',
        action: 'list',
        payload: {
          'category': category,
          'location_id': locationId,
          'limit': limit,
        },
      ),
    );
    return _rows(data);
  }

  Future<Map<String, dynamic>> deleteBusinessSimulation({
    required String tenantId,
    required String simulationId,
  }) async {
    final data = await _api.call(
      ThqApiRequest(
        tenantId: tenantId,
        resource: 'business-simulation',
        action: 'delete',
        payload: {
          'simulation_id': simulationId,
        },
      ),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _rows(dynamic data) => (data as List? ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}
