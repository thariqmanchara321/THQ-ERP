import 'operations_intelligence_models.dart';

typedef RpcInvoker = Future<dynamic> Function(String rpcName, {Map<String, dynamic>? params});

abstract class OperationsIntelligenceRepository {
  Future<ExecutiveHealthSnapshot> getExecutiveSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  });

  Future<List<InsightRecord>> getInsights({
    required String tenantId,
    String? locationId,
    IntelligenceEngineType? engine,
    InsightSeverity? severity,
    InsightStatus? status,
    String query = '',
    int limit = 200,
    int offset = 0,
  });

  Future<String> saveInsight(InsightRecord insight, {String? dedupKey});

  Future<bool> updateInsightStatus({
    required String tenantId,
    required String insightId,
    required InsightStatus status,
    String? resolutionNote,
  });

  Future<List<ActionProposal>> getActions({
    required String tenantId,
    String? locationId,
    ActionStatus? status,
    int limit = 200,
  });

  Future<String> createAction(ActionProposal proposal);

  Future<Map<String, dynamic>> decideAction({
    required String tenantId,
    required String actionId,
    required bool approve,
    String note = '',
  });

  Future<List<Map<String, dynamic>>> getInventoryIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 1000,
  });

  Future<List<Map<String, dynamic>>> getCustomerCreditIntelligence({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 1000,
  });

  Future<List<Map<String, dynamic>>> getSupplierPayablesIntelligence({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 1000,
  });
}

/// Production repository invoking PostgreSQL RPCs directly.
class RpcOperationsIntelligenceRepository implements OperationsIntelligenceRepository {
  final RpcInvoker rpc;

  const RpcOperationsIntelligenceRepository(this.rpc);

  List<Map<String, dynamic>> _rows(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  @override
  Future<ExecutiveHealthSnapshot> getExecutiveSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    final raw = await rpc(
      'operations_intelligence_summary_v830',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_days': days,
      },
    );
    if (raw is Map) {
      return ExecutiveHealthSnapshot.fromMap(Map<String, dynamic>.from(raw));
    }
    throw StateError('Unexpected summary response from operations_intelligence_summary_v830');
  }

  @override
  Future<List<InsightRecord>> getInsights({
    required String tenantId,
    String? locationId,
    IntelligenceEngineType? engine,
    InsightSeverity? severity,
    InsightStatus? status,
    String query = '',
    int limit = 200,
    int offset = 0,
  }) async {
    final raw = await rpc(
      'erp_intelligence_insights_list_v830',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_engine': engine?.code,
        'p_severity': severity?.code,
        'p_status': status?.code,
        'p_query': query,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return _rows(raw).map((m) => InsightRecord.fromMap(m)).toList();
  }

  @override
  Future<String> saveInsight(InsightRecord insight, {String? dedupKey}) async {
    final raw = await rpc(
      'erp_intelligence_insight_save_v830',
      params: {
        'p_tenant_id': insight.tenantId,
        'p_location_id': insight.locationId,
        'p_engine': insight.engine.code,
        'p_category': insight.category,
        'p_severity': insight.severity.code,
        'p_priority': insight.priority.code,
        'p_title': insight.title,
        'p_description': insight.description,
        'p_evidence': insight.evidence.toMap(),
        'p_source_references': insight.sourceReferences.map((e) => e.toMap()).toList(),
        'p_confidence': insight.confidence,
        'p_dedup_key': dedupKey,
      },
    );
    return raw?.toString() ?? '';
  }

  @override
  Future<bool> updateInsightStatus({
    required String tenantId,
    required String insightId,
    required InsightStatus status,
    String? resolutionNote,
  }) async {
    final raw = await rpc(
      'erp_intelligence_insight_status_v830',
      params: {
        'p_tenant_id': tenantId,
        'p_insight_id': insightId,
        'p_status': status.code,
        'p_resolution_note': resolutionNote,
      },
    );
    return raw == true;
  }

  @override
  Future<List<ActionProposal>> getActions({
    required String tenantId,
    String? locationId,
    ActionStatus? status,
    int limit = 200,
  }) async {
    final raw = await rpc(
      'erp_intelligence_actions_list_v830',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_status': status?.code,
        'p_limit': limit,
      },
    );
    return _rows(raw).map((m) => ActionProposal.fromMap(m)).toList();
  }

  @override
  Future<String> createAction(ActionProposal proposal) async {
    final raw = await rpc(
      'erp_intelligence_action_create_v830',
      params: {
        'p_tenant_id': proposal.tenantId,
        'p_location_id': proposal.locationId,
        'p_insight_id': proposal.insightId,
        'p_action_type': proposal.actionType.code,
        'p_payload': proposal.payload,
        'p_preview_summary': proposal.previewSummary,
        'p_required_permission': proposal.requiredPermission,
      },
    );
    return raw?.toString() ?? '';
  }

  @override
  Future<Map<String, dynamic>> decideAction({
    required String tenantId,
    required String actionId,
    required bool approve,
    String note = '',
  }) async {
    final raw = await rpc(
      'erp_intelligence_action_decide_v830',
      params: {
        'p_tenant_id': tenantId,
        'p_action_id': actionId,
        'p_approve': approve,
        'p_note': note,
      },
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  @override
  Future<List<Map<String, dynamic>>> getInventoryIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 1000,
  }) async {
    final raw = await rpc(
      'inventory_intelligence_v830',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_days': days,
        'p_query': query,
        'p_limit': limit,
      },
    );
    return _rows(raw);
  }

  @override
  Future<List<Map<String, dynamic>>> getCustomerCreditIntelligence({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 1000,
  }) async {
    final raw = await rpc(
      'customer_credit_intelligence_v480',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_query': query,
        'p_limit': limit,
      },
    );
    return _rows(raw);
  }

  @override
  Future<List<Map<String, dynamic>>> getSupplierPayablesIntelligence({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 1000,
  }) async {
    final raw = await rpc(
      'supplier_payables_intelligence_v480',
      params: {
        'p_tenant_id': tenantId,
        'p_location_id': locationId,
        'p_query': query,
        'p_limit': limit,
      },
    );
    return _rows(raw);
  }
}

/// Hermetic in-memory mock repository for tests.
class MockOperationsIntelligenceRepository implements OperationsIntelligenceRepository {
  final List<InsightRecord> insights = [];
  final List<ActionProposal> actions = [];
  ExecutiveHealthSnapshot? customSnapshot;

  MockOperationsIntelligenceRepository() {
    _seedDefaultData();
  }

  void _seedDefaultData() {
    insights.add(
      InsightRecord(
        id: 'ins-1',
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        engine: IntelligenceEngineType.inventory,
        category: 'stockout_risk',
        severity: InsightSeverity.critical,
        priority: InsightPriority.urgent,
        title: 'Critical Stockout Risk: UltraTech Cement 50kg',
        description: 'Current stock is 4 units with average daily sales of 12 units. Projected stockout in 0.3 days.',
        evidence: const InsightEvidence(
          currentValue: 4,
          threshold: 20,
          metricUnit: 'bags',
        ),
        dataFreshness: DateTime.now(),
        status: InsightStatus.newInsight,
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
    );

    actions.add(
      ActionProposal(
        id: 'act-1',
        tenantId: 'tenant-1',
        locationId: 'loc-1',
        insightId: 'ins-1',
        actionType: ActionType.createPurchaseOrder,
        payload: {
          'supplier_id': 'sup-1',
          'items': [
            {'variant_id': 'var-c1', 'quantity': 100, 'unit_cost': 380.0}
          ]
        },
        previewSummary: 'Create PO for 100 bags UltraTech Cement from Birla Suppliers',
        requiredPermission: 'purchases.manage',
        status: ActionStatus.pendingApproval,
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    );
  }

  @override
  Future<ExecutiveHealthSnapshot> getExecutiveSummary({
    required String tenantId,
    String? locationId,
    int days = 30,
  }) async {
    return customSnapshot ??
        ExecutiveHealthSnapshot(
          periodDays: days,
          fromDate: DateTime.now().subtract(Duration(days: days)),
          toDate: DateTime.now(),
          grossSales: 450000.0,
          salesReturns: 12000.0,
          netSales: 438000.0,
          grossProfit: 98000.0,
          grossMarginPct: 22.37,
          expenses: 32000.0,
          netOperatingProfit: 66000.0,
          orderCount: 310,
          averageOrderValue: 1412.90,
          inventoryValue: 850000.0,
          totalMonitoredVariants: 240,
          lowStockCount: 14,
          outOfStockCount: 3,
          deadStockCount: 8,
          overstockCount: 5,
          receivables: 68000.0,
          overdueReceivables: 14000.0,
          payables: 52000.0,
          overduePayables: 6000.0,
          unresolvedInsightsCount: insights.where((i) => i.status == InsightStatus.newInsight).length,
          criticalInsightsCount: insights.where((i) => i.severity == InsightSeverity.critical).length,
          pendingActionsCount: actions.where((a) => a.status == ActionStatus.pendingApproval).length,
          compositeHealthScore: 88.5,
          topProducts: const [
            {'product_name': 'UltraTech Cement 50kg', 'revenue': 145000.0, 'margin_pct': 24.5},
            {'product_name': 'TMT Steel 12mm', 'revenue': 112000.0, 'margin_pct': 18.2},
          ],
          hourlyDistribution: const [
            {'hour': 10, 'order_count': 28, 'sales_amount': 42000.0},
            {'hour': 14, 'order_count': 35, 'sales_amount': 55000.0},
          ],
        );
  }

  @override
  Future<List<InsightRecord>> getInsights({
    required String tenantId,
    String? locationId,
    IntelligenceEngineType? engine,
    InsightSeverity? severity,
    InsightStatus? status,
    String query = '',
    int limit = 200,
    int offset = 0,
  }) async {
    var filtered = insights.where((i) => i.tenantId == tenantId || i.tenantId == 'tenant-1');
    if (locationId != null) {
      filtered = filtered.where((i) => i.locationId == null || i.locationId == locationId);
    }
    if (engine != null) filtered = filtered.where((i) => i.engine == engine);
    if (severity != null) filtered = filtered.where((i) => i.severity == severity);
    if (status != null) filtered = filtered.where((i) => i.status == status);
    if (query.trim().isNotEmpty) {
      final q = query.toLowerCase();
      filtered = filtered.where((i) => i.title.toLowerCase().contains(q) || i.description.toLowerCase().contains(q));
    }
    return filtered.skip(offset).take(limit).toList();
  }

  @override
  Future<String> saveInsight(InsightRecord insight, {String? dedupKey}) async {
    final idx = insights.indexWhere((i) => i.id == insight.id);
    if (idx >= 0) {
      insights[idx] = insight;
      return insight.id;
    } else {
      final newId = 'ins-${insights.length + 1}';
      insights.add(insight.copyWith(id: newId));
      return newId;
    }
  }

  @override
  Future<bool> updateInsightStatus({
    required String tenantId,
    required String insightId,
    required InsightStatus status,
    String? resolutionNote,
  }) async {
    final idx = insights.indexWhere((i) => i.id == insightId && (i.tenantId == tenantId || i.tenantId == 'tenant-1'));
    if (idx >= 0) {
      insights[idx] = insights[idx].copyWith(
        status: status,
        resolutionNote: resolutionNote,
        resolvedAt: (status == InsightStatus.resolved || status == InsightStatus.dismissed) ? DateTime.now() : null,
      );
      return true;
    }
    return false;
  }

  @override
  Future<List<ActionProposal>> getActions({
    required String tenantId,
    String? locationId,
    ActionStatus? status,
    int limit = 200,
  }) async {
    var filtered = actions.where((a) => a.tenantId == tenantId || a.tenantId == 'tenant-1');
    if (locationId != null) {
      filtered = filtered.where((a) => a.locationId == null || a.locationId == locationId);
    }
    if (status != null) filtered = filtered.where((a) => a.status == status);
    return filtered.take(limit).toList();
  }

  @override
  Future<String> createAction(ActionProposal proposal) async {
    final id = 'act-${actions.length + 1}';
    actions.add(proposal.copyWith(id: id));
    return id;
  }

  @override
  Future<Map<String, dynamic>> decideAction({
    required String tenantId,
    required String actionId,
    required bool approve,
    String note = '',
  }) async {
    final idx = actions.indexWhere((a) => a.id == actionId && (a.tenantId == tenantId || a.tenantId == 'tenant-1'));
    if (idx >= 0) {
      final newStatus = approve ? ActionStatus.approved : ActionStatus.rejected;
      actions[idx] = actions[idx].copyWith(
        status: newStatus,
        approvedAt: DateTime.now(),
        executionResult: {'decision_note': note},
      );
      return {'action_id': actionId, 'status': newStatus.code};
    }
    throw StateError('Action not found');
  }

  @override
  Future<List<Map<String, dynamic>>> getInventoryIntelligence({
    required String tenantId,
    String? locationId,
    int days = 30,
    String query = '',
    int limit = 1000,
  }) async => [
    {
      'variant_id': 'var-c1',
      'product_name': 'UltraTech Cement 50kg',
      'sku': 'CEM-UT-50',
      'quantity': 4.0,
      'available': 4.0,
      'available_stock': 4.0,
      'reorder_level': 20.0,
      'max_stock': 100.0,
      'average_cost': 350.0,
      'stock_value': 1400.0,
      'net_sold_qty': 120.0,
      'avg_daily_sales': 4.0,
      'days_cover': 1.0,
      'suggested_reorder': 96.0,
      'status': 'low_stock',
      'abc_class': 'A',
    }
  ];

  @override
  Future<List<Map<String, dynamic>>> getCustomerCreditIntelligence({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 1000,
  }) async => [
    {
      'customer_id': 'cust-1',
      'customer_name': 'Apex Contractors',
      'credit_limit': 100000.0,
      'total_outstanding': 85000.0,
      'available_credit': 15000.0,
      'utilization_pct': 85.0,
      'current_amount': 60000.0,
      'days_1_30': 15000.0,
      'days_31_60': 10000.0,
      'days_61_90': 0.0,
      'days_90_plus': 0.0,
      'status': 'current',
    }
  ];

  @override
  Future<List<Map<String, dynamic>>> getSupplierPayablesIntelligence({
    required String tenantId,
    String? locationId,
    String query = '',
    int limit = 1000,
  }) async => [
    {
      'supplier_id': 'sup-1',
      'supplier_name': 'Birla Materials Ltd',
      'total_outstanding': 42000.0,
      'current_amount': 38000.0,
      'days_1_30': 4000.0,
      'days_31_60': 0.0,
      'days_61_90': 0.0,
      'days_90_plus': 0.0,
      'status': 'current',
    }
  ];
}
